import CoreLocation
import Foundation
import SQLite3

/// Turkish-aware folding shared with Tools/search/build_index.py (`fold`): "Çanakkale" and "canakkale",
/// "Iğdır" and "igdir" become the same text. The two must stay identical or offline search misses.
public enum TurkishFold {
    public static func fold(_ text: String) -> String {
        let lowered = text.replacingOccurrences(of: "İ", with: "i").replacingOccurrences(of: "I", with: "ı").lowercased()
        let map: [Character: Character] = ["ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u", "â": "a", "î": "i", "û": "u"]
        return String(lowered.map { map[$0] ?? $0 })
    }

    /// Folded name → the spelling to show, for names that differ only in Turkish letters or case. The one
    /// with the most Turkish letters wins: OSM has "Canakkale Caddesi" next to "Çanakkale Caddesi" on one road.
    public static func preferredSpellings(_ names: [String]) -> [String: String] {
        var best: [String: String] = [:]
        for name in names {
            let key = fold(name)
            if let current = best[key], turkishLetters(current) >= turkishLetters(name) { continue }
            best[key] = name
        }
        return best
    }

    private static func turkishLetters(_ text: String) -> Int {
        text.filter { "çğıöşüÇĞİÖŞÜ".contains($0) }.count
    }
}

/// "Yakında" on the search screen: kinds a driver looks for nearby, as the index stores them (first OSM key that
/// applies, Tools/search/build_index.py). Only named places are in the index.
public enum NearbyKind: String, CaseIterable, Sendable {
    case fuel = "amenity=fuel"
    case parking = "amenity=parking"
    case pharmacy = "amenity=pharmacy"
    case charging = "amenity=charging_station"
    case market = "shop=supermarket"
    case atm = "amenity=atm"
    case restaurant = "amenity=restaurant"
    case cafe = "amenity=cafe"

    /// Every tag that counts as this kind: a corner shop is a market too, a fast-food place a place to eat.
    public var categories: [String] {
        switch self {
        case .market: [rawValue, "shop=convenience"]
        case .restaurant: [rawValue, "amenity=fast_food"]
        default: [rawValue]
        }
    }

    public var title: String {
        switch self {
        case .fuel: "Benzinlik"
        case .parking: "Otopark"
        case .pharmacy: "Eczane"
        case .charging: "Şarj"
        case .market: "Market"
        case .atm: "ATM"
        case .restaurant: "Restoran"
        case .cafe: "Kafe"
        }
    }

    public var systemImage: String {
        switch self {
        case .fuel: "fuelpump.fill"
        case .parking: "parkingsign"
        case .pharmacy: "cross.case.fill"
        case .charging: "bolt.car.fill"
        case .market: "cart.fill"
        case .atm: "banknote.fill"
        case .restaurant: "fork.knife"
        case .cafe: "cup.and.saucer.fill"
        }
    }
}

/// Place search without a connection: the Istanbul index shipped with the app (Tools/search/build_index.py,
/// OpenStreetMap). Prefix matching on folded names, ranked by how well the name matches, then by distance.
public struct OfflinePlaceIndex: PlaceSearchProvider {
    let url: URL
    /// Leads each place's id, so rows of two indexes never share one.
    let idPrefix: String

    init(url: URL, idPrefix: String = "offline") {
        self.url = url
        self.idPrefix = idPrefix
    }

    /// Present only in builds that carry the offline packages.
    public static let bundled: OfflinePlaceIndex? = shipped("places.sqlite", idPrefix: "offline")
    /// Shops, restaurants, offices and other businesses, in the same schema (Tools/search/build_pois.py,
    /// Overture Maps places): about ten times the businesses OpenStreetMap has for Istanbul.
    public static let businesses: OfflinePlaceIndex? = shipped("pois.sqlite", idPrefix: "poi")

    private static func shipped(_ file: String, idPrefix: String) -> OfflinePlaceIndex? {
        guard let url = Bundle.main.url(forResource: "Offline", withExtension: nil)?.appendingPathComponent(file),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return OfflinePlaceIndex(url: url, idPrefix: idPrefix)
    }

