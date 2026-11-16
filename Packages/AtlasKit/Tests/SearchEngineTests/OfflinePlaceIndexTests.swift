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
            // Nearest from the Kartal coast in the real index (2026-11-14): BP 189 m, Shell 785 m; Opet across the city.
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

struct BusinessSearchTests {
    private let here = GeoPoint(latitude: 40.8890, longitude: 29.1905)

    /// A place `metres` north of the Kartal coast.
    private func place(_ name: String, _ metres: Double, id: String, category: String? = nil) -> Place {
        Place(id: id, name: name, subtitle: "", point: GeoPoint(latitude: 40.8890 + metres / 110_540, longitude: 29.1905), category: category)
    }

    /// "kartal" means the district, not the nearest of the businesses with Kartal in their names.
    @Test func aDistrictLeadsTheBusinessesNamedAfterIt() {
        let district = place("Kartal", 900, id: "R1", category: "place=town")
        let merged = BusinessSearchProvider.merge(
            [district], [place("Kartal Çarşı", 30, id: "poi-1"), place("Kartal", 200, id: "poi-2", category: "amenity=restaurant")],
            query: "kartal", near: here
        )
        // After it, the businesses by nearness: one 30 m away that starts with the word, then one named just that.
        #expect(merged.map(\.id) == ["R1", "poi-1", "poi-2"])
    }

    /// Both sources know the brand: nearest first, and a store both have is listed once (the surveyed record).
    @Test func aBrandIsListedNearestFirstAndOnce() {
        let osm = [place("Migros", 1_100, id: "N1", category: "shop=supermarket"), place("Migros", 5_000, id: "N2", category: "shop=supermarket")]
        let businesses = [place("Migros", 300, id: "poi-1"), place("Migros Kartal", 1_130, id: "poi-2")]
        let merged = BusinessSearchProvider.merge(osm, businesses, query: "migros", near: here)
        #expect(merged.map(\.id) == ["poi-1", "N1", "N2"])
    }

    /// A word that describes rather than names: the place round the corner, not the one that starts with it.
    @Test func nearnessOutweighsWhereTheWordStands() {
        let businesses = [place("Veteriner Durağı", 2_300, id: "poi-1"), place("Roza Veteriner Kliniği", 230, id: "poi-2")]
        #expect(BusinessSearchProvider.merge([], businesses, query: "veteriner", near: here).map(\.id) == ["poi-2", "poi-1"])
        // An exact name still leads one four times nearer that only contains it.
        let exact = [place("Noter", 2_000, id: "poi-3"), place("Kartal 3. Noterliği", 600, id: "poi-4")]
        #expect(BusinessSearchProvider.merge([], exact, query: "noter", near: here).map(\.id) == ["poi-3", "poi-4"])
        // Without a position: by how well the name matches.
        #expect(BusinessSearchProvider.merge([], businesses, query: "veteriner", near: nil).map(\.id) == ["poi-1", "poi-2"])
    }

    /// "kartal adliyesi": OpenStreetMap files the courthouse under another name. It leads the pages businesses
    /// made about it, and the bus stop named after it follows.
    @Test func thePlaceOfTheKindAskedForLeads() {
        let courthouse = place("İstanbul Anadolu Adalet Sarayı", 3_000, id: "W1", category: "amenity=courthouse")
        let stop = place("Kartal Adliyesi", 3_050, id: "N9", category: "highway=bus_stop")
        let merged = BusinessSearchProvider.merge(
            [courthouse, stop], [place("Kartal Adliyesi", 3_020, id: "poi-1")], query: "kartal adliyesi", near: here
        )
        #expect(merged.map(\.id) == ["W1", "poi-1", "N9"])
    }

    /// What the other provider found without the words in the name (a spelling it forgave) follows the names.
    @Test func otherAnswersFollowTheNames() {
        let other = place("Kıyı Balık", 100, id: "N1", category: "amenity=restaurant")
        let merged = BusinessSearchProvider.merge([other], [place("Kıyı Pastanesi", 400, id: "poi-1")], query: "kıyı pastanesi", near: here)
        #expect(merged.map(\.id) == ["poi-1", "N1"])
    }

