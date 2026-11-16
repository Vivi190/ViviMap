import Foundation

/// Another provider's answers together with the shipped business index (OfflinePlaceIndex.businesses: shops,
/// restaurants, offices from Overture Maps). OpenStreetMap, which the other providers search, knows the streets
/// and districts of Istanbul and a tenth of its businesses; the index knows the businesses and no streets.
///
/// The index is searched on the device while the other provider's request is on its way, so it adds no wait and
/// answers without a connection.
public struct BusinessSearchProvider: PlaceSearchProvider {
    let base: any PlaceSearchProvider
    let businesses: OfflinePlaceIndex
    /// Finds the district a query names ("kartal kuaför"); nil in builds without the street index.
    let districts: OfflinePlaceIndex?

    public init(base: any PlaceSearchProvider, businesses: OfflinePlaceIndex, districts: OfflinePlaceIndex? = nil) {
        self.base = base
        self.businesses = businesses
        self.districts = districts
    }

    public func search(_ query: String, near: GeoPoint?) async throws -> [Place] {
        // An address with a house number is no business's name: the index has nothing to add.
        guard PlaceRanking.address(query).houseNumber == nil else { return try await base.search(query, near: near) }
        // "kartal kuaför", "veteriner pendik": the nearest of that kind around the district, from both sources.
        if let around = PlaceRanking.kindAround(query), let center = (try? districts?.place(named: around.district, near: near))?.point {
            let categories = around.tags.map { $0.replacingOccurrences(of: ":", with: "=") }
            let listed = (try? businesses.nearby(categories: categories, near: center, limit: Self.limit)) ?? []
            let surveyed = (try? await base.search(query, near: near)) ?? []
            if !listed.isEmpty || !surveyed.isEmpty { return Self.nearest(surveyed, listed, near: center) }
        }
        async let answered = base.search(query, near: near)
        let local: (places: [Place], query: String) = (try? candidates(query, near: near)) ?? ([], query)
        let found: [Place]
        do {
            found = try await answered
        } catch {
            // The other provider failed (no connection and no street index, a server error): the businesses
            // still answer, and only an empty list reports the failure.
            if local.places.isEmpty { throw error }
            return Self.merge([], local.places, query: local.query, near: near)
        }
        // Another spelling was tried because the index had no name with the words as typed. When the other
        // provider has one, the words were right and the place is simply not a business in the index.
        if local.query != query {
            let asked = Self.words(of: query)
            if found.contains(where: { Self.quality(of: $0.name, asked: asked) != nil }) {
                return Self.merge(found, [], query: query, near: near)
            }
        }
        return Self.merge(found, local.places, query: local.query, near: near)
    }

    /// "eczane", "en yakın ATM": the nearest of that kind. Anything else: the nearest names with the words,
    /// and when no name has them, with one word respelt ("mediamarket" → "mediamarkt").
    /// `query` is the one the names answer: the respelt one when that is what found them.
    private func candidates(_ query: String, near: GeoPoint?) throws -> (places: [Place], query: String) {
        if let tags = PlaceRanking.kind(query) {
            guard let near else { return ([], query) }
            return (try businesses.nearby(categories: tags.map { $0.replacingOccurrences(of: ":", with: "=") }, near: near), query)
        }
        let found = try businesses.matches(query, near: near)
        guard found.isEmpty, let respelt = businesses.respelt(query, near: near) else { return (found, query) }
        return respelt
    }

    static let limit = 20
    /// How much nearer a name that is exactly the query, or starts with it, counts than one that only contains
    /// it: an exact match four times as far away still comes first. A plain order by match put a tyre maker
    /// 6 km away ahead of the car wash round the corner for "oto yıkama".
    private static let exactWeight = 0.25, prefixWeight = 0.6

