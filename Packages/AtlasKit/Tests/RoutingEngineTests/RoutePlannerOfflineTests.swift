import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
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

/// Stands in for the server answering with the recorded bridge route (11.2 km).
private final class ServerWithTheBridgeRoute: URLProtocol {
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let file = Bundle.module.url(forResource: "valhalla-osrm-bridge", withExtension: "json", subdirectory: "Fixtures"),
              let answer = try? Data(contentsOf: file)
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// Stands in for the server refusing the request.
private final class Forbidden: URLProtocol {
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }
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

    /// A real FOSSGIS Valhalla answer (2026-11-14) to the request Ferrostar builds, as the device would give it.
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

    /// Any server failure but "no path" is worth asking the device: it could answer a request the server refused.
    @Test func aRefusingServerFallsBackToTheDevice() async throws {
        let answer = try recordedAnswer()
        let planner = try RoutePlanner(session: session(Forbidden.self)) { _ in answer }
        let routes = try await planner.routes(from: kartal, to: destination)
        #expect(routes.first?.isOffline == true)
        #expect(abs((routes.first?.distance ?? 0) - 5163) < 1)
    }

    /// A reroute while driving: the device answers first (milliseconds, no connection needed); planning still
    /// asks the server first.
    @Test func reroutesAskTheDeviceBeforeTheServer() async throws {
        let answer = try recordedAnswer() // Kartal, 5.2 km; the server here would send the bridge route, 11.2 km
        let planner = try RoutePlanner(session: session(ServerWithTheBridgeRoute.self)) { _ in answer }
        let waypoint = RoutePlanner.waypoint(destination, areaSpan: nil)
        let rerouted = try await planner.getRoutes(userLocation: UserLocation(clLocation: kartal), waypoints: [waypoint])
        #expect(abs((rerouted.first?.distance ?? 0) - 5163) < 1)
        let planned = try await planner.routes(from: kartal, to: destination)
        #expect(planned.first?.isOffline == false)
        #expect(abs((planned.first?.distance ?? 0) - 11176) < 1)
    }

    @Test func aRerouteTheDeviceCannotAnswerGoesToTheServer() async throws {
        let planner = try RoutePlanner(session: session(ServerWithTheBridgeRoute.self)) { _ in throw URLError(.cannotDecodeContentData) }
        let waypoint = RoutePlanner.waypoint(destination, areaSpan: nil)
        let rerouted = try await planner.getRoutes(userLocation: UserLocation(clLocation: kartal), waypoints: [waypoint])
        #expect(abs((rerouted.first?.distance ?? 0) - 11176) < 1)
    }

    /// Builds without the tiles: a reroute is the server's, as before.
    @Test func withoutTilesARerouteIsTheServers() async throws {
        let planner = try RoutePlanner(session: session(ServerWithTheBridgeRoute.self), offline: nil)
        let waypoint = RoutePlanner.waypoint(destination, areaSpan: nil)
        let rerouted = try await planner.getRoutes(userLocation: UserLocation(clLocation: kartal), waypoints: [waypoint])
        #expect(abs((rerouted.first?.distance ?? 0) - 11176) < 1)
    }

    /// Altunizade → Ortaköy over the Bosphorus bridge, as FOSSGIS Valhalla answered on 2026-11-14.
    private func bridgeAnswer() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "valhalla-osrm-bridge", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func avoidingTollsAsksValhallaToExcludeThem() async throws {
        let answer = try recordedAnswer()
        let sent = SentBody()
        let planner = try RoutePlanner(session: session(NoConnection.self)) { body in
            await sent.store(body)
            return answer
        }
        planner.avoidsTolls = true
        _ = try await planner.routes(from: kartal, to: destination)
        let body = try #require(await sent.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let costing = try #require(json["costing_options"] as? [String: Any])
        let auto = try #require(costing["auto"] as? [String: Any])
        #expect(auto["exclude_tolls"] as? Bool == true)
        #expect(json["alternates"] as? Int == 2) // the other options stay
    }

