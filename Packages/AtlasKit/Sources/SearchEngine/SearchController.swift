import Foundation
import Observation

/// Drives the search screen: debounced queries, cancellation of stale requests, recent places.
@MainActor
@Observable
public final class SearchController {
    public var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }

    public private(set) var results: [Place] = []
    public private(set) var isSearching = false
    public private(set) var errorMessage: String?
    /// The place "Yakındaki otoparklar" listed around; distances are measured from it. nil: from the user.
    public private(set) var nearbyCenter: Place?
    public private(set) var recents: [Place]
    /// Places the driver starred, newest first; kept on the device only.
    public private(set) var saved: [Place]
    public private(set) var home: Place?
    public private(set) var work: Place?

    public enum Slot: String, Sendable {
        case home, work
    }

    /// Biases results towards the user; read when a search starts.
    @ObservationIgnored public var origin: @MainActor () -> GeoPoint? = { nil }
    @ObservationIgnored private let provider: any PlaceSearchProvider
    /// Answers "Yakında: Benzinlik"; nil in builds without the offline packages, and the buttons are hidden.
    @ObservationIgnored private let nearbyIndex: OfflinePlaceIndex?
    /// The businesses of the same kinds, listed with the street index's (nil in builds without it).
    @ObservationIgnored private let businessIndex: OfflinePlaceIndex?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?

    private static let recentsKey = "atlas.recentPlaces"
    private static let savedKey = "atlas.savedPlaces"
    private static let maxRecents = 12

    /// Photon online, the shipped street index without a connection, and with either the shipped business index
    /// (in builds that carry them).
    public nonisolated static var standardProvider: any PlaceSearchProvider {
        let streets = FallbackSearchProvider(
            primary: PhotonSearchProvider(districts: OfflinePlaceIndex.bundled), fallback: OfflinePlaceIndex.bundled
        )
        guard let businesses = OfflinePlaceIndex.businesses else { return streets }
        return BusinessSearchProvider(base: streets, businesses: businesses, districts: OfflinePlaceIndex.bundled)
    }

    public init(
        provider: any PlaceSearchProvider = SearchController.standardProvider,
        nearbyIndex: OfflinePlaceIndex? = OfflinePlaceIndex.bundled,
        businessIndex: OfflinePlaceIndex? = OfflinePlaceIndex.businesses,
        defaults: UserDefaults = .standard
    ) {
        self.provider = provider
        self.nearbyIndex = nearbyIndex
        self.businessIndex = businessIndex
        self.defaults = defaults
        recents = defaults.data(forKey: Self.recentsKey).flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
        saved = defaults.data(forKey: Self.savedKey).flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
        home = Self.load(.home, from: defaults)
        work = Self.load(.work, from: defaults)
    }

    /// Home / work shortcuts, kept on the device only.
    public func save(_ place: Place, as slot: Slot) {
        switch slot {
        case .home: home = place
        case .work: work = place
        }
        if let data = try? JSONEncoder().encode(place) { defaults.set(data, forKey: "atlas.saved.\(slot.rawValue)") }
    }

    private static func load(_ slot: Slot, from defaults: UserDefaults) -> Place? {
        defaults.data(forKey: "atlas.saved.\(slot.rawValue)").flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
    }

    /// A point picked on the map: the address there if Photon knows one, otherwise just the coordinate.
    /// The place keeps the exact picked point either way.
    public func place(at point: GeoPoint) async -> Place {
        let coordinates = String(format: "%.5f, %.5f", point.latitude, point.longitude)
        let nearest = try? await PhotonSearchProvider().reverse(point)
        let subtitle = nearest.map { $0.subtitle.isEmpty ? $0.name : "\($0.name), \($0.subtitle)" } ?? coordinates
        return Place(id: "picked:\(coordinates)", name: "Seçilen konum", subtitle: subtitle, point: point, category: nil)
    }

    /// A place badge tapped on the map: its name comes from the map, the rest from Photon when it answers.
    public func place(named name: String, category: String?, at point: GeoPoint) async -> Place {
        Self.place(named: name, category: category, at: point, nearest: try? await PhotonSearchProvider().reverse(point))
    }

    /// The nearest place Photon knows at a badge is usually the badge itself: with the same name its record is
    /// used (address, kind, area), otherwise only its address, which the neighbours share. The place keeps the
    /// name and the point of the map either way, so nothing on screen moves when the answer arrives.
    /// `category`: the kind the map itself gives the badge, kept unless Photon's record has its own.
    nonisolated static func place(named name: String, category: String?, at point: GeoPoint, nearest: Place?) -> Place {
        let coordinates = String(format: "%.5f, %.5f", point.latitude, point.longitude)
        guard let nearest else {
            return Place(id: "map:\(coordinates)", name: name, subtitle: coordinates, point: point, category: category)
        }
        guard TurkishFold.fold(nearest.name) == TurkishFold.fold(name) else {
            return Place(id: "map:\(coordinates)", name: name, subtitle: nearest.subtitle, point: point, category: category)
        }
        return Place(
            id: nearest.id, name: name, subtitle: nearest.subtitle, point: point, category: nearest.category ?? category,
            areaSpan: nearest.areaSpan, streetAddress: nearest.streetAddress
        )
    }

    public func isSaved(_ place: Place) -> Bool {
        saved.contains { $0.id == place.id }
    }

    /// Stars a place, or takes its star away.
    public func toggleSaved(_ place: Place) {
        if isSaved(place) {
            saved.removeAll { $0.id == place.id }
        } else {
            saved.insert(place, at: 0)
        }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.savedKey) }
    }

    /// Call when the user picks a place, so it shows up first next time.
    public func remember(_ place: Place) {
        recents.removeAll { $0.id == place.id }
        recents.insert(place, at: 0)
        recents = Array(recents.prefix(Self.maxRecents))
        if let data = try? JSONEncoder().encode(recents) { defaults.set(data, forKey: Self.recentsKey) }
    }

    public func clearRecents() {
        recents = []
        defaults.removeObject(forKey: Self.recentsKey)
    }

    public var canShowNearby: Bool { nearbyIndex != nil }

    /// "Yakında: Benzinlik": the field shows the kind, the nearest ones come from the shipped index instead of
    /// a text search (Photon matches names, and fuel stations are called "Shell", not "benzinlik").
    /// Editing the field afterwards searches as usual.
    /// With `place`: the nearest ones around it instead ("Yakındaki otoparklar" on a destination's card).
    public func showNearby(_ kind: NearbyKind, around place: Place? = nil) {
        guard let index = nearbyIndex else { return }
        query = kind.title
        task?.cancel() // the text search the line above scheduled
        nearbyCenter = place
        guard let center = place?.point ?? origin() else {
            results = []
            isSearching = false
            errorMessage = "Konumun henüz bilinmiyor."
            return
        }
        isSearching = true
        let businesses = businessIndex
        task = Task {
            let found = await Task.detached {
                let surveyed = (try? index.nearby(kind, near: center)) ?? []
                let listed = (try? businesses?.nearby(kind, near: center)) ?? []
                return BusinessSearchProvider.nearest(surveyed, listed, near: center)
            }.value
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }

    private func scheduleSearch() {
        task?.cancel()
        nearbyCenter = nil // typing searches around the user again
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        guard text.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        if let place = CoordinateQuery.place(from: text) {
            results = [place]
            isSearching = false
            return
        }
        isSearching = true
        let origin = origin()
        let provider = provider
        task = Task {
            try? await Task.sleep(for: .milliseconds(300)) // debounce typing
            guard !Task.isCancelled else { return }
            do {
                let found = try await provider.search(text, near: origin)
                guard !Task.isCancelled else { return }
                results = found
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorMessage = Self.message(for: error)
            }
            isSearching = false
        }
    }

    /// The cause in plain words: no connection, or a search server that did not answer (the public Photon
    /// can fail while the connection is fine, and blaming the connection then misleads).
    nonisolated static func message(for error: any Error) -> String {
        let offline: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed]
        if let url = error as? URLError, offline.contains(url.code) {
            return "İnternet bağlantısı yok. Bağlantını kontrol et."
        }
        return "Arama sunucusu şu an yanıt vermiyor. Biraz sonra yeniden dene."
    }
}
