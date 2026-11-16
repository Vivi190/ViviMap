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

    public var title: String {
        switch self {
        case .fuel: "Benzinlik"
        case .parking: "Otopark"
        case .pharmacy: "Eczane"
        case .charging: "Şarj"
        }
    }

    public var systemImage: String {
        switch self {
        case .fuel: "fuelpump.fill"
        case .parking: "parkingsign"
        case .pharmacy: "cross.case.fill"
        case .charging: "bolt.car.fill"
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
        try nearby(categories: [kind.rawValue], near: point, limit: limit)
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
        let words = TurkishFold.fold(query).split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty else { return [] }
        return try rows(matching: words.map { $0 + "*" }.joined(separator: " "), near: near, limit: limit)
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
