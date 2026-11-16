import CoreLocation
import Foundation
import Testing
@testable import TrafficEngine

// The inline shapes follow HERE's documented Route Import examples (docs.here.com, routing-v8-route-import).
// here-import-sample.json has the full answer shape with made-up values: HERE's own data is not kept in this
// (public) repository.
struct HEREImportResponseTests {
    @Test func parsesARouteImportAnswer() throws {
        let url = try #require(Bundle.module.url(forResource: "here-import-sample", withExtension: "json", subdirectory: "Fixtures"))
        let estimate = try HEREImportResponse.estimate(from: Data(contentsOf: url))
        #expect(estimate.duration == 500)
        #expect(estimate.baseDuration == 470)
        #expect(estimate.typicalDuration == 485)
    }

    @Test func sumsSectionsWithTraffic() throws {
        let json = """
        {"routes":[{"id":"r","sections":[
          {"summary":{"duration":363,"length":1303,"baseDuration":300,"typicalDuration":330}},
          {"summary":{"duration":637,"length":4100,"baseDuration":500,"typicalDuration":560}}
        ]}]}
        """
        let estimate = try HEREImportResponse.estimate(from: Data(json.utf8))
        #expect(estimate.duration == 1000)
        #expect(estimate.baseDuration == 800)
        #expect(estimate.typicalDuration == 890)
        #expect(estimate.delay == 200)
    }

    @Test func typicalOnlyWhenEverySectionHasIt() throws {
        let json = """
        {"routes":[{"sections":[
          {"summary":{"duration":100,"baseDuration":90,"typicalDuration":95}},
          {"summary":{"duration":50,"baseDuration":50}}
        ]}]}
        """
        #expect(try HEREImportResponse.estimate(from: Data(json.utf8)).typicalDuration == nil)
    }

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// here-import-spans.json: the shape of an answer with spans, with made-up values. Two sections, as HERE
    /// returns a trace it could not match in one piece (notice `importSplitRoute`).
    @Test func theSpansOfEverySectionGiveTheSpeedLimits() throws {
        let estimate = try HEREImportResponse.estimate(from: fixture("here-import-spans"))
        // The times still add up over the sections.
        #expect(estimate.duration == 100)
        #expect(estimate.baseDuration == 85)
        #expect(estimate.typicalDuration == 93)
        // 13.8888893, 8.333334 and 19.4444447 m/s are 50, 30 and 70 km/h; the "unlimited" span is no limit.
        #expect(estimate.limits.map(\.kmh) == [50, 30, 70, 50])
        #expect(estimate.limits.map(\.length) == [168, 168, 221, 84])
        // Each starts at the point of its own section's line that its offset names.
        let starts: [(Double, Double)] = [(40.9, 29.2), (40.9, 29.202), (40.903, 29.204), (40.905, 29.204)]
        for (stretch, start) in zip(estimate.limits, starts) {
            #expect(abs(stretch.latitude - start.0) < 1e-9 && abs(stretch.longitude - start.1) < 1e-9)
        }
    }

    @Test func anAnswerWithoutSpansOrLineStillGivesTheTimes() throws {
        // As before the spans were asked for: the sample answer has neither.
        let plain = try HEREImportResponse.estimate(from: fixture("here-import-sample"))
        #expect(plain.duration == 500)
        #expect(plain.limits.isEmpty)
        // Spans without the line they point into, a line that is no polyline, spans that are no list, and in
        // the last section spans pointing past the line (it has two points), with a text for an offset, without
        // a length and without a limit: the times stand, and the one span that has everything counts.
        let json = """
        {"routes":[{"sections":[
          {"summary":{"duration":10,"baseDuration":9},"spans":[{"offset":0,"length":100,"maxSpeed":13.8888893}]},
          {"summary":{"duration":20,"baseDuration":18},"polyline":"not a polyline","spans":[{"offset":0,"length":100,"maxSpeed":13.8888893}]},
          {"summary":{"duration":30,"baseDuration":27},"polyline":"BGg6qguCgon23BAw-B","spans":"none"},
          {"summary":{"duration":40,"baseDuration":36},"polyline":"BGg6qguCgon23BAw-B","spans":[
            {"offset":2,"length":100,"maxSpeed":13.8888893},{"offset":"0","length":100,"maxSpeed":13.8888893},
            {"offset":0,"maxSpeed":13.8888893},{"offset":0,"length":100},{"offset":1,"length":84,"maxSpeed":8.333334}]}
        ]}]}
        """
        let estimate = try HEREImportResponse.estimate(from: Data(json.utf8))
        #expect(estimate.duration == 100)
        #expect(estimate.baseDuration == 90)
        #expect(estimate.limits.map(\.kmh) == [30])
        #expect(abs((estimate.limits.first?.longitude ?? 0) - 29.201) < 1e-9)
    }