    /// A kind of place has no name to match: everything, nearest first.
    @Test func aKindIsListedNearestFirst() {
        let osm = [place("Şifa Eczanesi", 400, id: "N1", category: "amenity=pharmacy")]
        let businesses = [place("Derman Eczanesi", 150, id: "poi-1", category: "amenity=pharmacy"),
                          place("Sifa Eczanesi Kartal", 420, id: "poi-2", category: "amenity=pharmacy")]
        #expect(BusinessSearchProvider.merge(osm, businesses, query: "en yakın eczane", near: here).map(\.id) == ["poi-1", "N1"])
    }

    @Test func theSameBusinessInBothSources() {
        #expect(BusinessSearchProvider.same(place("Migros", 0, id: "a"), place("Migros Kartal", 60, id: "b")))
        #expect(BusinessSearchProvider.same(place("ŞİFA ECZANESİ", 0, id: "a"), place("Sifa Eczanesi", 10, id: "b")))
        // Another business next door, and the same chain down the road.
        #expect(!BusinessSearchProvider.same(place("Migros", 0, id: "a"), place("BİM", 20, id: "b")))
        #expect(!BusinessSearchProvider.same(place("Migros", 0, id: "a"), place("Migros", 400, id: "b")))
    }

    private struct Failing: PlaceSearchProvider {
        func search(_: String, near _: GeoPoint?) async throws -> [Place] { throw URLError(.notConnectedToInternet) }
    }

    private struct Fixed: PlaceSearchProvider {
        let places: [Place]
        func search(_: String, near _: GeoPoint?) async throws -> [Place] { places }
    }

    /// An index of businesses in the builder's schema.
    private func businesses() throws -> OfflinePlaceIndex {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pois-\(UUID()).sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        // Name, kind, latitude and weight (how likely the place is to exist, in percent).
        let rows: [(String, String?, Double, Int)] = [
            ("Kıyı Pastanesi", "amenity=cafe", 40.8910, 60), ("Kıyı Pastanesi", "amenity=cafe", 40.9300, 90),
            ("Derman Eczanesi", "amenity=pharmacy", 40.8900, 95), ("Ankara Caddesi Büfe", nil, 40.8895, 99),
        ]
        var sql = """
        CREATE TABLE place (id INTEGER PRIMARY KEY, name TEXT NOT NULL, subtitle TEXT NOT NULL, category TEXT, lat REAL NOT NULL, lon REAL NOT NULL, weight INTEGER NOT NULL);
        CREATE VIRTUAL TABLE place_fts USING fts4(folded, tokenize=unicode61);
        CREATE VIRTUAL TABLE place_terms USING fts4aux(place_fts);
        CREATE TABLE contact (id INTEGER PRIMARY KEY, phone TEXT, website TEXT);
        INSERT INTO contact VALUES (1, '+902164830420', 'http://www.kiyipastanesi.com');
        INSERT INTO contact VALUES (3, '+902163066161', NULL);
        """
        for (id, row) in rows.enumerated() {
            let category = row.1.map { "'\($0)'" } ?? "NULL"
            sql += "INSERT INTO place VALUES (\(id + 1), '\(row.0)', '', \(category), \(row.2), 29.1905, \(row.3));"
            sql += "INSERT INTO place_fts (docid, folded) VALUES (\(id + 1), '\(TurkishFold.fold(row.0))');"
        }
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        return OfflinePlaceIndex(url: url, idPrefix: "poi")
    }

    @Test func theIndexAnswersWhenTheOtherProviderCannot() async throws {
        let provider = BusinessSearchProvider(base: Failing(), businesses: try businesses())
        // Nearest first, with the index's own ids.
        #expect(try await provider.search("kiyi past", near: here).map(\.id) == ["poi-1", "poi-2"])
        #expect(try await provider.search("eczane", near: here).map(\.name) == ["Derman Eczanesi"])
        // Nothing of its own to offer: the failure is reported.
        await #expect(throws: URLError.self) { try await provider.search("migros", near: here) }
    }