    public func search(_ query: String, near: GeoPoint?) async throws -> [Place] {
        // "benzinlik", "marketler": the nearest of that kind (the index keeps every named place's category).
        if let near, let tags = PlaceRanking.kind(query) {
            return try nearby(categories: tags.map { $0.replacingOccurrences(of: ":", with: "=") }, near: near)
        }
        // "Çanakkale Cad. No:5" spelled out; the index has no house numbers, so it looks for the street.
        let address = PlaceRanking.address(query)
        var words = TurkishFold.fold(address.text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0 != address.houseNumber }
        guard !words.isEmpty else { return [] }
        var found = try rows(matching: words.map { $0 + "*" }.joined(separator: " "), near: near)
        var center = near
        // "ankara caddesi kartal": the index holds names only, so a district named last finds nothing. Without
        // it, and nearest to that district first.
        if found.isEmpty, words.count > 1, let area = try place(named: words[words.count - 1], near: near) {
            words.removeLast()
            found = try rows(matching: words.map { $0 + "*" }.joined(separator: " "), near: area.point)
            center = area.point
        }
        let wanted = words.joined(separator: " ")
        func rank(_ place: Place) -> (Int, Double) {
            let name = TurkishFold.fold(place.name)
            let match = name == wanted ? 0 : name.hasPrefix(wanted) ? 1 : 2
            return (match, center.map { place.point.distance(to: $0) } ?? 0)
        }
        return Array(found.sorted { rank($0) < rank($1) }.prefix(12))
    }

    /// The nearest places of one kind by straight-line distance, from the shipped index alone: instant and
    /// without a connection (2026-11-14 index: 833 fuel stations, 1 151 car parks, 5 195 pharmacies, 87 chargers).
    public func nearby(_ kind: NearbyKind, near point: GeoPoint, limit: Int = 12) throws -> [Place] {
        try nearby(categories: kind.categories, near: point, limit: limit)
    }

    /// The nearest places in any of `categories` ("shop=supermarket", …).
    func nearby(categories: [String], near point: GeoPoint, limit: Int = 12) throws -> [Place] {
        let list = categories.indices.map { "?\($0 + 5)" }.joined(separator: ", ")
        // Longitude degrees shrink with latitude; scaled, the squared sum orders by distance at city scale.
        let sql = """
        SELECT id, name, subtitle, category, lat, lon FROM place WHERE category IN (\(list))
        ORDER BY (lat - ?1) * (lat - ?1) + ((lon - ?2) * ?3) * ((lon - ?2) * ?3) LIMIT ?4
        """
        return try rows(sql) { statement in
            sqlite3_bind_double(statement, 1, point.latitude)
            sqlite3_bind_double(statement, 2, point.longitude)
            sqlite3_bind_double(statement, 3, cos(point.latitude * .pi / 180))
            sqlite3_bind_int(statement, 4, Int32(limit))
            for (offset, category) in categories.enumerated() {
                sqlite3_bind_text(statement, Int32(offset + 5), category, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        }
    }

    /// The district or neighbourhood (`place=*`) called `name`, the one nearest `near`: Istanbul has an
    /// Esentepe in Kartal and one in Şişli. Photon's own place search, asked the same 2026-11-14, put a
    /// Kurtköy in Yalova first and found no Aydınlı.
    public func place(named name: String, near: GeoPoint?) throws -> Place? {
        let folded = TurkishFold.fold(name).split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
        guard !folded.isEmpty else { return nil }
        let center = near ?? GeoPoint(latitude: 41.01, longitude: 28.98) // no fix yet: the city centre
        let sql = """
        SELECT p.id, p.name, p.subtitle, p.category, p.lat, p.lon
        FROM place_fts JOIN place p ON p.id = place_fts.docid
        WHERE place_fts MATCH ?1 AND place_fts.folded = ?2 AND p.category LIKE 'place=%'
        ORDER BY (p.lat - ?3) * (p.lat - ?3) + ((p.lon - ?4) * ?5) * ((p.lon - ?4) * ?5) LIMIT 1
        """
        return try rows(sql) { statement in
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, "\"\(folded)\"", -1, transient) // a phrase: every word, in order
            sqlite3_bind_text(statement, 2, folded, -1, transient)
            sqlite3_bind_double(statement, 3, center.latitude)
            sqlite3_bind_double(statement, 4, center.longitude)
            sqlite3_bind_double(statement, 5, cos(center.latitude * .pi / 180))
        }.first
    }

    /// The places whose names have every word of `query` (as typed so far: the last one may be unfinished),
    /// nearest first. For a caller that ranks them itself (BusinessSearchProvider).
    func matches(_ query: String, near: GeoPoint?, limit: Int = 60) throws -> [Place] {
        let words = BusinessSearchProvider.words(of: query)
        guard !words.isEmpty else { return [] }
        return try rows(matching: words.map { $0 + "*" }.joined(separator: " "), near: near, limit: limit)
    }

    /// Names for a query that matched none, with one of its words respelt: "mediamarket" → "mediamarkt",
    /// "kebabçı uzunlar" → "kebapci uzunlar". A word is replaced by the most common word of the index within one
    /// letter of it (two for words of six letters and more) that, with the rest of the query, names a place.
    /// The first two letters have to be right. nil when no respelling finds anything, and for an index built
    /// without its list of words.
    func respelt(_ query: String, near: GeoPoint?, limit: Int = 60) -> (places: [Place], query: String)? {
        let words = BusinessSearchProvider.words(of: query)
        // A lone short word has too many neighbours to guess among; next to other words they decide.
        let shortest = words.count > 1 ? 3 : 4
        for (index, word) in words.enumerated() where word.count >= shortest {
            for candidate in neighbours(of: word) {
                var respelt = words
                respelt[index] = candidate
                let text = respelt.joined(separator: " ")
                if let found = try? matches(text, near: near, limit: limit), !found.isEmpty { return (found, text) }
            }
        }
        return nil
    }

    /// The three most common words of the index near `word`, the most common first.
    private func neighbours(of word: String) -> [String] {
        let start = String(word.prefix(2))
        guard let candidates = try? terms(from: start, upTo: Self.next(after: start), limit: 20_000) else { return [] }
        let allowed = word.count >= 6 ? 2 : 1
        let near: [(term: String, distance: Int, uses: Int)] = candidates.compactMap { candidate in
            guard candidate.term != word else { return nil }
            let distance = Self.editDistance(word, candidate.term, atMost: allowed)
            return distance <= allowed ? (candidate.term, distance, candidate.uses) : nil
        }
        // A spelling the index has seen five times and more before one it has seen once (somebody else's typing
        // error); among those the nearer one, then the more common: "teknoza" is "teknosa", not "tekno".
        func order(_ entry: (term: String, distance: Int, uses: Int)) -> (Int, Int, Int, String) {
            (entry.uses < 5 ? 1 : 0, entry.distance, -entry.uses, entry.term)
        }
        return near.sorted { order($0) < order($1) }.prefix(3).map { $0.term }
    }

    /// The index's words from `lower` up to, not including, `upper`, with the number of names each is in.
    private func terms(from lower: String, upTo upper: String, limit: Int) throws -> [(term: String, uses: Int)] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT term, documents FROM place_terms WHERE col = '*' AND term >= ?1 AND term < ?2 LIMIT ?3"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, lower, -1, transient)
        sqlite3_bind_text(statement, 2, upper, -1, transient)
        sqlite3_bind_int(statement, 3, Int32(limit))
        var found: [(term: String, uses: Int)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let text = sqlite3_column_text(statement, 0) else { continue }
            found.append((String(cString: text), Int(sqlite3_column_int64(statement, 1))))
        }
        return found
    }

