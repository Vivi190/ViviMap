import CoreLocation
import Foundation
import Testing
@testable import TrafficEngine

struct FlexiblePolylineTests {
    // HERE's documented corridor example (docs.here.com, Traffic API v7 geospatial filters).
    private let berlin = [
        (52.529583, 13.379416), (52.532820, 13.399157), (52.538458, 13.395896), (52.541277, 13.408856), (52.539085, 13.424048),
    ].map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }

    @Test func matchesHEREsDocumentedExample() {
        #expect(FlexiblePolyline.encode(berlin, precision: 6) == "BG-6kmkDw1zwZqqG6xmBsgL5rGmwFgqZ_oEw1d")
    }

    @Test func defaultPrecisionFive() {
        // Same points at precision 5, from the reference algorithm cross-checked on the example above.
        #expect(FlexiblePolyline.encode(berlin) == "BF81zgKsl1xCoUs7DojBrU0RgxC1N--C")
    }
}

struct HEREFlowResponseTests {
    @Test func joinsTheLinksOfEachResult() throws {
        // Flow answer shape with made-up values (HERE's own data is not kept in this public repository): links
        // share their joining points, 3 + 2, 2 + 1 + 2 and 4 of them. The fourth result comes in three
        // sub-segments: the first ends on a vertex, the second in the middle of an edge.
        let url = try #require(Bundle.module.url(forResource: "here-flow-sample", withExtension: "json", subdirectory: "Fixtures"))
        let segments = try HEREFlowResponse.segments(from: Data(contentsOf: url))
        try #require(segments.count == 6)
        #expect(segments.map(\.points.count) == [5, 5, 4, 2, 3, 3])
        #expect(segments[0].jamFactor == 0.6)
        #expect(segments.allSatisfy { !$0.isClosed })
        #expect(segments[0].points.first?.latitude == 40.9)
        // Speeds in m/s, the uncapped one where HERE gives both; every value here is live.
        #expect(segments[0].speed == 12.5)
        #expect(segments[0].freeFlow == 13.9)
        #expect(segments.allSatisfy { $0.isLive })
        // The most important class among a result's links: the fourth has a class 2 and a class 1 link.
        #expect(segments.compactMap { $0.roadClass } == [3, 2, 4, 1, 1, 1])
        #expect(segments.suffix(3).map { $0.jamFactor } == [0.4, 5.6, 8.8])
        #expect(segments[3].speed == 24.1)
    }

    @Test func closedAndUnknown() throws {
        let json = """
        {"results":[
          {"location":{"shape":{"links":[{"points":[{"lat":40.9,"lng":29.2},{"lat":40.901,"lng":29.2}]}]}},
           "currentFlow":{"jamFactor":10.0,"traversability":"closed"}},
          {"location":{"shape":{"links":[{"points":[{"lat":40.9,"lng":29.2},{"lat":40.901,"lng":29.2}]}]}},
           "currentFlow":{"jamFactor":-1.0,"traversability":"open"}}
        ]}
        """
        let segments = try HEREFlowResponse.segments(from: Data(json.utf8))
        #expect(segments[0].isClosed)
        #expect(segments[1].jamFactor == 0)
        // No confidence, no measurement.
        #expect(segments.allSatisfy { !$0.isLive })
    }

    @Test func liveMeansConfidenceAboveSeventyPercent() throws {
        // HERE: above 0.70 real-time data is included, 0.70 is historical only, 0.5 and below the speed limit.
        let json = """
        {"results":[
          {"location":{"shape":{"links":[{"points":[{"lat":40.9,"lng":29.2},{"lat":40.901,"lng":29.2}]}]}},
           "currentFlow":{"jamFactor":1.0,"confidence":0.71,"traversability":"open"}},
          {"location":{"shape":{"links":[{"points":[{"lat":40.9,"lng":29.2},{"lat":40.901,"lng":29.2}]}]}},
           "currentFlow":{"jamFactor":1.0,"confidence":0.70,"traversability":"open"}},
          {"location":{"shape":{"links":[{"points":[{"lat":40.9,"lng":29.2},{"lat":40.901,"lng":29.2}]}]}},
           "currentFlow":{"jamFactor":1.0,"confidence":0.5,"traversability":"open"}}
        ]}
        """
        let segments = try HEREFlowResponse.segments(from: Data(json.utf8))
        #expect(segments.map { $0.isLive } == [true, false, false])
    }

