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