    /// One list from the two sources, in three parts:
    /// 1. the districts and streets the query names (the other provider's, in its order): "kartal" means the
    ///    district, not the nearest of the thousand businesses with Kartal in their names; and the places of the
    ///    kind its words ask for ("kartal adliyesi": the courthouse as surveyed, which OpenStreetMap files under
    ///    another name, before the pages businesses made about it);
    /// 2. the places of either source whose names have the query's words, nearest first, exact and leading
    ///    matches counting as nearer;
    /// 3. what else the other provider found (other spellings, typing errors it forgave), in its order.
    /// A query for a kind of place has no names to match: everything, nearest first.
    static func merge(_ base: [Place], _ local: [Place], query: String, near: GeoPoint?) -> [Place] {
        if PlaceRanking.kind(query) != nil { return nearest(base, local, near: near) }
        func distance(_ place: Place) -> Double { near.map { place.point.distance(to: $0) } ?? 0 }
        // A bus stop or a line named after a place is not that place: it stands for no business and leads nothing.
        func isStop(_ place: Place) -> Bool {
            guard let category = place.category else { return false }
            return PlaceRanking.stops.contains(category) || PlaceRanking.lines.contains(category)
        }
        let fresh = local.filter { candidate in !base.contains { !isStop($0) && same($0, candidate) } }
        let asked = words(of: query)
        let kinds = PlaceRanking.wantedKinds(query)
        var leading: [Place] = []
        var matched: [(place: Place, key: Double, order: Int)] = []
        var rest: [Place] = []
        func add(_ place: Place, _ grade: Int) {
            let weight = grade == 0 ? exactWeight : grade == 1 ? prefixWeight : 1
            // Without a position there is no "nearer": by how well the name answers alone.
            matched.append((place, near == nil ? Double(grade) : distance(place) * weight, matched.count))
        }
        for place in base {
            let category = place.category ?? ""
            if kinds.contains(category) {
                leading.append(place)
                continue
            }
            guard let grade = Self.quality(of: place.name, asked: asked), !isStop(place) else {
                rest.append(place)
                continue
            }
            let isArea = category.hasPrefix("place=") || category.hasPrefix("boundary=") || category.hasPrefix("highway=")
            if isArea, grade <= 1 { leading.append(place) } else { add(place, grade) }
        }
        for place in fresh {
            if let grade = Self.quality(of: place.name, asked: asked) { add(place, grade) }
        }
        matched.sort { ($0.key, $0.order) < ($1.key, $1.order) }
        return Array((leading + matched.map { $0.place } + rest).prefix(limit))
    }

    /// The places of one kind from both sources as one list, nearest first, a business both know listed once.
    static func nearest(_ base: [Place], _ local: [Place], near: GeoPoint?) -> [Place] {
        func distance(_ place: Place) -> Double { near.map { place.point.distance(to: $0) } ?? 0 }
        let fresh = local.filter { candidate in !base.contains { same($0, candidate) } }
        return Array((base + fresh).map { ($0, distance($0)) }.sorted { $0.1 < $1.1 }.map { $0.0 }.prefix(limit))
    }

    /// How well a name answers the words asked for: 0 it is exactly them, 1 it starts with them, 2 it has every
    /// one of them (the last may be unfinished); nil when a word is missing.
    static func quality(of name: String, asked: [String]) -> Int? {
        let nameWords = words(of: name)
        let wanted = asked.joined(separator: " ")
        let whole = nameWords.joined(separator: " ")
        if whole == wanted { return 0 }
        if whole.hasPrefix(wanted) { return 1 }
        return asked.allSatisfy { word in nameWords.contains { $0.hasPrefix(word) } } ? 2 : nil
    }

    /// Folded words of a name or a query: "Kıyı Pastanesi - Kartal" → ["kiyi", "pastanesi", "kartal"]. An
    /// apostrophe joins: "McDonald's" is "mcdonalds", as people type it.
    static func words(of text: String) -> [String] {
        TurkishFold.fold(text).filter { $0 != "'" && $0 != "’" }.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// One business in both sources: within 100 m of each other, and one name's words begin the other's
    /// ("Migros" and "Migros Kartal"). The other provider's record is the one kept (its position is surveyed).
    static func same(_ a: Place, _ b: Place) -> Bool {
        guard a.point.distance(to: b.point) <= 100 else { return false }
        let first = words(of: a.name), second = words(of: b.name)
        guard !first.isEmpty, !second.isEmpty else { return false }
        let (short, long) = first.count <= second.count ? (first, second) : (second, first)
        return Array(long.prefix(short.count)) == short
    }
}