    // A street heading east, a vertex every 0.001° (about 84 m), as two links of HERE's. Written out, not
    // computed: 29.2 + 2 x 0.001 is not the number JSON's 29.202 is.
    private let street = [29.2, 29.201, 29.202, 29.203, 29.204].map { CLLocationCoordinate2D(latitude: 40.9, longitude: $0) }
    private let streetLinks = """
    {"shape":{"links":[
      {"points":[{"lat":40.9,"lng":29.2},{"lat":40.9,"lng":29.201},{"lat":40.9,"lng":29.202}],"functionalClass":3},
      {"points":[{"lat":40.9,"lng":29.202},{"lat":40.9,"lng":29.203},{"lat":40.9,"lng":29.204}],"functionalClass":2}
    ]}}
    """

    @Test func aResultIsCutAtItsSubSegments() throws {
        // Sub-segment lengths are HERE's road lengths (400 m here) and need not match the line as measured
        // (about 337 m): the cuts fall at the same shares of it, a quarter and a half.
        let json = """
        {"results":[{"location":\(streetLinks),
          "currentFlow":{"speed":10.0,"speedUncapped":11.0,"freeFlow":20.0,"jamFactor":4.0,"confidence":0.9,"traversability":"open",
            "subSegments":[
              {"length":100.0,"speed":15.0,"speedUncapped":18.0,"freeFlow":21.0,"jamFactor":1.0,"confidence":0.7,"traversability":"open"},
              {"length":100.0,"jamFactor":6.0},
              {"length":200.0,"speedUncapped":0.0,"jamFactor":10.0,"traversability":"closed"}
            ]}}]}
        """
        let segments = try HEREFlowResponse.segments(from: Data(json.utf8))
        try #require(segments.count == 3)
        // Each piece starts where the last one ended; cuts on a vertex add no point.
        #expect(segments.map(\.points.count) == [2, 2, 3])
        #expect(segments[0].points.last?.longitude == street[1].longitude)
        #expect(segments[1].points.first?.longitude == street[1].longitude)
        #expect(segments[2].points.first?.longitude == street[2].longitude)
        #expect(segments[2].points.last?.longitude == street[4].longitude)
        let total = FlowSegment.metres(along: street)
        #expect(abs(total - 336.6) < 0.1)
        #expect(abs(segments[0].length - total / 4) < 0.001)
        #expect(abs(segments[1].length - total / 4) < 0.001)
        #expect(abs(segments[2].length - total / 2) < 0.001)
        // Each piece has its own values...
        #expect(segments.map { $0.jamFactor } == [1.0, 6.0, 10.0])
        #expect(segments.map { $0.isClosed } == [false, false, true])
        #expect(segments[0].speed == 18)
        #expect(segments[0].freeFlow == 21)
        #expect(!segments[0].isLive)
        // ...and what it leaves out comes from the result: the second piece has only a jam factor.
        #expect(segments[1].speed == 11)
        #expect(segments[1].freeFlow == 20)
        #expect(segments[1].isLive)
        #expect(segments[2].speed == 0)
        // One class for the whole result.
        #expect(segments.compactMap { $0.roadClass } == [2, 2, 2])
    }

    @Test func aCutInsideAnEdgeIsInterpolated() throws {
        // 150 of 400: three eighths of the line, the middle of its second edge.
        let pieces = HEREFlowResponse.cut(street, lengths: [150, 250])
        try #require(pieces.map(\.count) == [3, 4])
        let cutPoint = pieces[0][2]
        #expect(abs(cutPoint.longitude - 29.2015) < 1e-9)
        #expect(cutPoint.latitude == 40.9)
        #expect(pieces[1][0].longitude == cutPoint.longitude)
        let total = FlowSegment.metres(along: street)
        #expect(abs(FlowSegment.metres(along: pieces[0]) - total * 3 / 8) < 0.001)
        #expect(abs(FlowSegment.metres(along: pieces[1]) - total * 5 / 8) < 0.001)
        // A cut within a metre of a vertex moves onto it: 101 of 400 is 0.8 m past the first one.
        #expect(HEREFlowResponse.cut(street, lengths: [101, 299]).map(\.count) == [2, 4])
    }

