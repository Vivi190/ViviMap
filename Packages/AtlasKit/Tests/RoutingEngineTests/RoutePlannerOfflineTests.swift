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

/// What a plan asks the router for beyond its first request: a route by local streets, and ways round roads
/// found closed. The "device" here answers every request and keeps what it was sent.
@MainActor
struct RoutePlannerCandidatesTests {
    private let kartal = CLLocation(latitude: 40.8890, longitude: 29.1905)
    private let destination = GeoPoint(latitude: 40.9050, longitude: 29.2100)

    private func session(_ stub: URLProtocol.Type) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [stub]
        return URLSession(configuration: configuration)
    }

    private func answer(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func json(_ body: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    /// Every request sent so far, as JSON.
    private func requests(_ sent: SentBodies) async throws -> [[String: Any]] {
        let bodies = await sent.bodies
        return try bodies.map { try json($0) }
    }

    /// The `costing_options.auto` of a request, nil when it has none.
    private func auto(_ request: [String: Any]) -> [String: Any]? {
        (request["costing_options"] as? [String: Any])?["auto"] as? [String: Any]
    }

    /// A planner without a connection whose device answers with the Kartal route (5.2 km), and with the bridge
    /// route (11.2 km) when asked for local streets.
    private func makePlanner(keeping sent: SentBodies) throws -> RoutePlanner {
        let street = try answer("valhalla-osrm-kartal")
        let other = try answer("valhalla-osrm-bridge")
        return try RoutePlanner(session: session(NoConnection.self)) { body in
            await sent.store(body)
            return String(decoding: body, as: UTF8.self).contains("use_highways") ? other : street
        }
    }

    @Test func aPlanAlsoAsksForARouteByLocalStreets() async throws {
        let sent = SentBodies()
        let planner = try makePlanner(keeping: sent)
        // The chooser is given the router's own route first, then the extra one, and keeps both.
        let routes = try await planner.routes(from: kartal, to: destination, choosing: { shapes, own in
            shapes.count == 2 && own == 1 && shapes[0].count > 1 ? [0, 1] : []
        })
        try #require(routes.count == 2)
        #expect(routes.map(\.index) == [0, 1])
        #expect(abs(routes[0].distance - 5163) < 1)
        #expect(abs(routes[1].distance - 11176) < 1)
        let sentRequests = try await requests(sent)
        try #require(sentRequests.count == 2)
        let local = try #require(sentRequests.first(where: { auto($0) != nil }))
        let main = try #require(sentRequests.first(where: { auto($0) == nil }))
        // One route that keeps off the main roads where it can; the rest of the request is the same.
        // Through two JSON writers on its way here: equal to within a rounding step.
        #expect(abs((auto(local)?["use_highways"] as? Double ?? -1) - 0.1) < 1e-9)
        #expect(local["alternates"] as? Int == 0)
        #expect((local["locations"] as? [Any])?.count == 2)
        #expect(local["format"] as? String == "osrm")
        #expect(main["alternates"] as? Int == 2)
        #expect(main["exclude_locations"] == nil)
    }

    @Test func whatIsOfferedIsTheChoosersAndNeverMoreThanThree() async throws {
        let planner = try makePlanner(keeping: SentBodies())
        // Only the extra route kept: it takes the first place.
        let one = try await planner.routes(from: kartal, to: destination, choosing: { _, _ in [1] })
        #expect(one.map(\.index) == [0])
        #expect(abs((one.first?.distance ?? 0) - 11176) < 1)
        // More places than the card has tiles, and one that does not exist.
        let many = try await planner.routes(from: kartal, to: destination, choosing: { _, _ in [0, 1, 7, 0, 1] })
        #expect(many.map(\.index) == [0, 1, 2])
        // A choice of none still leaves the router's own route.
        let none = try await planner.routes(from: kartal, to: destination, choosing: { _, _ in [] })
        #expect(none.count == 1)
        #expect(abs((none.first?.distance ?? 0) - 5163) < 1)
        // A route can be put in another place of the list: tiles and map labels go by its index.
        let moved = try #require(one.first).placed(at: 2)
        #expect(moved.index == 2)
        #expect(abs(moved.distance - 11176) < 1)
    }

    @Test func withoutAChooserThereIsOneRequestAsBefore() async throws {
        let sent = SentBodies()
        let planner = try makePlanner(keeping: sent)
        let routes = try await planner.routes(from: kartal, to: destination)
        #expect(routes.count == 1)
        let sentRequests = try await requests(sent)
        #expect(sentRequests.count == 1)
    }

    @Test func tollsStayExcludedOnTheLocalStreetsRoute() async throws {
        let sent = SentBodies()
        let planner = try makePlanner(keeping: sent)
        planner.avoidsTolls = true
        _ = try await planner.routes(from: kartal, to: destination, choosing: { _, _ in [0] })
        let sentRequests = try await requests(sent)
        try #require(sentRequests.count == 2)
        // Both requests exclude tolls; one of them also prefers local streets.
        #expect(sentRequests.allSatisfy { auto($0)?["exclude_tolls"] as? Bool == true })
        #expect(sentRequests.filter { auto($0)?["use_highways"] != nil }.count == 1)
    }

    @Test func roadsFoundClosedAreKeptOffInEveryRequest() async throws {
        let sent = SentBodies()
        let planner = try makePlanner(keeping: sent)
        let here = CLLocationCoordinate2D(latitude: 40.8951, longitude: 29.1962)
        let there = CLLocationCoordinate2D(latitude: 40.8963, longitude: 29.1978)
        #expect(planner.markClosed([here, there]))
        // Known already: the same points, and one 10 m from the first.
        #expect(!planner.markClosed([here, CLLocationCoordinate2D(latitude: 40.89519, longitude: 29.1962)]))
        #expect(planner.closedRoads.count == 2)
        planner.avoidsTolls = true
        _ = try await planner.routes(from: kartal, to: destination)
        let planned = try #require(try await requests(sent).last)
        let excluded = try #require(planned["exclude_locations"] as? [[String: Any]])
        try #require(excluded.count == 2)
        #expect(abs((excluded[0]["lat"] as? Double ?? 0) - 40.8951) < 1e-9)
        #expect(abs((excluded[0]["lon"] as? Double ?? 0) - 29.1962) < 1e-9)
        #expect(abs((excluded[1]["lat"] as? Double ?? 0) - 40.8963) < 1e-9)
        // Not snapped to a junction, which would take the cross street with it.
        #expect(excluded[0]["node_snap_tolerance"] as? Double == 0)
        // The other options stay.
        #expect(auto(planned)?["exclude_tolls"] as? Bool == true)
        #expect(planned["alternates"] as? Int == 2)
        // A reroute while driving keeps off them too.
        let waypoint = RoutePlanner.waypoint(destination, areaSpan: nil)
        _ = try await planner.getRoutes(userLocation: UserLocation(clLocation: kartal), waypoints: [waypoint])
        let rerouted = try #require(try await requests(sent).last)
        #expect((rerouted["exclude_locations"] as? [[String: Any]])?.count == 2)
        // A new destination starts without them.
        planner.closedRoads = []
        _ = try await planner.routes(from: kartal, to: destination)
        let later = try #require(try await requests(sent).last)
        #expect(later["exclude_locations"] == nil)
    }

    @Test func noMoreClosedPointsAreSentThanTheRouterTakes() async throws {
        let sent = SentBodies()
        let planner = try makePlanner(keeping: sent)
        // 45 points about 110 m apart; Valhalla refuses a request with more than 50.
        let points = (0 ..< 45).map { CLLocationCoordinate2D(latitude: 40.89 + Double($0) * 0.001, longitude: 29.2) }
        #expect(planner.markClosed(points))
        #expect(planner.closedRoads.count == 40)
        _ = try await planner.routes(from: kartal, to: destination)
        let planned = try #require(try await requests(sent).last)
        let excluded = try #require(planned["exclude_locations"] as? [[String: Any]])
        #expect(excluded.count == 40)
        // The latest ones.
        #expect(abs((excluded.last?["lat"] as? Double ?? 0) - points[44].latitude) < 1e-9)
    }

    /// The destination may lie on a closed road, or the car stand on one: a closure must not cost the route.
    @Test func whenNoRouteKeepsOffTheClosedRoadsTheyAreLetGo() async throws {
        let street = try answer("valhalla-osrm-kartal")
        let sent = SentBodies()
        // A router that finds no way while anything is excluded.
        let planner = try RoutePlanner(session: session(NoConnection.self)) { body in
            await sent.store(body)
            if String(decoding: body, as: UTF8.self).contains("exclude_locations") { throw URLError(.cannotDecodeContentData) }
            return street
        }
        #expect(planner.markClosed([CLLocationCoordinate2D(latitude: 40.8951, longitude: 29.1962)]))
        let routes = try await planner.routes(from: kartal, to: destination)
        #expect(abs((routes.first?.distance ?? 0) - 5163) < 1)
        #expect(planner.closedRoads.isEmpty)
        // Asked with them first, then without.
        let sentRequests = try await requests(sent)
        #expect(sentRequests.count == 2)
        #expect(sentRequests.first?["exclude_locations"] != nil)
        #expect(sentRequests.last?["exclude_locations"] == nil)
    }
}

private actor SentBodies {
    var bodies: [Data] = []
    func store(_ data: Data) { bodies.append(data) }
}
