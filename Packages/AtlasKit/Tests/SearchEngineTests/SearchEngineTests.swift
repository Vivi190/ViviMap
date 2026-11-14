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

/// The queries that failed in the search benchmark (14.11.2026) and what the focused request asks Photon.
struct FocusedSearchTests {
    @Test func kindWordsBecomeAnOSMFilter() throws {
        let station = try #require(PlaceRanking.focus("Kartal Metro İstasyonu"))
        #expect(station.name == "kartal")
        #expect(station.tags.contains("railway:station"))
        let mall = try #require(PlaceRanking.focus("akasya avm"))
        #expect(mall.name == "akasya")
        #expect(mall.tags == ["shop:mall"])
    }

    @Test func aStopNamedAfterTheMetroIsStillAStop() throws {
        let stop = try #require(PlaceRanking.focus("kartal metro durağı"))
        #expect(stop.name == "kartal metro")
        #expect(stop.tags.contains("highway:bus_stop"))
    }

    @Test func noKindOrNothingLeftMeansOneRequest() {
        #expect(PlaceRanking.focus("kartal adliyesi") == nil)
        #expect(PlaceRanking.focus("metro") == nil)
    }

    @Test func focusedRequestCarriesTheFilters() throws {
        let request = PhotonSearchProvider().request("kartal", near: nil, tags: ["railway:station", "railway:halt"])
        let url = try #require(request.url)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.filter { $0.name == "osm_tag" }.map(\.value) == ["railway:station", "railway:halt"])
        #expect(items.first { $0.name == "q" }?.value == "kartal")
        #expect(items.first { $0.name == "lang" }?.value == "default")
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