    @Test func aResultThatCannotBeCutStaysWhole() throws {
        #expect(HEREFlowResponse.cut(street, lengths: []).isEmpty)
        #expect(HEREFlowResponse.cut(street, lengths: [0, 0]).isEmpty)
        #expect(HEREFlowResponse.cut([street[0]], lengths: [100, 100]).isEmpty)
        // A sub-segment without a length: one segment with the values of the result.
        let json = """
        {"results":[{"location":\(streetLinks),
          "currentFlow":{"speed":10.0,"freeFlow":20.0,"jamFactor":4.0,"confidence":0.9,"traversability":"open",
            "subSegments":[{"length":100.0,"jamFactor":1.0},{"jamFactor":6.0}]}}]}
        """
        let segments = try HEREFlowResponse.segments(from: Data(json.utf8))
        try #require(segments.count == 1)
        #expect(segments[0].points.count == 5)
        #expect(segments[0].jamFactor == 4)
        // Only the capped speed is given here.
        #expect(segments[0].speed == 10)
    }
}

struct RouteTrafficTests {
    // Route heading east along a street, ~85 m between points.
    private let route = (0 ... 10).map { CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2 + Double($0) * 0.001) }

    private func segment(_ points: [(Double, Double)], jam: Double, closed: Bool = false) -> FlowSegment {
        FlowSegment(points: points.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }, jamFactor: jam, isClosed: closed)
    }

    @Test func coloursOnlySlowStretchesAlongTheRouteInItsDirection() {
        let flow = [
            segment([(40.9, 29.201), (40.9, 29.203)], jam: 3), // along, same direction, slow
            segment([(40.9, 29.204), (40.9, 29.206)], jam: 1.5), // along but flowing: not coloured
            segment([(40.9001, 29.208), (40.9001, 29.207)], jam: 9), // opposite carriageway: other direction
            segment([(40.899, 29.205), (40.901, 29.205)], jam: 9), // cross street
            segment([(40.9, 29.208), (40.9, 29.21)], jam: 10, closed: true), // along, closed
        ]
        let sections = RouteTraffic.sections(route: route, flow: flow)
        #expect(sections.map(\.level) == [.slow, .stopped])
        // Drawn on the route's own points: 29.201 → 29.203 and 29.208 → 29.210.
        #expect(sections.map(\.coordinates.count) == [3, 3])
        #expect(sections.first?.coordinates.first?.longitude == route[1].longitude)
    }

    @Test func freeFlowLeavesTheRouteUncoloured() {
        #expect(RouteTraffic.sections(route: route, flow: [segment([(40.9, 29.201), (40.9, 29.209)], jam: 1)]).isEmpty)
    }

    @Test func jamBands() {
        // Yellow from 2, red from 8, dark red from 9.5.
        #expect(RouteTraffic.level(segment([(0, 0), (0, 1)], jam: 1.9)) == nil)
        #expect(RouteTraffic.level(segment([(0, 0), (0, 1)], jam: 2)) == .slow)
        #expect(RouteTraffic.level(segment([(0, 0), (0, 1)], jam: 7.9)) == .slow)
        #expect(RouteTraffic.level(segment([(0, 0), (0, 1)], jam: 8)) == .heavy)
        #expect(RouteTraffic.level(segment([(0, 0), (0, 1)], jam: 9.4)) == .heavy)
        #expect(RouteTraffic.level(segment([(0, 0), (0, 1)], jam: 9.5)) == .stopped)
        #expect(RouteTraffic.level(segment([(0, 0), (0, 1)], jam: 10)) == .stopped)
        // A route keeps flagging a closed stretch, whatever its jam factor.
        #expect(RouteTraffic.level(segment([(0, 0), (0, 1)], jam: 1, closed: true)) == .stopped)
    }

    @Test func theRouteIsColouredFromLiveValuesOnly() {
        let along = [(40.9, 29.201), (40.9, 29.203)].map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
        // Usually slow at this hour, not measured now: no colour.
        let usual = FlowSegment(points: along, jamFactor: 6, isClosed: false, isLive: false)
        #expect(RouteTraffic.sections(route: route, flow: [usual]).isEmpty)
        // A closed stretch is flagged even though a closure carries no confidence.
        let closed = FlowSegment(points: along, jamFactor: 10, isClosed: true, isLive: false)
        #expect(RouteTraffic.sections(route: route, flow: [closed]).map(\.level) == [.stopped])
    }

    @Test func flowRequestIsACorridorPost() throws {
        let provider = HERETrafficProvider(apiKey: "k", session: .shared, budget: RequestBudget(defaults: UserDefaults(suiteName: "atlas.test.\(UUID())")!))
        let request = try provider.flowRequest(for: route)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == "data.traffic.hereapi.com")
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let area = try #require(body["in"] as? [String: Any])
        #expect(area["type"] as? String == "corridor")
        // Wide enough for the roads beside the route: the same answer draws the traffic around it.
        #expect(area["radius"] as? Int == 400)
        #expect((area["corridor"] as? String)?.hasPrefix("BF") == true)
        #expect(body["locationReferencing"] as? [String] == ["shape"])
        #expect(body["functionalClasses"] as? [Int] == [1, 2, 3, 4])
    }
}

