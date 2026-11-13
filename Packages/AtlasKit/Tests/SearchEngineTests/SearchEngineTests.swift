import Foundation
import Testing
@testable import SearchEngine

/// Fixtures are real Photon responses saved on 2026-11-13 (Tests/SearchEngineTests/Fixtures).
struct PhotonParserTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func parsesNameSubtitleAndCategory() throws {
        let place = try #require(try PhotonParser.places(from: fixture("photon-kartal-adliyesi")).first)
        #expect(place.name == "İstanbul Anadolu Adalet Sarayı")
        #expect(place.category == "amenity=courthouse")
        #expect(place.subtitle.contains("Kartal"))
        #expect(abs(place.point.latitude - 40.9) < 0.2 && abs(place.point.longitude - 29.1) < 0.3)
    }

    @Test func dropsDuplicateStreetSegments() throws {
        let places = try PhotonParser.places(from: fixture("photon-ankara-caddesi-kartal"))
        #expect(places.filter { $0.name == "Ankara Caddesi" }.count == 1)
    }

    @Test func townhallOutranksBusStopsForBelediye() throws {
        let parsed = try PhotonParser.places(from: fixture("photon-tuzla-belediyesi"))
        #expect(parsed.first?.category == "highway=bus_stop") // Photon's own order, the problem being fixed
        let ranked = PlaceRanking.rank(parsed, query: "Tuzla Belediyesi")
        #expect(ranked.first?.category == "amenity=townhall")
        #expect(ranked.suffix(2).allSatisfy { $0.category == "highway=bus_stop" })
        #expect(ranked.count == parsed.count)
    }

    @Test func stopsStayWhenTheQueryAsksForThem() throws {
        let parsed = try PhotonParser.places(from: fixture("photon-tuzla-belediyesi"))
        #expect(PlaceRanking.rank(parsed, query: "Tuzla Belediyesi durağı").first?.category == "highway=bus_stop")
    }
}

struct CoordinateQueryTests {
    @Test func parsesCommaOrSpaceSeparatedPairs() {
        #expect(CoordinateQuery.place(from: "40.8890, 29.1905")?.point == GeoPoint(latitude: 40.889, longitude: 29.1905))
        #expect(CoordinateQuery.place(from: " 40.8890 29.1905 ") != nil)
    }

    @Test func rejectsTextAndOutOfRangeValues() {
        #expect(CoordinateQuery.place(from: "Kartal 34") == nil)
        #expect(CoordinateQuery.place(from: "95.0, 29.0") == nil)
        #expect(CoordinateQuery.place(from: "40.88") == nil)
    }
}
