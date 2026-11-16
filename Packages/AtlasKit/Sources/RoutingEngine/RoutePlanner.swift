import CoreLocation
@preconcurrency import FerrostarCore
// The UniFFI types (Route, RouteAdapter, WellKnownRouteProvider …) live here; FerrostarCore does not re-export them.
@preconcurrency import FerrostarCoreFFI
import Foundation
import SearchEngine

/// Plans car routes with Valhalla through Ferrostar's adapter (request building + OSRM-format parsing).
///
/// The adapter calls are synchronous and stay on the main actor; only the HTTP request (Sendable values)
/// leaves it, which keeps the pre-concurrency Ferrostar types out of Swift 6 isolation crossings.
@MainActor
public final class RoutePlanner {
    public enum PlanningError: LocalizedError {
        case noRoute
        case service(status: Int)
        /// The server failed or could not be reached, and the tiles on the device could not route it either
        /// (e.g. outside Istanbul).
        case offlineUnavailable

        public var errorDescription: String? {
            switch self {
            case .noRoute: "Bu hedefe rota bulunamadı. Hedef kapalı bir alanda olabilir."
            // The status code is for the log, not for the driver.
            case .service: "Rota servisi yanıt vermedi. Biraz sonra yeniden deneyin."
            // Not "İnternet yok": the device is also asked when the server answers with an error.
            case .offlineUnavailable: "Rota servisi yanıt vermedi; cihazdaki İstanbul verisiyle de rota bulunamadı. Hedef İstanbul dışında olabilir."
            }
        }
    }

    // FOSSGIS public Valhalla: fair use (1 request/s) for personal development; a self-hosted instance
    // replaces it later (docs/architecture.md, ADR-4).
    static let endpoint = "https://valhalla1.openstreetmap.de/route"

    let provider: WellKnownRouteProvider
    private let adapter: RouteAdapter
    private let tollFreeAdapter: RouteAdapter
    private let session: URLSession
    /// Answers the same request on the device (bundled Istanbul tiles); nil in builds without them.
    private let offline: (@Sendable (Data) async throws -> Data)?

    public init(
        session: URLSession = .shared,
        offline: (@Sendable (Data) async throws -> Data)? = OfflineRouter.bundledRoute
    ) throws {
        provider = try Self.valhallaProvider()
        adapter = try RouteAdapter.fromWellKnownRouteProvider(wellKnownRouteProvider: provider)
        tollFreeAdapter = try RouteAdapter.fromWellKnownRouteProvider(wellKnownRouteProvider: Self.valhallaProvider(avoidingTolls: true))
        self.session = session
        self.offline = offline
    }

    /// Whether this build can route without a connection.
    public var canRouteOffline: Bool { offline != nil }

    /// Set from the "Ücretli yollardan kaçın" setting before planning; reroutes during guidance keep it.
    public var avoidsTolls = false

    /// Points on roads that live traffic reports as closed (`markClosed`). Every request keeps off the road
    /// nearest each of them, the reroutes during guidance too: a route once led round a closed stretch does
    /// not go back through it when the driver leaves the route. Emptied for a new destination; emptied by the
    /// planner itself when a request cannot be answered with them (`fetch`).
    public var closedRoads: [CLLocationCoordinate2D] = []