    @Test func cardKnowsAboutTollsAndFerries() async throws {
        let bridge = try bridgeAnswer()
        let viaBridge = try RoutePlanner(session: session(NoConnection.self)) { _ in bridge }
        let tolled = try await viaBridge.routes(from: kartal, to: destination)
        #expect(tolled.first?.notes == RouteNotes(hasToll: true, hasFerry: false))

        let street = try recordedAnswer()
        let inKartal = try RoutePlanner(session: session(NoConnection.self)) { _ in street }
        let plain = try await inKartal.routes(from: kartal, to: destination)
        #expect(plain.first?.notes == RouteNotes())

        // Kadıköy → Beşiktaş with tolls excluded (2026-11-14): the Harem–Sirkeci car ferry, no toll.
        let url = try #require(Bundle.module.url(forResource: "valhalla-osrm-ferry", withExtension: "json", subdirectory: "Fixtures"))
        let ferryAnswer = try Data(contentsOf: url)
        let byFerry = try RoutePlanner(session: session(NoConnection.self)) { _ in ferryAnswer }
        let crossing = try await byFerry.routes(from: kartal, to: destination)
        #expect(crossing.first?.notes == RouteNotes(hasToll: false, hasFerry: true))
    }

    /// What the device (or server) is asked for the destination, by the size of the place.
    private func destinationSent(areaSpan: Double?) async throws -> [String: Any] {
        let answer = try recordedAnswer()
        let sent = SentBody()
        let planner = try RoutePlanner(session: session(NoConnection.self)) { body in
            await sent.store(body)
            return answer
        }
        _ = try await planner.routes(from: kartal, to: destination, areaSpan: areaSpan)
        let body = try #require(await sent.body)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let locations = try #require(json["locations"] as? [[String: Any]])
        return try #require(locations.last)
    }

    @Test func bigAreasEndOnAPublicRoad() async throws {
        let airport = try await destinationSent(areaSpan: 4_000)
        #expect((airport["search_filter"] as? [String: Any])?["min_road_class"] as? String == "tertiary")
        let hospital = try await destinationSent(areaSpan: 480)
        #expect((hospital["search_filter"] as? [String: Any])?["min_road_class"] as? String == "residential")
        let cafe = try await destinationSent(areaSpan: nil)
        #expect(cafe["search_filter"] == nil)
        #expect(cafe["type"] as? String == "break")
        let courthouse = try await destinationSent(areaSpan: 81) // small: the nearest road, as before
        #expect(courthouse["search_filter"] == nil)
    }

    @Test func whatCountsAsUnreachable() {
        #expect(RoutePlanner.worthTryingOffline(URLError(.notConnectedToInternet)))
        #expect(RoutePlanner.worthTryingOffline(URLError(.timedOut)))
        #expect(RoutePlanner.worthTryingOffline(RoutePlanner.PlanningError.service(status: 503)))
        #expect(RoutePlanner.worthTryingOffline(RoutePlanner.PlanningError.service(status: 429)))
        // A server that refuses, or whose answer cannot be read, is no reason to leave the driver without a route.
        #expect(RoutePlanner.worthTryingOffline(RoutePlanner.PlanningError.service(status: 403)))
        #expect(RoutePlanner.worthTryingOffline(RoutePlanner.PlanningError.service(status: 404)))
        #expect(RoutePlanner.worthTryingOffline(URLError(.cannotParseResponse)))
        // "No path" (HTTP 400): the same tiles would say the same.
        #expect(!RoutePlanner.worthTryingOffline(RoutePlanner.PlanningError.noRoute))
        // A prefetch dropped for another place: no device answer either.
        #expect(!RoutePlanner.worthTryingOffline(URLError(.cancelled)))
        #expect(!RoutePlanner.worthTryingOffline(CancellationError()))
    }
}

private actor SentBody {
    var body: Data?
    func store(_ data: Data) { body = data }
}