    /// The first text after every text that starts with `prefix`: its last character moved one on.
    static func next(after prefix: String) -> String {
        guard let last = prefix.unicodeScalars.last, let bumped = Unicode.Scalar(last.value + 1) else { return prefix }
        return String(prefix.unicodeScalars.dropLast()) + String(bumped)
    }

    /// Letters to change, add or drop to turn one word into the other; `limit` + 1 as soon as it is more than
    /// `limit` (the caller only asks whether it is that near).
    static func editDistance(_ a: String, _ b: String, atMost limit: Int) -> Int {
        let first = Array(a.unicodeScalars), second = Array(b.unicodeScalars)
        guard abs(first.count - second.count) <= limit else { return limit + 1 }
        var previous = Array(0 ... second.count)
        for (i, x) in first.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: second.count)
            for (j, y) in second.enumerated() {
                current[j + 1] = min(previous[j] + (x == y ? 0 : 1), previous[j + 1] + 1, current[j] + 1)
            }
            guard current.min()! <= limit else { return limit + 1 }
            previous = current
        }
        return min(previous[second.count], limit + 1)
    }

    /// The places with a kind inside a box, the likeliest to exist first: what the map shows as badges. Empty
    /// for an index without weights (the street index).
    public func places(west: Double, south: Double, east: Double, north: Double, limit: Int = 200) -> [Place] {
        let sql = """
        SELECT id, name, subtitle, category, lat, lon FROM place
        WHERE lat BETWEEN ?1 AND ?2 AND lon BETWEEN ?3 AND ?4 AND category IS NOT NULL
        ORDER BY weight DESC LIMIT ?5
        """
        let found = try? rows(sql) { statement in
            sqlite3_bind_double(statement, 1, south)
            sqlite3_bind_double(statement, 2, north)
            sqlite3_bind_double(statement, 3, west)
            sqlite3_bind_double(statement, 4, east)
            sqlite3_bind_int(statement, 5, Int32(limit))
        }
        return found ?? []
    }

    /// One of this index's places by the id it was listed with.
    public func place(id: String) -> Place? {
        guard id.hasPrefix(idPrefix + "-"), let row = Int64(id.dropFirst(idPrefix.count + 1)) else { return nil }
        let found = try? rows("SELECT id, name, subtitle, category, lat, lon FROM place WHERE id = ?1") { statement in
            sqlite3_bind_int64(statement, 1, row)
        }
        return found?.first
    }

    /// What a business gave for reaching it, when the data has it.
    public struct Contact: Sendable, Equatable {
        public let phone: String?
        public let website: URL?
    }

    /// Phone number and website of one of this index's places, or of a place from another source that this
    /// index knows too (the same name within 100 m): a restaurant found through OpenStreetMap gets its number.
    /// nil when there is none, and for an index built without contacts.
    public func contact(of place: Place) -> Contact? {
        var row: Int64?
        if place.id.hasPrefix(idPrefix + "-") {
            row = Int64(place.id.dropFirst(idPrefix.count + 1))
        } else if let twin = (try? matches(place.name, near: place.point, limit: 5))?.first(where: { BusinessSearchProvider.same($0, place) }) {
            row = Int64(twin.id.dropFirst(idPrefix.count + 1))
        }
        guard let row else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT phone, website FROM contact WHERE id = ?1", -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, row)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let phone = sqlite3_column_text(statement, 0).map { String(cString: $0) }
        let website = sqlite3_column_text(statement, 1).flatMap { URL(string: String(cString: $0)) }
        return Contact(phone: phone, website: website)
    }

    /// The nearest matches: a common word is in thousands of names, and any 200 of them would leave out the
    /// ones around the corner.
    private func rows(matching expression: String, near: GeoPoint?, limit: Int = 200) throws -> [Place] {
        let center = near ?? GeoPoint(latitude: 41.01, longitude: 28.98) // no fix yet: the city centre
        let sql = """
        SELECT p.id, p.name, p.subtitle, p.category, p.lat, p.lon
        FROM place_fts JOIN place p ON p.id = place_fts.docid
        WHERE place_fts MATCH ?1
        ORDER BY (p.lat - ?2) * (p.lat - ?2) + ((p.lon - ?3) * ?4) * ((p.lon - ?3) * ?4) LIMIT ?5
        """
        return try rows(sql) { statement in
            sqlite3_bind_text(statement, 1, expression, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(statement, 2, center.latitude)
            sqlite3_bind_double(statement, 3, center.longitude)
            sqlite3_bind_double(statement, 4, cos(center.latitude * .pi / 180))
            sqlite3_bind_int(statement, 5, Int32(limit))
        }
    }

    /// Runs a query whose columns are id, name, subtitle, category, lat, lon.
    private func rows(_ sql: String, bind: (OpaquePointer?) -> Void) throws -> [Place] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }
        var places: [Place] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            places.append(Place(
                id: "\(idPrefix)-\(sqlite3_column_int64(statement, 0))",
                name: text(1) ?? "",
                subtitle: text(2) ?? "",
                point: GeoPoint(latitude: sqlite3_column_double(statement, 4), longitude: sqlite3_column_double(statement, 5)),
                category: text(3) // NULL comes back as nil
            ))
        }
        return places
    }
}

/// Online search first; when it cannot be reached, the offline index answers (if this build has one).
public struct FallbackSearchProvider: PlaceSearchProvider {
    let primary: any PlaceSearchProvider
    let fallback: (any PlaceSearchProvider)?

    public init(primary: any PlaceSearchProvider, fallback: (any PlaceSearchProvider)?) {
        self.primary = primary
        self.fallback = fallback
    }

    public func search(_ query: String, near: GeoPoint?) async throws -> [Place] {
        do {
            return try await primary.search(query, near: near)
        } catch {
            guard let fallback, Self.isOutage(error) else { throw error }
            return try await fallback.search(query, near: near)
        }
    }

    /// No connection, or the server down or rate-limiting (the public Photon answers 502/503 at busy times):
    /// the shipped index can answer. Anything else is a real failure to report.
    static func isOutage(_ error: any Error) -> Bool {
        // A cancelled search (the next keystroke) wants no answer, not one from the shipped index.
        if let error = error as? URLError { return error.code != .cancelled }
        guard let http = error as? PhotonSearchProvider.HTTPError else { return false }
        return http.status >= 500 || http.status == 429
    }
}