    /// Adds points on roads found closed (the middle of each closed edge of a route). False when every one of
    /// them was known already, within 25 m: there is nothing new to ask the router for.
    @discardableResult
    public func markClosed(_ points: [CLLocationCoordinate2D]) -> Bool {
        let fresh = points.filter { point in
            !closedRoads.contains { known in
                CLLocation(latitude: known.latitude, longitude: known.longitude)
                    .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude)) < 25
            }
        }
        // The latest: the router takes no more (`excludedLimit`).
        closedRoads = Array((closedRoads + fresh).suffix(Self.excludedLimit))
        return !fresh.isEmpty
    }

    /// `use_highways` of the extra candidate. Measured on FOSSGIS, 2026-11-16, Pendik → Kadıköy: at 0.1 (and
    /// at 0) a route sharing 35 % of its points with the default one; at 0.25 still 89 % the same.
    static let localStreetsUseHighways = 0.1

    /// Valhalla refuses a request with more than 50 excluded locations (its default `max_exclude_locations`,
    /// on FOSSGIS and in the tiles' engine on the device): HTTP 400 at 60 on 2026-11-16, fine at 45.
    static let excludedLimit = 40

    /// Shared with the navigation session so reroutes use the same engine and options.
    /// - Parameters:
    ///   - localStreets: one route that keeps off motorways and trunk roads where it can, as a candidate for
    ///     when the main roads are jammed.
    ///   - closed: points on roads to keep off (`exclude_locations`: Valhalla takes the road nearest each).
    public static func valhallaProvider(
        avoidingTolls: Bool = false, localStreets: Bool = false, closed: [CLLocationCoordinate2D] = []
    ) throws -> WellKnownRouteProvider {
        var options: [String: Any] = [
            "directions_options": ["language": "tr-TR", "units": "kilometers"],
            "alternates": localStreets ? 0 : 2,
        ]
        var auto: [String: Any] = [:]
        // exclude_tolls, not use_tolls: 0, which still took the Bosphorus bridge (FOSSGIS, 2026-11-14);
        // excluded, Kadıköy → Beşiktaş goes by the Harem–Sirkeci car ferry.
        if avoidingTolls { auto["exclude_tolls"] = true }
        if localStreets { auto["use_highways"] = localStreetsUseHighways }
        if !auto.isEmpty { options["costing_options"] = ["auto": auto] }
        if !closed.isEmpty {
            // Not snapped to a junction: a point within Valhalla's 5 m of one would take every road that
            // meets there, the cross street included.
            let excluded: [[String: Double]] = closed.suffix(excludedLimit).map {
                ["lat": $0.latitude, "lon": $0.longitude, "node_snap_tolerance": 0]
            }
            options["exclude_locations"] = excluded
        }
        return try WellKnownRouteProvider.valhalla(endpointUrl: endpoint, profile: "auto", optionsJson: nil)
            .withJsonOptions(options: options)
    }

    /// The most routes offered at once: the route card has three tiles.
    static let offered = 3

    /// - Parameters:
    ///   - areaSpan: size of the destination when it is an area (Place.areaSpan); see `waypoint`.
    ///   - deviceFirst: for a new route while driving; see `fetch`.
    ///   - choose: nil asks the router once and offers what it answers. Otherwise a second request, sent at
    ///     the same moment, asks for a route that prefers local streets, and `choose` says which candidates to
    ///     offer: it is given their lines, the router's own first (`own` of them) and the extra one last, and
    ///     returns the places of those to keep. It runs off the main actor (lines are compared point by point).
    public func routes(
        from location: CLLocation, to destination: GeoPoint, areaSpan: Double? = nil, deviceFirst: Bool = false,
        choosing choose: (@Sendable (_ shapes: [[CLLocationCoordinate2D]], _ own: Int) -> [Int])? = nil
    ) async throws -> [RouteOption] {
        let waypoint = Self.waypoint(destination, areaSpan: areaSpan)
        let start = UserLocation(clLocation: location)
        guard let choose else {
            let found = try await fetch(userLocation: start, waypoints: [waypoint], deviceFirst: deviceFirst)
            return Self.options(found.routes, notes: found.notes, isOffline: found.offline)
        }
        // Not after the first answer: the card waits for both, so they go out together.
        async let extra = self.fetch(userLocation: start, waypoints: [waypoint], deviceFirst: deviceFirst, localStreets: true)
        let found = try await fetch(userLocation: start, waypoints: [waypoint], deviceFirst: deviceFirst)
        var routes: [Route] = found.routes
        var notes: [RouteNotes] = routes.indices.map { found.notes.indices.contains($0) ? found.notes[$0] : RouteNotes() }
        // Only from the same source as the router's own routes: a card must not mix the server's with ones
        // from the device's tiles, which get no traffic times. A failed extra request costs nothing.
        if let local = try? await extra, local.offline == found.offline, let route = local.routes.first {
            routes.append(route)
            notes.append(local.notes.first ?? RouteNotes())
        }
        let own = found.routes.count
        let shapes: [[CLLocationCoordinate2D]] = routes.map { $0.geometry.map(\.clLocationCoordinate2D) }
        let kept: [Int] = await Task.detached { choose(shapes, own) }.value
        let chosen: [Int] = kept.filter { routes.indices.contains($0) }.prefix(Self.offered).map { $0 }
        // A choice of none must not cost the driver the routes the router found.
        guard !chosen.isEmpty else { return Self.options(found.routes, notes: found.notes, isOffline: found.offline) }
        return Self.options(chosen.map { routes[$0] }, notes: chosen.map { notes[$0] }, isOffline: found.offline)
    }

    /// Routes as the card lists them, numbered by their place.
    private static func options(_ routes: [Route], notes: [RouteNotes], isOffline: Bool) -> [RouteOption] {
        routes.enumerated().map { index, route in
            RouteOption(index: index, route: route, isOffline: isOffline, notes: notes.indices.contains(index) ? notes[index] : RouteNotes())
        }
    }

    /// Search gives an area's middle point, and Valhalla then ends the route on the nearest road inside it.
    /// Measured on FOSSGIS (2026-11-14): Sabiha Gökçen's middle → 31.9 min via airside service roads; held to
    /// tertiary roads and up → 19.7 min to the airport junction. Hospital campuses and malls ended on internal
    /// service roads too; without service roads they end on the street outside (Marmara Üniversitesi Pendik:
    /// 20 → 16 maneuvers, Tevfik İleri Caddesi). Small places and streets keep the nearest road.
    static func waypoint(_ destination: GeoPoint, areaSpan: Double?) -> Waypoint {
        let coordinate = GeographicCoordinate(lat: destination.latitude, lng: destination.longitude)
        guard let areaSpan, areaSpan >= 150 else { return Waypoint(coordinate: coordinate, kind: .break) }
        let road: ValhallaRoadClass = areaSpan >= 1500 ? .tertiary : .residential
        return createWaypointWithValhallaProperties(
            coordinate: coordinate,
            kind: .break,
            properties: ValhallaWaypointProperties(searchFilter: ValhallaLocationSearchFilter(minRoadClass: road))
        )
    }

    /// The routes for a request. Closed roads are kept off when another way exists: if the request fails with
    /// them in force (no route when the destination lies on one, or when the car stands on one that was
    /// reported closed), they are let go and it is asked once more, so a closure never leaves the driver
    /// without a route.
    /// - Parameter deviceFirst: for reroutes while driving; see `answer`.
    /// - Parameter localStreets: the extra candidate of a plan; see `valhallaProvider`.
    func fetch(
        userLocation: UserLocation, waypoints: [Waypoint], deviceFirst: Bool = false, localStreets: Bool = false
    ) async throws -> (routes: [Route], notes: [RouteNotes], offline: Bool) {
        // Read before the request: of two requests sent together, the one that fails second finds the list
        // already emptied by the first.
        let excluding = !closedRoads.isEmpty
        do {
            return try await answer(userLocation: userLocation, waypoints: waypoints, deviceFirst: deviceFirst, localStreets: localStreets)
        } catch where excluding && !Task.isCancelled {
            closedRoads = []
            return try await answer(userLocation: userLocation, waypoints: waypoints, deviceFirst: deviceFirst, localStreets: localStreets)
        }
    }

    /// Online first; with no connection or a failing server, the same request answered on the device.
    /// - Parameter deviceFirst: for reroutes while driving. The device answers in milliseconds and needs no
    ///   connection, and the server knows no more about traffic than the bundled tiles do; a slow answer
    ///   describes where the car was when it was asked. The server is the fallback then.
    private func answer(
        userLocation: UserLocation, waypoints: [Waypoint], deviceFirst: Bool, localStreets: Bool
    ) async throws -> (routes: [Route], notes: [RouteNotes], offline: Bool) {
        let chosen = try requestAdapter(localStreets: localStreets)
        let request = try Self.urlRequest(for: chosen.generateRequest(userLocation: userLocation, waypoints: waypoints))
        if deviceFirst, offline != nil, let body = request.httpBody {
            if let found = try? await onDevice(body, adapter: chosen) { return found }
        }
        do {
            let (routes, data) = try await online(request, adapter: chosen)
            return (routes, RouteNotes.of(data), false)
        } catch where !deviceFirst && Self.worthTryingOffline(error) {
            guard offline != nil, let body = request.httpBody else { throw error }
            return try await onDevice(body, adapter: chosen)
        }
    }

    /// The adapter that writes a request with the options in force. Ferrostar's adapter takes its options
    /// once, when it is built, so a request for local streets or round closed roads gets one of its own; any
    /// of them reads the answers.
    private func requestAdapter(localStreets: Bool) throws -> RouteAdapter {
        if !localStreets, closedRoads.isEmpty { return avoidsTolls ? tollFreeAdapter : adapter }
        return try RouteAdapter.fromWellKnownRouteProvider(wellKnownRouteProvider: Self.valhallaProvider(
            avoidingTolls: avoidsTolls, localStreets: localStreets, closed: closedRoads
        ))
    }

    /// The request answered from the tiles on the device; `offlineUnavailable` when they cannot route it.
    private func onDevice(_ body: Data, adapter: RouteAdapter) async throws -> (routes: [Route], notes: [RouteNotes], offline: Bool) {
        guard let offline else { throw PlanningError.offlineUnavailable }
        let routes: [Route], data: Data
        do {
            data = try await offline(body)
            routes = try adapter.parseResponse(response: data)
        } catch {
            throw PlanningError.offlineUnavailable
        }
        guard !routes.isEmpty else { throw PlanningError.offlineUnavailable }
        return (routes, RouteNotes.of(data), true)
    }

    private func online(_ request: URLRequest, adapter: RouteAdapter) async throws -> ([Route], Data) {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Valhalla answers "no path" (error 442) with 400; anything else non-2xx is a service problem.
        if status == 400 { throw PlanningError.noRoute }
        guard (200 ..< 300).contains(status) else { throw PlanningError.service(status: status) }
        let routes = try adapter.parseResponse(response: data)
        guard !routes.isEmpty else { throw PlanningError.noRoute }
        return (routes, data)
    }

    /// Whatever went wrong with the server (no connection, busy, down, refusing, an answer that cannot be read),
    /// the device can still answer. "No path" (HTTP 400) is the exception: the same tiles would say the same.
    static func worthTryingOffline(_ error: any Error) -> Bool {
        // A cancelled request (the driver picked another place) wants no answer at all, not one from the device.
        if let error = error as? URLError { return error.code != .cancelled }
        if error is CancellationError { return false }
        if case PlanningError.noRoute = error { return false }
        return true
    }

    private static func urlRequest(for request: RouteRequest) throws -> URLRequest {
        let (url, headers, body): (String, [String: String], Data?) = switch request {
        case let .httpPost(requestURL, requestHeaders, requestBody): (requestURL, requestHeaders, requestBody)
        case let .httpGet(requestURL, requestHeaders): (requestURL, requestHeaders, nil)
        }
        guard let parsed = URL(string: url) else { throw PlanningError.service(status: 0) }
        var urlRequest = URLRequest(url: parsed)
        urlRequest.httpMethod = body == nil ? "GET" : "POST"
        urlRequest.httpBody = body
        urlRequest.timeoutInterval = 20
        for (field, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        return IdentifiedLoader.identified(urlRequest)
    }
}

