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

    public init(base: any PlaceSearchProvider, businesses: OfflinePlaceIndex) {
        self.base = base
        self.businesses = businesses
    }

    public func search(_ query: String, near: GeoPoint?) async throws -> [Place] {
        // An address with a house number is no business's name: the index has nothing to add.
        guard PlaceRanking.address(query).houseNumber == nil else { return try await base.search(query, near: near) }
        async let answered = base.search(query, near: near)
        let local = (try? candidates(query, near: near)) ?? []
        do {
            return Self.merge(try await answered, local, query: query, near: near)
        } catch {
            // The other provider failed (no connection and no street index, a server error): the businesses
            // still answer, and only an empty list reports the failure.
            if local.isEmpty { throw error }
            return Self.merge([], local, query: query, near: near)
        }
    }

    /// "eczane", "en yakın ATM": the nearest of that kind. Anything else: the nearest names with the words.
    private func candidates(_ query: String, near: GeoPoint?) throws -> [Place] {
        guard let tags = PlaceRanking.kind(query) else { return try businesses.matches(query, near: near) }
        guard let near else { return [] }
        return try businesses.nearby(categories: tags.map { $0.replacingOccurrences(of: ":", with: "=") }, near: near)
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
        func distance(_ place: Place) -> Double { near.map { place.point.distance(to: $0) } ?? 0 }
        // A bus stop or a line named after a place is not that place: it stands for no business and leads nothing.
        func isStop(_ place: Place) -> Bool {
            guard let category = place.category else { return false }
            return PlaceRanking.stops.contains(category) || PlaceRanking.lines.contains(category)
        }
        let fresh = local.filter { candidate in !base.contains { !isStop($0) && same($0, candidate) } }
        if PlaceRanking.kind(query) != nil {
            return Array((base + fresh).sorted { distance($0) < distance($1) }.prefix(limit))
        }

        let asked = words(of: query)
        let wanted = asked.joined(separator: " ")
        /// 0 the name is the query, 1 it starts with it, 2 it has every word; nil when a word is missing.
        func match(_ place: Place) -> Int? {
            let nameWords = Self.words(of: place.name)
            let name = nameWords.joined(separator: " ")
            if name == wanted { return 0 }
            if name.hasPrefix(wanted) { return 1 }
            return asked.allSatisfy { word in nameWords.contains { $0.hasPrefix(word) } } ? 2 : nil
        }

        let kinds = PlaceRanking.wantedKinds(query)
        var leading: [Place] = []
        var matched: [(place: Place, key: Double, order: Int)] = []
        var rest: [Place] = []
        func add(_ place: Place, _ quality: Int) {
            let weight = quality == 0 ? exactWeight : quality == 1 ? prefixWeight : 1
            // Without a position there is no "nearer": by quality alone.
            matched.append((place, near == nil ? Double(quality) : distance(place) * weight, matched.count))
        }
        for place in base {
            let category = place.category ?? ""
            if kinds.contains(category) {
                leading.append(place)
                continue
            }
            guard let quality = match(place), !isStop(place) else {
                rest.append(place)
                continue
            }
            let isArea = category.hasPrefix("place=") || category.hasPrefix("boundary=") || category.hasPrefix("highway=")
            if isArea, quality <= 1 { leading.append(place) } else { add(place, quality) }
        }
        for place in fresh {
            if let quality = match(place) { add(place, quality) }
        }
        matched.sort { ($0.key, $0.order) < ($1.key, $1.order) }
        return Array((leading + matched.map { $0.place } + rest).prefix(limit))
    }

    /// Folded words of a name or a query: "Kıyı Pastanesi - Kartal" → ["kiyi", "pastanesi", "kartal"].
    static func words(of text: String) -> [String] {
        TurkishFold.fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
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
