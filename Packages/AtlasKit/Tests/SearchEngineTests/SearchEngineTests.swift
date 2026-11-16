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

struct AreaSpanTests {
    @Test func areasGetTheirSizeStreetsAndPointsDoNot() throws {
        // Extents as Photon gives them ([west, north, east, south]); the airport's is Sabiha Gökçen's.
        let json = """
        {"features":[
          {"geometry":{"coordinates":[29.3118,40.8943]},"properties":{"osm_type":"R","osm_id":1,"osm_key":"aeroway","osm_value":"aerodrome","name":"Sabiha Gökçen Havalimanı","extent":[29.2958,40.9100,29.3290,40.8790]}},
          {"geometry":{"coordinates":[29.20,40.90]},"properties":{"osm_type":"W","osm_id":2,"osm_key":"highway","osm_value":"primary","name":"Ankara Caddesi","extent":[29.18,40.91,29.22,40.89]}},
          {"geometry":{"coordinates":[29.19,40.88]},"properties":{"osm_type":"N","osm_id":3,"osm_key":"amenity","osm_value":"cafe","name":"Kafe"}}
        ]}
        """
        let places = try PhotonParser.places(from: Data(json.utf8))
        let airport = try #require(places.first?.areaSpan)
        #expect(airport > 3_000 && airport < 5_000)
        #expect(places[1].areaSpan == nil) // a street's box is its length
        #expect(places[2].areaSpan == nil)
    }
}