/// Network loader for Ferrostar's own requests (reroutes during navigation) with the identification
/// headers FOSSGIS asks apps to send.
public struct IdentifiedLoader: URLRequestLoading {
    public init() {}

    public func loadData(with urlRequest: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: Self.identified(urlRequest))
    }

    static func identified(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue("Atlas-iOS/1.0 (personal navigation app)", forHTTPHeaderField: "User-Agent")
        request.setValue("atlas-ios-personal", forHTTPHeaderField: "X-Client-Id")
        return request
    }
}

/// Reroutes during guidance send the same request as planning, but to the device first when it has the tiles;
/// the server answers when it has none or cannot route it.
extension RoutePlanner: @preconcurrency CustomRouteProvider {
    public func getRoutes(userLocation: UserLocation, waypoints: [Waypoint]) async throws -> [Route] {
        try await fetch(userLocation: userLocation, waypoints: waypoints, deviceFirst: true).routes
    }
}

/// What a route passes that a driver weighs before choosing it, from Valhalla's intersection classes.
public struct RouteNotes: Sendable, Equatable {
    /// A bridge, tunnel or motorway with a toll (Bosphorus bridges, Avrasya Tüneli, Kuzey Marmara Otoyolu).
    public var hasToll = false
    public var hasFerry = false

