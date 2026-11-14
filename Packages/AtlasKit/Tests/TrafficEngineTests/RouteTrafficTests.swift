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
    @Test func joinsLinksOfARealCorridorResponse() throws {
        // First three results of a live corridor query along a Kartal route (14.11.2026, 01:30 Istanbul).
        let url = try #require(Bundle.module.url(forResource: "here-flow-kartal", withExtension: "json", subdirectory: "Fixtures"))
        let segments = try HEREFlowResponse.segments(from: Data(contentsOf: url))
        #expect(segments.map(\.points.count) == [8, 12, 29])
        #expect(segments[0].jamFactor == 0.6)
        #expect(segments.allSatisfy { !$0.isClosed })
        #expect(segments[0].points.first?.latitude == 40.90602)
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
            segment([(40.9, 29.201), (40.9, 29.203)], jam: 5), // along, same direction, slow
            segment([(40.9, 29.204), (40.9, 29.206)], jam: 2), // along but flowing: not coloured
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
        #expect(RouteTraffic.level(segment([(0, 0), (0, 1)], jam: 3.9)) == nil)
        #expect(RouteTraffic.level(segment([(0, 0), (0, 1)], jam: 4)) == .slow)
        #expect(RouteTraffic.level(segment([(0, 0), (0, 1)], jam: 8)) == .heavy)
        #expect(RouteTraffic.level(segment([(0, 0), (0, 1)], jam: 2, closed: true)) == .stopped)
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
        #expect(area["radius"] as? Int == 20)
        #expect((area["corridor"] as? String)?.hasPrefix("BF") == true)
        #expect(body["locationReferencing"] as? [String] == ["shape"])
    }
}

struct AreaTrafficTests {
    private let kartal = TrafficArea(west: 29.1, south: 40.85, east: 29.3, north: 40.95)

    private func segment(_ points: [(Double, Double)], jam: Double, closed: Bool = false) -> FlowSegment {
        FlowSegment(points: points.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }, jamFactor: jam, isClosed: closed)
    }

    @Test func drawsOnlySlowAndWorse() {
        let sections = AreaTraffic.sections([
            segment([(40.90, 29.20), (40.90, 29.21)], jam: 2),
            segment([(40.91, 29.20), (40.91, 29.21)], jam: 6),
            segment([(40.92, 29.20), (40.92, 29.21)], jam: 1, closed: true),
            segment([(40.93, 29.20)], jam: 9), // a single point draws nothing
        ])
        #expect(sections.map(\.level) == [.slow, .stopped])
    }

    @Test func eachDirectionMovesToItsRightSide() {
        let east = AreaTraffic.offsetRight([(40.9, 29.20), (40.9, 29.21)].map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }, metres: 4)
        let north = AreaTraffic.offsetRight([(40.90, 29.2), (40.91, 29.2)].map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }, metres: 4)
        // Eastbound keeps to the south side, northbound to the east side, 4 m out.
        #expect(abs((40.9 - east[0].latitude) * 110_540 - 4) < 0.01)
        #expect(east[1].longitude == 29.21)
        #expect(abs((north[1].longitude - 29.2) * 111_320 * cos(40.91 * .pi / 180) - 4) < 0.01)
        #expect(north[0].latitude == 40.90)
    }

    @Test func requestIsABoxPostForSlowRoadsOnly() throws {
        let provider = HERETrafficProvider(apiKey: "k", session: .shared, budget: RequestBudget(defaults: UserDefaults(suiteName: "atlas.test.\(UUID())")!))
        // The box measured on 14.11.2026 (HERETrafficProvider.flow(in:)): close enough for every road class.
        let request = try provider.areaFlowRequest(for: TrafficArea(west: 29.15, south: 40.86, east: 29.25, north: 40.93))
        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == "data.traffic.hereapi.com")
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let box = try #require(body["in"] as? [String: Any])
        #expect(box["type"] as? String == "bbox")
        #expect(box["west"] as? Double == 29.15)
        #expect(box["north"] as? Double == 40.93)
        #expect(body["minJamFactor"] as? Double == 4)
        #expect(body["maxJamFactor"] as? Double == 10) // without it HERE ignores the minimum
        #expect(body["functionalClasses"] == nil) // close in: every road
        #expect(body["locationReferencing"] as? [String] == ["shape"])
    }

    @Test func zoomedOutAsksForMainRoadsOnly() throws {
        let provider = HERETrafficProvider(apiKey: "k", session: .shared, budget: RequestBudget(defaults: UserDefaults(suiteName: "atlas.test.\(UUID())")!))
        let request = try provider.areaFlowRequest(for: TrafficArea(west: 29.0, south: 40.85, east: 29.3, north: 41.05))
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["functionalClasses"] as? [Int] == [1, 2, 3])
    }

    @Test func fetchedAreaCoversSmallPansAndStaysUnderHERELimit() {
        let fetched = kartal.expanded(by: 0.5)
        #expect(fetched.contains(kartal))
        #expect(fetched.contains(TrafficArea(west: 29.15, south: 40.86, east: 29.35, north: 40.96)))
        #expect(abs((fetched.east - fetched.west) - 0.4) < 1e-9)
        #expect(TrafficArea(west: 28.5, south: 40.8, east: 29.4, north: 41.2).expanded(by: 0.5).fitsHERE)
        #expect(!TrafficArea(west: 28.0, south: 40.8, east: 29.2, north: 41.2).fitsHERE)
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