    /// What the map shows of a view: the places with a kind, the likeliest first.
    @Test func thePlacesOfAMapView() throws {
        let index = try businesses()
        let view = index.places(west: 29.18, south: 40.885, east: 29.20, north: 40.895)
        #expect(view.map(\.name) == ["Derman Eczanesi", "Kıyı Pastanesi"]) // the kiosk has no kind, the other cafe is out of view
        #expect(index.places(west: 29.18, south: 40.885, east: 29.20, north: 40.895, limit: 1).map(\.id) == ["poi-3"])
        // A tapped badge hands its id back.
        #expect(index.place(id: "poi-1")?.name == "Kıyı Pastanesi")
        #expect(index.place(id: "offline-1") == nil)
        #expect(index.place(id: "poi-99") == nil)
    }

    @Test func aBusinessGivesItsPhoneAndWebsite() throws {
        let index = try businesses()
        let own = try #require(index.place(id: "poi-1"))
        #expect(index.contact(of: own) == OfflinePlaceIndex.Contact(phone: "+902164830420", website: URL(string: "http://www.kiyipastanesi.com")))
        // A place of another source that the index knows too: the same name within 100 m.
        let osm = Place(id: "N7", name: "Derman Eczanesi", subtitle: "", point: GeoPoint(latitude: 40.89005, longitude: 29.1905), category: "amenity=pharmacy")
        #expect(index.contact(of: osm)?.phone == "+902163066161")
        #expect(index.contact(of: osm)?.website == nil)
        // Nothing on record, and nobody of that name nearby.
        let kiosk = try #require(index.place(id: "poi-4"))
        #expect(index.contact(of: kiosk) == nil)
        #expect(index.contact(of: place("Migros", 100, id: "N8")) == nil)
    }

    /// A word typed wrong: the spelling the index knows that, with the rest of the query, names a place.
    @Test func aMisspeltWordIsRespelt() async throws {
        let index = try businesses()
        let respelt = try #require(index.respelt("kıyı pastenesi", near: here))
        #expect(respelt.query == "kiyi pastanesi")
        #expect(respelt.places.map(\.id) == ["poi-1", "poi-2"])
        // Nothing near enough, and a lone short word is not guessed at.
        #expect(index.respelt("migros", near: here) == nil)
        #expect(index.respelt("kıy", near: here) == nil)

        let provider = BusinessSearchProvider(base: Failing(), businesses: index)
        #expect(try await provider.search("kıyı pastenesi", near: here).map(\.id) == ["poi-1", "poi-2"])
        // The other provider has a name with the words as typed: they were right, and nothing is respelt.
        let asTyped = place("Kıyı Pastenesi Büfe", 50, id: "N3")
        let both = BusinessSearchProvider(base: Fixed(places: [asTyped]), businesses: index)
        #expect(try await both.search("kıyı pastenesi", near: here).map(\.id) == ["N3"])
    }

    @Test func lettersBetweenTwoWords() {
        #expect(OfflinePlaceIndex.editDistance("mediamarket", "mediamarkt", atMost: 2) == 1)
        #expect(OfflinePlaceIndex.editDistance("kebabci", "kebapci", atMost: 1) == 1)
        #expect(OfflinePlaceIndex.editDistance("bauhouse", "bauhaus", atMost: 2) == 2)
        #expect(OfflinePlaceIndex.editDistance("migros", "migros", atMost: 1) == 0)
        // Further apart than asked about: one more than the limit, whatever the true number.
        #expect(OfflinePlaceIndex.editDistance("migros", "akbank", atMost: 2) == 3)
        #expect(OfflinePlaceIndex.next(after: "me") == "mf")
    }

