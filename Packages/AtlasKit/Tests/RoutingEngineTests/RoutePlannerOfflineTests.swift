import CoreLocation
import Foundation
import SearchEngine
import Testing
@testable import RoutingEngine

/// Stands in for a phone with no connection.
private final class NoConnection: URLProtocol {
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

/// Stands in for Valhalla answering "no path" (HTTP 400).
private final class NoPath: URLProtocol {
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error_code":442,"error":"No path could be found for input"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
struct RoutePlannerOfflineTests {
    private let kartal = CLLocation(latitude: 40.8890, longitude: 29.1905)
    private let destination = GeoPoint(latitude: 40.9050, longitude: 29.2100)

    private func session(_ stub: URLProtocol.Type) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [stub]
        return URLSession(configuration: configuration)
    }

    /// A real FOSSGIS Valhalla answer (14.11.2026) to the request Ferrostar builds, as the device would give it.
    private func recordedAnswer() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "valhalla-osrm-kartal", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func withoutAConnectionTheDeviceAnswers() async throws {
        let answer = try recordedAnswer()
        let sent = SentBody()
        let planner = try RoutePlanner(session: session(NoConnection.self)) { body in
            await sent.store(body)
            return answer
        }
        let routes = try await planner.routes(from: kartal, to: destination)
        #expect(routes.count == 1)
        #expect(routes[0].isOffline)
        #expect(abs(routes[0].distance - 5163) < 1)
        // The device gets the same JSON body the server would have: OSRM format, Turkish, both points.
        let body = try #require(await sent.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["format"] as? String == "osrm")
        #expect((json["locations"] as? [Any])?.count == 2)
    }

    @Test func noPathIsNotRetriedOnTheDevice() async throws {
        let planner = try RoutePlanner(session: session(NoPath.self)) { _ in
            Issue.record("a 'no path' answer must not fall back to the device")
            return Data()
        }
        // The result is dropped inside: routes are main-actor values and may not leave as the closure's result.
        await #expect(throws: RoutePlanner.PlanningError.self) { _ = try await planner.routes(from: kartal, to: destination) }
    }

    @Test func deviceFailureSaysWhy() async throws {
        let planner = try RoutePlanner(session: session(NoConnection.self)) { _ in throw URLError(.cannotDecodeContentData) }
        do {
            _ = try await planner.routes(from: kartal, to: destination)
            Issue.record("expected an error")
        } catch let error as RoutePlanner.PlanningError {
            #expect(error.errorDescription?.contains("İstanbul") == true)
        }
    }

    @Test func whatCountsAsUnreachable() {
        #expect(RoutePlanner.worthTryingOffline(URLError(.notConnectedToInternet)))
        #expect(RoutePlanner.worthTryingOffline(URLError(.timedOut)))
        #expect(RoutePlanner.worthTryingOffline(RoutePlanner.PlanningError.service(status: 503)))
        #expect(RoutePlanner.worthTryingOffline(RoutePlanner.PlanningError.service(status: 429)))
        #expect(!RoutePlanner.worthTryingOffline(RoutePlanner.PlanningError.noRoute))
        #expect(!RoutePlanner.worthTryingOffline(RoutePlanner.PlanningError.service(status: 403)))
    }
}

private actor SentBody {
    var body: Data?
    func store(_ data: Data) { body = data }
}