/// The queries that failed in the search benchmark (2026-11-14) and what the focused request asks Photon.
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

    @Test func aKindWordInAStreetNameIsNoKind() {
        #expect(PlaceRanking.focus("istasyon caddesi tuzla") == nil)
        let parking = PlaceRanking.focus("istanbul havalimanı otopark")
        #expect(parking?.name == "istanbul havalimanı")
        #expect(parking?.tags == ["amenity:parking"])
    }

    @Test func theKindAskedForOutranksTheOneItsNameSuggests() throws {
        // "havalimanı" lifts airports; "… otopark" asks for the car park.
        let json = """
        {"features":[
          {"geometry":{"coordinates":[28.7519,41.2753]},"properties":{"osm_type":"W","osm_id":1,"osm_key":"aeroway","osm_value":"aerodrome","name":"İstanbul Havalimanı","city":"Arnavutköy"}},
          {"geometry":{"coordinates":[28.74414,41.25796]},"properties":{"osm_type":"W","osm_id":2,"osm_key":"amenity","osm_value":"parking","name":"İstanbul Havalimanı Otoparkı","street":"Terminal Caddesi","city":"Arnavutköy"}}
        ]}
        """
        let ranked = PlaceRanking.rank(try PhotonParser.places(from: Data(json.utf8)), query: "istanbul havalimanı otopark")
        #expect(ranked.first?.category == "amenity=parking")
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

/// Addresses as they are written in Turkey; search benchmark 2026-11-14: "No:5" and "Cad." sent Photon to
/// notaries and tyre shops.
struct AddressSearchTests {
    @Test func shorthandIsSpelledOutAndTheHouseNumberFound() {
        let yakacik = PlaceRanking.address("Yakacık Mah. Atatürk Cad. No:12 D:5 Kartal/İstanbul")
        #expect(yakacik.text == "yakacık mahallesi atatürk caddesi 12 kartal istanbul")
        #expect(yakacik.houseNumber == "12")
        #expect(PlaceRanking.address("ATATÜRK CAD. DIŞ KAPI NO: 12 İÇ KAPI NO: 3 KARTAL").text == "atatürk caddesi 12 kartal")
        #expect(PlaceRanking.address("Doğa Sk. No:5/2").text == "doğa sokak 5")
        #expect(PlaceRanking.address("Kızılay Blv. No.30").text == "kızılay bulvarı 30")
    }

    @Test func otherQueriesPassUnchanged() {
        let clinic = PlaceRanking.address("Kartal 5 Nolu Aile Sağlığı Merkezi")
        #expect(clinic.text == "Kartal 5 Nolu Aile Sağlığı Merkezi")
        #expect(clinic.houseNumber == nil)
        let typed = PlaceRanking.address("Ankara Caddesi 5 Kartal")
        #expect(typed.text == "Ankara Caddesi 5 Kartal")
        #expect(typed.houseNumber == "5")
    }

    @Test func theAddressOnThatStreetComesFirstThenTheStreet() throws {
        // Photon's answer for the spelled-out query, trimmed, plus a pharmacy at the address itself. The notary
        // is number 12 on another street.
        let json = """
        {"features":[
          {"geometry":{"coordinates":[29.22444,40.91824]},"properties":{"osm_type":"N","osm_id":1,"osm_key":"office","osm_value":"notary","name":"Kartal 24.Noter","street":"Kartal Caddesi","housenumber":"12","district":"Yakacık Çarşı","city":"Kartal"}},
          {"geometry":{"coordinates":[29.22688,40.91783]},"properties":{"osm_type":"W","osm_id":2,"osm_key":"building","osm_value":"residential","name":"Yakacık Çarşı Mahallesi Muhtarlığı","street":"Tarihi Ayazma Caddesi","district":"Yakacık Çarşı","city":"Kartal"}},
          {"geometry":{"coordinates":[29.21590,40.91843]},"properties":{"osm_type":"W","osm_id":3,"osm_key":"highway","osm_value":"tertiary","name":"Atatürk Caddesi","district":"Yakacık Çarşı","city":"Kartal"}},
          {"geometry":{"coordinates":[29.21600,40.91850]},"properties":{"osm_type":"N","osm_id":4,"osm_key":"amenity","osm_value":"pharmacy","name":"Eczane","street":"Atatürk Caddesi","housenumber":"12","district":"Yakacık Çarşı","city":"Kartal"}}
        ]}
        """
        let parsed = try PhotonParser.places(from: Data(json.utf8))
        #expect(parsed[3].streetAddress == "Atatürk Caddesi 12")
        let query = "Yakacık Mah. Atatürk Cad. No:12 D:5 Kartal/İstanbul"
        #expect(PlaceRanking.rank(parsed, query: query).prefix(2).map(\.name) == ["Eczane", "Atatürk Caddesi"])
        #expect(PlaceRanking.rank(parsed.filter { $0.name != "Eczane" }, query: query).first?.name == "Atatürk Caddesi")
    }

    @Test func linesAndPlansSink() throws {
        // Photon's answer for "cevizli tugay yolu", trimmed: a metro line under construction came first.
        let json = """
        {"features":[
          {"geometry":{"coordinates":[29.15987,40.91768]},"properties":{"osm_type":"W","osm_id":1,"osm_key":"railway","osm_value":"construction","name":"Tugay Yolu","street":"Tugay Yolu Caddesi","district":"Cevizli","city":"Maltepe"}},
          {"geometry":{"coordinates":[29.14961,40.91506]},"properties":{"osm_type":"N","osm_id":2,"osm_key":"highway","osm_value":"bus_stop","name":"Tugay Yolu","street":"Bağdat Caddesi","district":"Cevizli","city":"Maltepe"}},
          {"geometry":{"coordinates":[29.16771,40.91864]},"properties":{"osm_type":"W","osm_id":3,"osm_key":"highway","osm_value":"primary","name":"Tugay Yolu Caddesi","district":"Cevizli","city":"Maltepe"}}
        ]}
        """
        let ranked = PlaceRanking.rank(try PhotonParser.places(from: Data(json.utf8)), query: "cevizli tugay yolu")
        #expect(ranked.map(\.category) == ["highway=primary", "highway=bus_stop", "railway=construction"])
    }

    @Test func aStrayCombiningDotIsDropped() throws {
        // As Photon returned the stop by the Yavuz Selim hospital: "i" + U+0307, a doubled dot on screen.
        let json = #"{"features":[{"geometry":{"coordinates":[29.20687,40.90123]},"properties":{"osm_type":"N","osm_id":1,"osm_key":"highway","osm_value":"bus_stop","name":"Yavuz Seli̇m Devlet Hastanesi̇","street":"Yakacık Caddesi","city":"Kartal"}}]}"#
        let place = try #require(try PhotonParser.places(from: Data(json.utf8)).first)
        #expect(place.name == "Yavuz Selim Devlet Hastanesi")
    }
}

/// "benzinlik" by itself: Photon's text search found a station 148 km away (2026-11-14); the nearest are wanted.
struct KindSearchTests {
    @Test func bareKindsWantTheNearest() {
        #expect(PlaceRanking.kind("benzinlik") == ["amenity:fuel"])
        #expect(PlaceRanking.kind("En yakın eczane") == ["amenity:pharmacy"])
        #expect(PlaceRanking.kind("marketler") == ["shop:supermarket", "shop:convenience"])
        #expect(PlaceRanking.kind("yakındaki otoparklar") == ["amenity:parking"])
    }

    @Test func namedPlacesAreNoKind() {
        #expect(PlaceRanking.kind("akasya avm") == nil)
        #expect(PlaceRanking.kind("pendik devlet hastanesi") == nil)
        #expect(PlaceRanking.kind("nöbetçi eczane") == nil) // no duty roster in OSM
    }

    @Test func aKindNextToADistrict() {
        let pharmacy = PlaceRanking.kindAround("esentepe eczane")
        #expect(pharmacy?.tags == ["amenity:pharmacy"])
        #expect(pharmacy?.district == "esentepe")
        #expect(PlaceRanking.kindAround("benzinlik aydınlı")?.district == "aydınlı")
        #expect(PlaceRanking.kindAround("kartal metro istasyonu") == nil) // named after the place: focus finds it
        #expect(PlaceRanking.kindAround("eczane") == nil) // a bare kind
        #expect(PlaceRanking.kindAround("acıbadem hastane") == nil) // the hospital chain, not the district
    }

    @Test func aNamedDistrictPutsNearnessFirst() throws {
        let kurtkoy = GeoPoint(latitude: 40.9147, longitude: 29.3006)
        let url = try #require(PhotonSearchProvider().request("migros", near: kurtkoy, nearnessFirst: true).url)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "location_bias_scale" }?.value == "0")
        let plain = try #require(PhotonSearchProvider().request("migros", near: kurtkoy).url)
        #expect(plain.query?.contains("location_bias_scale") == false)
    }

    @Test func theRequestAsksForTheNearestOfThatKind() throws {
        let request = PhotonSearchProvider().reverseRequest(GeoPoint(latitude: 40.889, longitude: 29.19), tags: ["amenity:fuel"])
        let url = try #require(request.url)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.path == "/reverse")
        #expect(items.filter { $0.name == "osm_tag" }.map(\.value) == ["amenity:fuel"])
        #expect(items.first { $0.name == "limit" }?.value == "12")
        #expect(items.first { $0.name == "radius" }?.value == "15")
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

    /// A location someone sent: the links the map apps and WhatsApp share, read without asking anyone.
    @Test func readsThePointOutOfASharedLink() {
        let kartal = GeoPoint(latitude: 40.889, longitude: 29.1905)
        for link in [
            "https://maps.google.com/?q=40.889,29.1905",
            "https://www.google.com/maps/search/?api=1&query=40.889%2C29.1905",
            "https://www.google.com/maps/@40.889,29.1905,17z",
            "https://maps.google.com/maps?q=loc:40.889,29.1905",
            "https://maps.apple.com/?ll=40.889,29.1905&q=K%C4%B1y%C4%B1%20Pastanesi",
            "https://maps.apple.com/place?coordinate=40.889,29.1905&name=Kartal",
            "https://yandex.com.tr/maps/?pt=29.1905,40.889&z=17",
            "https://yandex.com.tr/maps/?ll=29.1905%2C40.889&z=17",
            "geo:40.889,29.1905",
            "geo:0,0?q=40.889,29.1905(Kartal)",
            "Buradayım: https://maps.google.com/?q=40.889,29.1905",
        ] {
            #expect(CoordinateQuery.place(from: link)?.point == kartal, "\(link)")
        }
    }

    /// A place link of Google's: the place's own point, not where the map was looking, and its name.
    @Test func readsThePlaceOfAGoogleLink() throws {
        let link = "https://www.google.com/maps/place/K%C4%B1y%C4%B1+Pastanesi/@40.8901,29.1899,17z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d40.889!4d29.1905"
        let place = try #require(CoordinateQuery.place(from: link))
        #expect(place.point == GeoPoint(latitude: 40.889, longitude: 29.1905))
        #expect(place.name == "Kıyı Pastanesi")
        #expect(place.subtitle == "Paylaşılan konum")
        // Apple Maps names the place beside its point; a label in a "geo:" address stands in brackets.
        #expect(CoordinateQuery.place(from: "https://maps.apple.com/?ll=40.889,29.1905&q=K%C4%B1y%C4%B1%20Pastanesi")?.name == "Kıyı Pastanesi")
        #expect(CoordinateQuery.place(from: "geo:0,0?q=40.889,29.1905(Kartal)")?.name == "Kartal")
        // Without a name the coordinates are the name.
        #expect(CoordinateQuery.place(from: "https://maps.google.com/?q=40.889,29.1905")?.name == "40.88900, 29.19050")
    }

    /// Links without a point in them are left to the text search: a short link, any other page.
    @Test func leavesOtherLinksAlone() {
        #expect(CoordinateQuery.place(from: "https://maps.app.goo.gl/AbCdEf123456") == nil)
        #expect(CoordinateQuery.place(from: "https://example.com/?q=kartal") == nil)
        #expect(CoordinateQuery.place(from: "geo:0,0") == nil)
        #expect(CoordinateQuery.place(from: "https://yandex.com.tr/maps/-/CDxyzABC") == nil)
    }
}

struct TappedPlaceTests {
    private let point = GeoPoint(latitude: 40.9, longitude: 29.2)
    private let pharmacy = Place(
        id: "N1", name: "Şifa Eczanesi", subtitle: "Ankara Caddesi, Kartal", point: GeoPoint(latitude: 40.90002, longitude: 29.20001),
        category: "amenity=pharmacy", streetAddress: "Ankara Caddesi 12"
    )

    /// The nearest place Photon knows at a badge is usually the badge itself, whatever the spelling.
    @Test func theSameNameTakesPhotonsRecord() {
        let place = SearchController.place(named: "ŞİFA ECZANESİ", category: "shop=chemist", at: point, nearest: pharmacy)
        #expect(place.id == "N1")
        #expect(place.category == "amenity=pharmacy")
        #expect(place.subtitle == "Ankara Caddesi, Kartal")
        #expect(place.streetAddress == "Ankara Caddesi 12")
        // The name and the point stay the map's: nothing on screen moves when the answer arrives.
        #expect(place.name == "ŞİFA ECZANESİ")
        #expect(place.point == point)
    }

    @Test func anotherNameGivesOnlyItsAddress() {
        let place = SearchController.place(named: "Kartal Börek", category: "shop=bakery", at: point, nearest: pharmacy)
        #expect(place.name == "Kartal Börek")
        #expect(place.subtitle == "Ankara Caddesi, Kartal")
        // The kind stays the map's own: the neighbour's says nothing about this place.
        #expect(place.category == "shop=bakery")
        #expect(place.id == "map:40.90000, 29.20000")
        #expect(place.point == point)
    }

    @Test func withoutAnAnswerThePlaceIsItsNameAndCoordinates() {
        let place = SearchController.place(named: "Kartal Börek", category: nil, at: point, nearest: nil)
        #expect(place.name == "Kartal Börek")
        #expect(place.subtitle == "40.90000, 29.20000")
        #expect(place.category == nil)
    }
}
