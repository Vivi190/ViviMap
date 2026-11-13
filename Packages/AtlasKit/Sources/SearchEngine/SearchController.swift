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
    public private(set) var recents: [Place]
    public private(set) var home: Place?
    public private(set) var work: Place?

    public enum Slot: String, Sendable {
        case home, work
    }

    /// Biases results towards the user; read when a search starts.
    @ObservationIgnored public var origin: @MainActor () -> GeoPoint? = { nil }
    @ObservationIgnored private let provider: any PlaceSearchProvider
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?

    private static let recentsKey = "atlas.recentPlaces"
    private static let maxRecents = 12

    public init(provider: any PlaceSearchProvider = PhotonSearchProvider(), defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        recents = defaults.data(forKey: Self.recentsKey).flatMap { try? JSONDecoder().decode([Place].self, from: $0) } ?? []
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

    private func scheduleSearch() {
        task?.cancel()
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
                errorMessage = "Arama yapılamadı. İnternet bağlantını kontrol et."
            }
            isSearching = false
        }
    }
}