struct AreaTrafficTests {
    private let kartal = TrafficArea(west: 29.1, south: 40.85, east: 29.3, north: 40.95)

    private func segment(_ points: [(Double, Double)], jam: Double, closed: Bool = false) -> FlowSegment {
        FlowSegment(points: points.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }, jamFactor: jam, isClosed: closed)
    }

    /// A stretch of main road for the score: `metres` long, live and open.
    private func road(_ metres: Double, speed: Double, freeFlow: Double, roadClass: Int? = nil) -> FlowSegment {
        FlowSegment(points: [], jamFactor: 0, isClosed: false, roadClass: roadClass, speed: speed, freeFlow: freeFlow, length: metres)
    }

    @Test func drawsOpenRoadsFlowingOnesGreen() {
        let sections = AreaTraffic.sections([
            segment([(40.90, 29.20), (40.90, 29.21)], jam: 1.5),
            segment([(40.91, 29.20), (40.91, 29.21)], jam: 3),
            segment([(40.92, 29.20), (40.92, 29.21)], jam: 8.5),
            segment([(40.93, 29.20), (40.93, 29.21)], jam: 9.7),
            segment([(40.94, 29.20)], jam: 9), // a single point draws nothing
        ])
        #expect(sections.map(\.level) == [.free, .slow, .heavy, .stopped])
        // HERE's own geometry, untouched: the map offsets each direction when it draws.
        #expect(sections[0].coordinates.first?.latitude == 40.90)
    }

    @Test func closedAndUnmeasuredRoadsAreNotDrawn() {
        let line = [(40.95, 29.20), (40.95, 29.21)].map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
        let sections = AreaTraffic.sections([
            segment([(40.90, 29.20), (40.90, 29.21)], jam: 10, closed: true), // road events draw closures
            FlowSegment(points: line, jamFactor: 1, isClosed: false, isLive: false), // usual speed, not measured: no green
            FlowSegment(points: line, jamFactor: 9, isClosed: false, isLive: false),
            segment([(40.91, 29.20), (40.91, 29.21)], jam: 8.5),
        ])
        #expect(sections.map(\.level) == [.heavy])
    }

    @Test func theScoreIsTheExtraTravelTimeOnMainRoads() {
        // 2 km at 8 m/s where 20 is free: 250 s against 100 s. 2 km faster than free flow count as free: 100 s
        // against 100 s. T = 350 / 200 = 1.75, and 7 x 0.75 = 5.25.
        let roads = [road(2000, speed: 8, freeFlow: 20), road(2000, speed: 30, freeFlow: 20, roadClass: 3)]
        #expect(AreaTraffic.score(roads) == 5)
        // Twice the free-flow time is 7.
        #expect(AreaTraffic.score([road(4000, speed: 10, freeFlow: 20)]) == 7)
        // None of these counts: a side street, a usual speed, a closed road, a road without speeds.
        let others = [
            road(4000, speed: 1, freeFlow: 20, roadClass: 4),
            FlowSegment(points: [], jamFactor: 9, isClosed: false, isLive: false, speed: 1, freeFlow: 20, length: 4000),
            FlowSegment(points: [], jamFactor: 10, isClosed: true, speed: 1, freeFlow: 20, length: 4000),
            FlowSegment(points: [], jamFactor: 9, isClosed: false, length: 4000),
            road(4000, speed: 0, freeFlow: 20),
        ]
        #expect(AreaTraffic.score(roads + others) == 5)
        #expect(AreaTraffic.score(others) == nil)
    }

    @Test func aQueueCountsAsHalfAMetreASecondAndTheScoreStopsAtTen() {
        // 100 m at 0.1 m/s count as 0.5: 200 s, not 1 000 s, against 10 s. With 3.9 km flowing at 10 m/s:
        // T = 590 / 400 = 1.475, and 7 x 0.475 = 3.3. At its own speed the queue would make it T = 3.475, a 10.
        #expect(AreaTraffic.score([road(100, speed: 0.1, freeFlow: 10), road(3900, speed: 10, freeFlow: 10)]) == 3)
        #expect(AreaTraffic.score([road(4000, speed: 1, freeFlow: 20)]) == 10)
        #expect(AreaTraffic.score([road(4000, speed: 20, freeFlow: 20)]) == 0)
    }

    @Test func tooLittleMeasuredRoadHasNoScore() {
        #expect(AreaTraffic.score([road(2999, speed: 10, freeFlow: 20)]) == nil)
        #expect(AreaTraffic.score([road(3000, speed: 10, freeFlow: 20)]) == 7)
        #expect(AreaTraffic.score([]) == nil)
        // Without a length the stretch is measured along its points: 0.01° of longitude here, about 841 m.
        let stretch = segment([(40.9, 29.20), (40.9, 29.21)], jam: 0)
        #expect(abs(stretch.length - 841.4) < 0.1)
    }

    @Test func scoreLabelsAreYandexsOwnWords() {
        let labels: [String] = (0 ... 10).map { AreaTraffic.label(score: $0) }
        #expect(labels == [
            "Trafik açık", "Trafik açık", "Trafik akıcı", "Yer yer yoğun, akıcı", "Yoğun, yer yer akıcı", "Yoğun trafik",
            "Çok yoğun trafik", "Trafik durma noktasında", "Kilometrelerce yoğunluk", "Trafik kilitlendi", "Yürümek daha hızlı",
        ])
        #expect(AreaTraffic.label(score: 14) == "Yürümek daha hızlı")
        #expect(AreaTraffic.label(score: -1) == "Trafik açık")
    }

    @Test func mainRoadsAreMarkedForTheWiderLine() {
        let line = [(40.90, 29.20), (40.90, 29.21)].map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }
        let sections = AreaTraffic.sections([
            FlowSegment(points: line, jamFactor: 1, isClosed: false, roadClass: 1),
            FlowSegment(points: line, jamFactor: 1, isClosed: false, roadClass: 2),
            FlowSegment(points: line, jamFactor: 1, isClosed: false, roadClass: 3),
            FlowSegment(points: line, jamFactor: 1, isClosed: false),
        ])
        #expect(sections.map(\.isMajor) == [true, true, false, false])
    }

    @Test func requestIsABoxPostForEveryJamLevel() throws {
        let provider = HERETrafficProvider(apiKey: "k", session: .shared, budget: RequestBudget(defaults: UserDefaults(suiteName: "atlas.test.\(UUID())")!))
        // A 0.1° box: main roads and the next class down (HERETrafficProvider.areaFlowRequest).
        let request = try provider.areaFlowRequest(for: TrafficArea(west: 29.15, south: 40.86, east: 29.25, north: 40.93))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == "data.traffic.hereapi.com")
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let box = try #require(body["in"] as? [String: Any])
        #expect(box["type"] as? String == "bbox")
        #expect(box["west"] as? Double == 29.15)
        #expect(box["north"] as? Double == 40.93)
        #expect(body["minJamFactor"] as? Double == 0) // flowing roads too, drawn green
        #expect(body["maxJamFactor"] as? Double == 10) // without it HERE ignores the minimum
        #expect(body["functionalClasses"] as? [Int] == [1, 2, 3, 4])
        #expect(body["locationReferencing"] as? [String] == ["shape"])
        // Close in too: no local streets (class 5).
        let close = try provider.areaFlowRequest(for: TrafficArea(west: 29.18, south: 40.88, east: 29.22, north: 40.91))
        let closeData = try #require(close.httpBody)
        let closeBody = try #require(try JSONSerialization.jsonObject(with: closeData) as? [String: Any])
        #expect(closeBody["functionalClasses"] as? [Int] == [1, 2, 3, 4])
    }

    @Test func zoomedOutAsksForMainRoadsOnly() throws {
        let provider = HERETrafficProvider(apiKey: "k", session: .shared, budget: RequestBudget(defaults: UserDefaults(suiteName: "atlas.test.\(UUID())")!))
        let request = try provider.areaFlowRequest(for: TrafficArea(west: 29.0, south: 40.85, east: 29.3, north: 41.05))
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["functionalClasses"] as? [Int] == [1, 2, 3])
        // Above 0.3°, the district and the whole city: motorways and main arteries only.
        let city = try provider.areaFlowRequest(for: TrafficArea(west: 28.6, south: 40.8, east: 29.4, north: 41.3))
        let cityData = try #require(city.httpBody)
        let cityBody = try #require(try JSONSerialization.jsonObject(with: cityData) as? [String: Any])
        #expect(cityBody["functionalClasses"] as? [Int] == [1, 2])
    }

    @Test func aSpanOnALimitGetsTheSameClassesWhereverTheBoxIs() throws {
        let provider = HERETrafficProvider(apiKey: "k", session: .shared, budget: RequestBudget(defaults: UserDefaults(suiteName: "atlas.test.\(UUID())")!))
        // A view 0.14° tall, in the 0.01° steps the map reports, is 0.20° tall with the layer's margin: a hair
        // over at one latitude, a hair under at another.
        let areas = [4040, 4048].map { step in
            TrafficArea(west: 29.20, south: Double(step) * 0.01, east: 29.25, north: Double(step + 14) * 0.01).expanded(by: 0.2)
        }
        #expect(areas[0].span > 0.20)
        #expect(areas[1].span < 0.20)
        for area in areas {
            let data = try #require(try provider.areaFlowRequest(for: area).httpBody)
            let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["functionalClasses"] as? [Int] == [1, 2, 3, 4])
        }
    }

    @Test func fetchedAreaCoversSmallPansAndStaysUnderHERELimit() {
        let fetched = kartal.expanded(by: 0.5)
        #expect(fetched.contains(kartal))
        #expect(fetched.contains(TrafficArea(west: 29.15, south: 40.86, east: 29.35, north: 40.96)))
        #expect(abs((fetched.east - fetched.west) - 0.4) < 1e-9)
        #expect(TrafficArea(west: 28.5, south: 40.8, east: 29.4, north: 41.2).expanded(by: 0.5).fitsHERE)
        #expect(!TrafficArea(west: 28.0, south: 40.8, east: 29.2, north: 41.2).fitsHERE)
        // The widest view the layer loads, 0.8° (CityTraffic.refresh), with its margin of a fifth: the limit
        // trims the margin on the long side.
        let city = TrafficArea(west: 28.6, south: 40.8, east: 29.4, north: 41.3).expanded(by: 0.2)
        #expect(city.fitsHERE)
        #expect(abs((city.east - city.west) - 0.99) < 1e-9)
        #expect(abs((city.north - city.south) - 0.7) < 1e-9)
    }

    @Test func theMarginHasAFloorSoAMapFollowingTheCarReusesOneAnswer() {
        // Street zoom, a 0.02° x 0.01° box: a fifth of it is 0.004° and 0.002°, less than the 0.01° steps the
        // map reports its box in, so every step would leave the fetched area. The floor is 0.03° on every side.
        let street = TrafficArea(west: 29.20, south: 40.90, east: 29.22, north: 40.91)
        let fetched = street.expanded(by: 0.2)
        #expect(abs((street.west - fetched.west) - 0.03) < 1e-9)
        #expect(abs((fetched.east - street.east) - 0.03) < 1e-9)
        #expect(abs((street.south - fetched.south) - 0.03) < 1e-9)
        #expect(abs((fetched.north - street.north) - 0.03) < 1e-9)
        // Two steps on, north-east, the same answer still covers the screen.
        #expect(fetched.contains(TrafficArea(west: 29.22, south: 40.92, east: 29.24, north: 40.93)))
        // A box large enough keeps its share: a fifth of 0.2° is more than the floor.
        #expect(abs((kartal.west - kartal.expanded(by: 0.2).west) - 0.04) < 1e-9)
        // The floor yields to HERE's limit as the share does.
        #expect(TrafficArea(west: 28.5, south: 40.9, east: 29.48, north: 40.91).expanded(by: 0.2).fitsHERE)
    }

    @Test func layerHasItsOwnMonthlyCap() async {
        let budget = RequestBudget(defaults: UserDefaults(suiteName: "atlas.test.\(UUID())")!, limits: [.areaFlow: 0, .flow: 5])
        let provider = HERETrafficProvider(apiKey: "k", session: .shared, budget: budget)
        await #expect(throws: TrafficError.budgetExhausted) {
            _ = try await provider.flow(in: kartal)
        }
        #expect(budget.used(.flow) == 0)
    }
}