    public init(hasToll: Bool = false, hasFerry: Bool = false) {
        self.hasToll = hasToll
        self.hasFerry = hasFerry
    }

    private struct Response: Decodable {
        struct Route: Decodable { let legs: [Leg] }
        struct Leg: Decodable { let steps: [Step] }
        struct Step: Decodable { let intersections: [Intersection]? }
        struct Intersection: Decodable { let classes: [String]? }
        let routes: [Route]?
    }

    /// One entry per route of an OSRM-format answer, in its order; empty if it cannot be read.
    static func of(_ data: Data) -> [RouteNotes] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return [] }
        return (response.routes ?? []).map { route in
            let classes = Set(route.legs.flatMap(\.steps).flatMap { $0.intersections ?? [] }.flatMap { $0.classes ?? [] })
            return RouteNotes(hasToll: classes.contains("toll"), hasFerry: classes.contains("ferry"))
        }
    }
}

/// One route alternative, flattened for the UI.
public struct RouteOption: Identifiable {
    public let index: Int
    public let route: Route
    /// Computed on the device from the bundled Istanbul tiles (no connection): no live traffic for it.
    public var isOffline = false
    public var notes = RouteNotes()

    public var id: Int { index }
    public var distance: Double { route.distance }
    public var duration: TimeInterval { route.steps.reduce(0) { $0 + $1.duration } }
    public var coordinates: [CLLocationCoordinate2D] { route.geometry.map(\.clLocationCoordinate2D) }
    public var southWest: CLLocationCoordinate2D { route.bbox.sw.clLocationCoordinate2D }
    public var northEast: CLLocationCoordinate2D { route.bbox.ne.clLocationCoordinate2D }
    public var mainRoads: [String] {
        RouteSummary.mainRoads(route.steps.map { (name: $0.roadName, distance: $0.distance) })
    }

    /// The same route at another place in a list: the card's tiles and the map's labels go by `index`.
    public func placed(at index: Int) -> RouteOption {
        RouteOption(index: index, route: route, isOffline: isOffline, notes: notes)
    }
}

enum RouteSummary {
    /// The two roads carrying most of the distance, in driving order ("Sahil Bulvarı, Ankara Caddesi").
    static func mainRoads(_ steps: [(name: String?, distance: Double)], limit: Int = 2) -> [String] {
        let named = steps.compactMap { step -> (name: String, distance: Double)? in
            guard let name = step.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            return (name, step.distance)
        }
        // One road spelled two ways in OSM counts once, shown with its Turkish letters.
        let spelling = TurkishFold.preferredSpellings(named.map(\.name))
        var total: [String: Double] = [:]
        var order: [String] = []
        for step in named {
            let name = spelling[TurkishFold.fold(step.name)] ?? step.name
            if total[name] == nil { order.append(name) }
            total[name, default: 0] += step.distance
        }
        let top = Set(order.sorted { total[$0]! > total[$1]! }.prefix(limit))
        return order.filter(top.contains)
    }
}
