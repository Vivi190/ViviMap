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
        #expect(query.contains(URLQueryItem(name: "return", value: "summary,typicalDuration")))
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
