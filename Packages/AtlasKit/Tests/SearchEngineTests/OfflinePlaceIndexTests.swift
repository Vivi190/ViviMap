import Foundation
import SQLite3
import Testing
@testable import SearchEngine

struct TurkishFoldTests {
    // Same cases as Tools/search/build_index.py --self-test: index and query must fold identically.
    @Test func matchesTheIndexBuilder() {
        #expect(TurkishFold.fold("İstanbul Çanakkale Iğdır Şişli Gümüşpınar") == "istanbul canakkale igdir sisli gumuspinar")
    }

    @Test func prefersTheSpellingWithTurkishLetters() {
        let spellings = TurkishFold.preferredSpellings(["Canakkale Caddesi", "Çanakkale Caddesi", "Canakkale Caddesi", "Ankara Caddesi"])
        #expect(spellings[TurkishFold.fold("Canakkale Caddesi")] == "Çanakkale Caddesi")
        #expect(spellings[TurkishFold.fold("Ankara Caddesi")] == "Ankara Caddesi")
        #expect(spellings.count == 2)
    }
}

struct OfflinePlaceIndexTests {
    /// A small index in the builder's schema (place + FTS4 over folded names).
    private func index() throws -> OfflinePlaceIndex {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("places-\(UUID()).sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let rows: [(String, String, String?, Double, Double)] = [
            ("İstanbul Anadolu Adalet Sarayı", "Endam Sokağı", "amenity=courthouse", 40.9145, 29.1782),
            ("Çanakkale Caddesi", "", "highway=secondary", 40.9005, 29.1722), // Kartal
            ("Çanakkale Caddesi", "", "highway=residential", 41.0400, 28.9000), // across the city
            ("Kartal", "", "place=town", 40.8890, 29.1905),
            // Nearest from the Kartal coast in the real index (14.11.2026): BP 189 m, Shell 785 m; Opet across the city.
            ("Opet", "", "amenity=fuel", 41.0500, 28.9500),
            ("BP", "", "amenity=fuel", 40.8905, 29.1910),
            ("Shell", "", "amenity=fuel", 40.8950, 29.1920),
            ("Migros", "", "shop=supermarket", 40.8900, 29.1900),
            ("Tekel", "", "shop=convenience", 40.8950, 29.1950),
            // Two districts of one name, as Istanbul has (Kartal and Şişli).
            ("Esentepe", "", "place=suburb", 40.9070, 29.1850),
            ("Esentepe", "", "place=suburb", 41.0800, 29.0100),
        ]
        var sql = """
        CREATE TABLE place (id INTEGER PRIMARY KEY, name TEXT NOT NULL, subtitle TEXT NOT NULL, category TEXT, lat REAL NOT NULL, lon REAL NOT NULL);
        CREATE VIRTUAL TABLE place_fts USING fts4(folded, tokenize=unicode61);
        """
        for (id, row) in rows.enumerated() {
            let category = row.2.map { "'\($0)'" } ?? "NULL"
            sql += "INSERT INTO place VALUES (\(id + 1), '\(row.0)', '\(row.1)', \(category), \(row.3), \(row.4));"
            sql += "INSERT INTO place_fts (docid, folded) VALUES (\(id + 1), '\(TurkishFold.fold(row.0))');"
        }
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        return OfflinePlaceIndex(url: url)
    }

    @Test func findsWithOrWithoutTurkishLetters() async throws {
        let index = try index()
        #expect(try await index.search("adalet", near: nil).map(\.name) == ["İstanbul Anadolu Adalet Sarayı"])
        #expect(try await index.search("ISTANBUL ANAD", near: nil).count == 1) // prefix, any case
        #expect(try await index.search("çanakkale", near: nil).count == 2)
        #expect(try await index.search("canakkale", near: nil).count == 2)
    }

    @Test func nearerSameNameComesFirst() async throws {
        let kartal = GeoPoint(latitude: 40.8890, longitude: 29.1905)
        let found = try await index().search("Çanakkale Caddesi", near: kartal)
        #expect(found.first?.point.latitude == 40.9005)
        #expect(found.first?.category == "highway=secondary")
    }

    @Test func anAddressFindsItsStreet() async throws {
        // No house numbers offline: "Çanakkale Cad. No:5" finds the street, the nearer one first.
        let kartal = GeoPoint(latitude: 40.8890, longitude: 29.1905)
        let found = try await index().search("Çanakkale Cad. No:5", near: kartal)
        #expect(found.first?.name == "Çanakkale Caddesi")
        #expect(found.first?.point.latitude == 40.9005)
    }

    @Test func aDistrictNamedLastSaysWhereToLook() async throws {
        // Names only in the index: "Kartal" matches no street, so it ranks the streets by distance from Kartal.
        let found = try await index().search("Çanakkale Caddesi Kartal", near: nil)
        #expect(found.count == 2)
        #expect(found.first?.point.latitude == 40.9005)
    }

    @Test func theNearestOfTwoSameNamedDistricts() throws {
        let shipped = try index()
        let kartal = GeoPoint(latitude: 40.8890, longitude: 29.1905)
        let sisli = GeoPoint(latitude: 41.0600, longitude: 28.9900)
        #expect(try shipped.place(named: "Esentepe", near: kartal)?.point.latitude == 40.9070)
        #expect(try shipped.place(named: "esentepe", near: sisli)?.point.latitude == 41.0800)
        #expect(try shipped.place(named: "Kartal", near: nil)?.category == "place=town")
        #expect(try shipped.place(named: "Çanakkale Caddesi", near: kartal) == nil) // a street, not a district
    }