    /// An apostrophe joins, the way people type: "mcdonalds" is "McDonald's".
    @Test func anApostropheJoinsTheWord() {
        #expect(BusinessSearchProvider.words(of: "McDonald's Kartal") == ["mcdonalds", "kartal"])
        #expect(BusinessSearchProvider.quality(of: "McDonald's", asked: ["mcdonalds"]) == 0)
        #expect(BusinessSearchProvider.quality(of: "McDonald's Kartal", asked: ["mcdonald"]) == 1)
        #expect(BusinessSearchProvider.quality(of: "Burger King", asked: ["mcdonalds"]) == nil)
    }

    /// The nearest of a kind from both indexes, each place once.
    @Test func theNearestOfAKindFromBothSources() {
        let surveyed = [place("Şifa Eczanesi", 400, id: "N1", category: "amenity=pharmacy")]
        let listed = [place("Derman Eczanesi", 150, id: "poi-1", category: "amenity=pharmacy"),
                      place("Sifa Eczanesi Kartal", 420, id: "poi-2", category: "amenity=pharmacy")]
        #expect(BusinessSearchProvider.nearest(surveyed, listed, near: here).map(\.id) == ["poi-1", "N1"])
        #expect(NearbyKind.market.categories == ["shop=supermarket", "shop=convenience"])
        #expect(NearbyKind.fuel.categories == ["amenity=fuel"])
    }

    /// "esentepe eczane": the pharmacies around that district, not around the driver.
    @Test func aKindNextToADistrictIsSearchedAroundTheDistrict() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("streets-\(UUID()).sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        // One district, 20 km north of the driver.
        let sql = """
        CREATE TABLE place (id INTEGER PRIMARY KEY, name TEXT NOT NULL, subtitle TEXT NOT NULL, category TEXT, lat REAL NOT NULL, lon REAL NOT NULL);
        CREATE VIRTUAL TABLE place_fts USING fts4(folded, tokenize=unicode61);
        INSERT INTO place VALUES (1, 'Esentepe', '', 'place=suburb', 41.0700, 29.1905);
        INSERT INTO place_fts (docid, folded) VALUES (1, 'esentepe');
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        // The index's pharmacy is at the driver; the other provider knows one in the district.
        let inDistrict = Place(id: "N5", name: "Esentepe Eczanesi", subtitle: "", point: GeoPoint(latitude: 41.0705, longitude: 29.1905), category: "amenity=pharmacy")
        let provider = BusinessSearchProvider(
            base: Fixed(places: [inDistrict]), businesses: try businesses(), districts: OfflinePlaceIndex(url: url)
        )
        // Both are pharmacies; the one in the district named comes first.
        #expect(try await provider.search("esentepe eczane", near: here).map(\.id) == ["N5", "poi-3"])
    }

    @MainActor
    @Test func aStarredPlaceIsKept() throws {
        let defaults = try #require(UserDefaults(suiteName: "atlas.test.\(UUID())"))
        let cafe = place("Kıyı Pastanesi", 200, id: "N1", category: "amenity=cafe")
        let controller = SearchController(provider: Fixed(places: []), nearbyIndex: nil, businessIndex: nil, defaults: defaults)
        #expect(!controller.isSaved(cafe))
        controller.toggleSaved(cafe)
        #expect(controller.saved == [cafe])
        // The next launch reads it back.
        let relaunched = SearchController(provider: Fixed(places: []), nearbyIndex: nil, businessIndex: nil, defaults: defaults)
        #expect(relaunched.isSaved(cafe))
        controller.toggleSaved(cafe)
        #expect(controller.saved.isEmpty)
    }

    /// An address with a house number is no business's name.
    @Test func anAddressIsLeftToTheOtherProvider() async throws {
        let address = place("Ankara Caddesi 12", 100, id: "N1", category: "building=yes")
        let provider = BusinessSearchProvider(base: Fixed(places: [address]), businesses: try businesses())
        #expect(try await provider.search("Ankara Cad. No:12", near: here).map(\.id) == ["N1"])
    }
}