    /// The same fixture: its road events, each on the stretch of its own section's line that the spans naming
    /// it cover.
    @Test func theEventsOfEverySectionComeWithTheirStretch() throws {
        let events = try HEREImportResponse.estimate(from: fixture("here-import-spans")).events
        // Road works on the second span of the first section, a closure on the last span of the second; the
        // congestion reported there belongs to the flow colours.
        #expect(events.map(\.kind) == [.roadworks, .closure])
        #expect(events.map(\.points.count) == [3, 2])
        #expect(abs((events.first?.points.first?.longitude ?? 0) - 29.202) < 1e-9)
        #expect(abs((events.first?.points.last?.longitude ?? 0) - 29.204) < 1e-9)
        #expect(abs((events.last?.points.first?.latitude ?? 0) - 40.905) < 1e-9)
        #expect(events.map(\.summary) == ["Örnek Cadde üzerinde yol çalışması", "Örnek Sokak kapalı"])
        // An answer without events has none.
        #expect(try HEREImportResponse.estimate(from: fixture("here-import-sample")).events.isEmpty)
    }

    @Test func eventsAreKnownByKindAndPlacedByTheSpansThatNameThem() throws {
        // Five points east along a street, four spans. An accident that closes the road is a closure
        // (`critical`), on the two spans that name it; road works that block the junction at the end of a span
        // lie at that junction; an accident no span names has no place. Left out as well: a place in the list
        // that does not exist (7), weather, a second report of the same id in the next section, and events that
        // are no list.
        let line = "BGg6qguCgon23BAw-BAw-BAw-BAw-B"
        let json = """
        {"routes":[{"sections":[
          {"summary":{"duration":10,"baseDuration":9},"polyline":"\(line)",
           "spans":[{"offset":0,"length":84,"incidents":[0,7]},{"offset":1,"length":84,"incidents":[0,2],"intersectionIncidents":[1]},
                    {"offset":2,"length":84,"incidents":[4]},{"offset":3,"length":84}],
           "incidents":[{"type":"accident","criticality":"critical","id":"a"},{"type":"construction","id":"b"},
                        {"type":"weather","id":"c"},{"type":"accident","id":"d"},{"type":"accident","criticality":"minor"}]},
          {"summary":{"duration":10,"baseDuration":9},"polyline":"\(line)",
           "spans":[{"offset":0,"length":336,"incidents":[0]}],
           "incidents":[{"type":"construction","id":"b"}]},
          {"summary":{"duration":10,"baseDuration":9},"polyline":"\(line)","spans":[{"offset":0,"length":336,"incidents":[0]}],"incidents":"none"}
        ]}]}
        """
        let estimate = try HEREImportResponse.estimate(from: Data(json.utf8))
        #expect(estimate.duration == 30)
        #expect(estimate.events.map(\.kind) == [.closure, .roadworks, .accident])
        #expect(estimate.events.map(\.points.count) == [3, 1, 2])
        try #require(estimate.events.count == 3)
        #expect(abs(estimate.events[0].points[0].longitude - 29.2) < 1e-9)
        #expect(abs(estimate.events[1].points[0].longitude - 29.202) < 1e-9)
        #expect(abs(estimate.events[2].points[1].longitude - 29.203) < 1e-9)
        #expect(estimate.events[0].summary == "")
    }

    @Test func limitsAreReadAsTheSignShowsThem() {
        // HERE's single-precision metres per second for 30, 50, 70, 82 and 120 km/h.
        #expect(HEREImportResponse.kmh(8.333334) == 30)
        #expect(HEREImportResponse.kmh(13.8888893) == 50)
        #expect(HEREImportResponse.kmh(13.89) == 50)
        #expect(HEREImportResponse.kmh(19.4444447) == 70)
        #expect(HEREImportResponse.kmh(22.7777786) == 82)
        #expect(HEREImportResponse.kmh(33.3333321) == 120)
        // No number, none above zero, or one no sign carries: no limit.
        #expect(HEREImportResponse.kmh(nil) == nil)
        #expect(HEREImportResponse.kmh(0) == nil)
        #expect(HEREImportResponse.kmh(-13.9) == nil)
        #expect(HEREImportResponse.kmh(Double.infinity) == nil)
        #expect(HEREImportResponse.kmh(1e300) == nil)
    }