/// Road events on the city layer (HERE Traffic incidents).
struct IncidentsTests {
    @Test func closuresAccidentsAndRoadworksOnlyWithTheirStretch() throws {
        // The answer's shape, trimmed; congestion belongs to the flow layer and is left out.
        let json = """
        {"results":[
          {"location":{"shape":{"links":[{"points":[{"lat":40.84,"lng":29.30},{"lat":40.841,"lng":29.302}]}]}},
           "incidentDetails":{"type":"roadClosure","criticality":"critical","roadClosed":true,"description":{"value":"Kapalı","language":"tr"}}},
          {"location":{"shape":{"links":[{"points":[{"lat":40.90,"lng":29.19}]}]}},
           "incidentDetails":{"type":"accident","roadClosed":false,"description":{"value":"Kaza","language":"tr"}}},
          {"location":{"shape":{"links":[{"points":[{"lat":40.91,"lng":29.20}]}]}},
           "incidentDetails":{"type":"congestion","roadClosed":false}},
          {"location":{"shape":{"links":[{"points":[{"lat":40.92,"lng":29.21}]}]}},
           "incidentDetails":{"type":"construction","roadClosed":false}}
        ]}
        """
        let incidents = try HEREIncidentsResponse.incidents(from: Data(json.utf8))
        #expect(incidents.map(\.kind) == [.closure, .accident, .roadworks])
        #expect(incidents[0].points.count == 2)
        #expect(incidents[0].summary == "Kapalı")
        #expect(incidents[2].summary == "")
    }

    @Test func theRequestAsksForTheBoxWithShapes() throws {
        let provider = HERETrafficProvider(apiKey: "k", session: .shared, budget: RequestBudget(defaults: UserDefaults(suiteName: "atlas.test.\(UUID())")!))
        let url = try #require(provider.incidentsRequest(for: TrafficArea(west: 29.1, south: 40.8, east: 29.4, north: 40.95)).url)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(url.path == "/v7/incidents")
        #expect(items.first { $0.name == "in" }?.value == "bbox:29.1,40.8,29.4,40.95")
        #expect(items.first { $0.name == "locationReferencing" }?.value == "shape")
    }

    @Test func roadEventsHaveTheirOwnMonthlyCap() async {
        let budget = RequestBudget(defaults: UserDefaults(suiteName: "atlas.test.\(UUID())")!, limits: [.incidents: 0, .areaFlow: 5])
        let provider = HERETrafficProvider(apiKey: "k", session: .shared, budget: budget)
        await #expect(throws: TrafficError.budgetExhausted) {
            _ = try await provider.incidents(in: TrafficArea(west: 29.1, south: 40.8, east: 29.4, north: 40.95))
        }
        #expect(budget.used(.areaFlow) == 0)
    }
}
