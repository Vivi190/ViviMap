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

/// Place search without a connection: the Istanbul index shipped with the app (Tools/search/build_index.py,
/// OpenStreetMap). Prefix matching on folded names, ranked by how well the name matches, then by distance.
public struct OfflinePlaceIndex: PlaceSearchProvider {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    /// Present only in builds that carry the offline packages.
    public static let bundled: OfflinePlaceIndex? = {
        guard let url = Bundle.main.url(forResource: "Offline", withExtension: nil)?.appendingPathComponent("places.sqlite"),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return OfflinePlaceIndex(url: url)
    }()

    public func search(_ query: String, near: GeoPoint?) async throws -> [Place] {
        let words = TurkishFold.fold(query).split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !words.isEmpty else { return [] }
        let found = try rows(matching: words.map { $0 + "*" }.joined(separator: " "))
        let wanted = words.joined(separator: " ")
        func rank(_ place: Place) -> (Int, Double) {
            let name = TurkishFold.fold(place.name)
            let match = name == wanted ? 0 : name.hasPrefix(wanted) ? 1 : 2
            return (match, near.map { place.point.distance(to: $0) } ?? 0)
        }
        return Array(found.sorted { rank($0) < rank($1) }.prefix(12))
    }

    private func rows(matching expression: String) throws -> [Place] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT p.id, p.name, p.subtitle, p.category, p.lat, p.lon
        FROM place_fts JOIN place p ON p.id = place_fts.docid
        WHERE place_fts MATCH ? LIMIT 200
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileReadCorruptFile) }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, expression, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        func text(_ column: Int32) -> String? {
            sqlite3_column_text(statement, column).map { String(cString: $0) }
        }
        var places: [Place] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            places.append(Place(
                id: "offline-\(sqlite3_column_int64(statement, 0))",
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
        } catch let error as URLError {
            guard let fallback else { throw error }
            return try await fallback.search(query, near: near)
        }
    }
}