    @Test func unmatchedTraceIsAnError() {
        let json = """
        {"notices":[{"title":"Route handle decoding failed","code":"violatedTransportModeInRouteHandleDecoding","severity":"critical"}],"routes":[]}
        """
        #expect(throws: TrafficError.notMatched) { try HEREImportResponse.estimate(from: Data(json.utf8)) }
    }

    @Test func trafficNeverMakesNegativeDelay() {
        #expect(TrafficEstimate(duration: 280, baseDuration: 300, typicalDuration: nil).delay == 0)
    }
}

struct HERERequestTests {
    @Test func traceKeepsEndsAndRespectsTheLimit() {
        let route = (0 ..< 2500).map { CLLocationCoordinate2D(latitude: 40.9 + Double($0) * 1e-5, longitude: 29.2) }
        let points = HERETrace.points(route, limit: 1000)
        #expect(points.count == 1000)
        #expect(points.first == HERETrace.Point(lat: route[0].latitude, lng: 29.2))
        #expect(points.last == HERETrace.Point(lat: route[2499].latitude, lng: 29.2))
        #expect(HERETrace.points(Array(route.prefix(10))).count == 10)
    }

    @Test func importRequestShape() throws {
        let provider = HERETrafficProvider(apiKey: "test-key", session: .shared, budget: RequestBudget(defaults: UserDefaults(suiteName: "atlas.test.\(UUID())")!))
        let route = [CLLocationCoordinate2D(latitude: 40.889, longitude: 29.1905), CLLocationCoordinate2D(latitude: 40.905, longitude: 29.21)]
        let request = try provider.request(for: route)
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(request.httpMethod == "POST")
        #expect(request.url?.host == "router.hereapi.com")
        #expect(query.contains(URLQueryItem(name: "transportMode", value: "car")))
        // The line, its spans and the road events in the same answer as the times: the speed limits and the
        // events on the route cost no request of their own.
        #expect(query.contains(URLQueryItem(name: "return", value: "polyline,summary,typicalDuration,incidents")))
        #expect(query.contains(URLQueryItem(name: "spans", value: "maxSpeed,length,incidents")))
        let body = try #require(request.httpBody)
        let trace = try #require((try JSONSerialization.jsonObject(with: body) as? [String: Any])?["trace"] as? [[String: Double]])
        #expect(trace.count == 2)
        #expect(trace[0]["lat"] == 40.889 && trace[0]["lng"] == 29.1905)
    }

    @Test func keyMustBeAnExpandedNonEmptyValue() {
        #expect(HEREKey.normalized(nil) == nil)
        #expect(HEREKey.normalized("  ") == nil)
        #expect(HEREKey.normalized("$(HERE_API_KEY)") == nil)
        #expect(HEREKey.normalized(" abc123 ") == "abc123")
    }
}

struct RequestBudgetTests {
    private func budget(limit: Int, at date: @escaping @Sendable () -> Date) -> RequestBudget {
        RequestBudget(defaults: UserDefaults(suiteName: "atlas.test.\(UUID())")!, limits: [.routeImport: limit], now: date)
    }

    @Test func stopsAtTheMonthlyCap() {
        let budget = budget(limit: 2) { Date(timeIntervalSince1970: 1_794_000_000) }
        #expect(budget.spend(.routeImport))
        #expect(budget.spend(.routeImport))
        #expect(!budget.spend(.routeImport))
        #expect(budget.used(.routeImport) == 2)
        #expect(!budget.spend(.flow)) // no cap configured means no spending
    }

    @Test func startsOverEachMonth() {
        let clock = Clock()
        let budget = budget(limit: 1) { clock.date }
        #expect(budget.spend(.routeImport))
        #expect(!budget.spend(.routeImport))
        clock.date = clock.date.addingTimeInterval(32 * 86_400)
        #expect(budget.spend(.routeImport))
    }

    @Test func monthKeyIsUTC() {
        // 2026-11-30 23:30 UTC is already December in Istanbul; the counter follows UTC.
        let date = Date(timeIntervalSince1970: 1_796_081_400)
        #expect(RequestBudget.key(.routeImport, date) == "atlas.here.routeImport.2026-11")
    }
}

private final class Clock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_794_000_000)
}