    @Test func aBareKindListsTheNearest() async throws {
        let kartal = GeoPoint(latitude: 40.8890, longitude: 29.1905)
        #expect(try await index().search("en yakın benzinlik", near: kartal).map(\.name) == ["BP", "Shell", "Opet"])
        // A kind of two categories, beyond the four "Yakında" buttons.
        #expect(try await index().search("marketler", near: kartal).map(\.name) == ["Migros", "Tekel"])
    }

    /// "Yakındaki otoparklar" on a destination's card: the nearest around the destination, not around the user.
    @MainActor
    @Test func nearestAroundAPlaceNotTheUser() async throws {
        let defaults = try #require(UserDefaults(suiteName: "atlas-tests-\(UUID())"))
        let shipped = try index()
        let search = SearchController(provider: Fixed(), nearbyIndex: shipped, defaults: defaults)
        search.origin = { GeoPoint(latitude: 41.05, longitude: 28.95) } // the user, by Opet across the city
        let destination = Place(id: "d", name: "Hedef", subtitle: "", point: GeoPoint(latitude: 40.8890, longitude: 29.1905), category: nil)
        search.showNearby(.fuel, around: destination)
        #expect(search.nearbyCenter == destination)
        for _ in 0 ..< 40 where search.results.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        #expect(search.results.map(\.name) == ["BP", "Shell", "Opet"])
        search.query = "kartal" // typing searches around the user again
        #expect(search.nearbyCenter == nil)
    }

    @Test func punctuationOnlyFindsNothing() async throws {
        #expect(try await index().search(" - ' ", near: nil).isEmpty)
    }

    @Test func nearbyListsOneKindNearestFirst() throws {
        let kartal = GeoPoint(latitude: 40.8890, longitude: 29.1905)
        let index = try index()
        #expect(try index.nearby(.fuel, near: kartal).map(\.name) == ["BP", "Shell", "Opet"])
        #expect(try index.nearby(.fuel, near: kartal, limit: 1).map(\.name) == ["BP"])
        #expect(try index.nearby(.charging, near: kartal).isEmpty)
    }
}

private struct Failing: PlaceSearchProvider {
    let error: any Error
    func search(_: String, near _: GeoPoint?) async throws -> [Place] { throw error }
}

private struct Fixed: PlaceSearchProvider {
    func search(_ query: String, near _: GeoPoint?) async throws -> [Place] {
        [Place(id: "x", name: query, subtitle: "", point: GeoPoint(latitude: 41, longitude: 29), category: nil)]
    }
}

struct SearchErrorMessageTests {
    @Test func blamesTheConnectionOnlyWhenThereIsNone() {
        #expect(SearchController.message(for: URLError(.notConnectedToInternet)).hasPrefix("İnternet bağlantısı yok"))
        #expect(SearchController.message(for: PhotonSearchProvider.HTTPError(status: 502)).hasPrefix("Arama sunucusu"))
        #expect(SearchController.message(for: URLError(.timedOut)).hasPrefix("Arama sunucusu"))
    }
}

struct FallbackSearchProviderTests {
    @Test func offlineAnswersOnlyWhenTheNetworkFails() async throws {
        let offline = FallbackSearchProvider(primary: Failing(error: URLError(.notConnectedToInternet)), fallback: Fixed())
        #expect(try await offline.search("kartal", near: nil).map(\.name) == ["kartal"])
        let broken = FallbackSearchProvider(primary: Failing(error: CocoaError(.fileReadCorruptFile)), fallback: Fixed())
        await #expect(throws: CocoaError.self) { try await broken.search("kartal", near: nil) }
        let noIndex = FallbackSearchProvider(primary: Failing(error: URLError(.timedOut)), fallback: nil)
        await #expect(throws: URLError.self) { try await noIndex.search("kartal", near: nil) }
        // Cancelled by the next keystroke: nobody waits for an answer, so the index is not asked.
        let cancelled = FallbackSearchProvider(primary: Failing(error: URLError(.cancelled)), fallback: Fixed())
        await #expect(throws: URLError.self) { try await cancelled.search("kartal", near: nil) }
    }

    @Test func aServerOutageAlsoFallsBack() async throws {
        let busy = FallbackSearchProvider(primary: Failing(error: PhotonSearchProvider.HTTPError(status: 502)), fallback: Fixed())
        #expect(try await busy.search("kartal", near: nil).map(\.name) == ["kartal"])
        let limited = FallbackSearchProvider(primary: Failing(error: PhotonSearchProvider.HTTPError(status: 429)), fallback: Fixed())
        #expect(try await limited.search("kartal", near: nil).map(\.name) == ["kartal"])
        let badRequest = FallbackSearchProvider(primary: Failing(error: PhotonSearchProvider.HTTPError(status: 400)), fallback: Fixed())
        await #expect(throws: PhotonSearchProvider.HTTPError.self) { try await badRequest.search("kartal", near: nil) }
    }
}
