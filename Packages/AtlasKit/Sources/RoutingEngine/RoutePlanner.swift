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
        /// No connection, and the tiles on the device could not route it either (e.g. outside Istanbul).
        case offlineUnavailable

        public var errorDescription: String? {
            switch self {
            case .noRoute: "Bu hedefe rota bulunamadı. Hedef kapalı bir alanda olabilir."
            case let .service(status): "Rota servisi yanıt vermedi (\(status)). Biraz sonra tekrar dene."
            case .offlineUnavailable: "İnternet yok; cihazdaki İstanbul verisiyle de rota bulunamadı. Hedef İstanbul dışında olabilir."
            }
        }
    }

    // FOSSGIS public Valhalla: fair use (1 request/s) for personal development; a self-hosted instance
    // replaces it later (docs/architecture.md, ADR-4).
    static let endpoint = "https://valhalla1.openstreetmap.de/route"

    let provider: WellKnownRouteProvider
    private let adapter: RouteAdapter
    private let session: URLSession
    /// Answers the same request on the device (bundled Istanbul tiles); nil in builds without them.
    private let offline: (@Sendable (Data) async throws -> Data)?

    public init(
        session: URLSession = .shared,
        offline: (@Sendable (Data) async throws -> Data)? = OfflineRouter.bundledRoute
    ) throws {
        provider = try Self.valhallaProvider()
        adapter = try RouteAdapter.fromWellKnownRouteProvider(wellKnownRouteProvider: provider)
        self.session = session
        self.offline = offline
    }

    /// Whether this build can route without a connection.
    public var canRouteOffline: Bool { offline != nil }

    /// Shared with the navigation session so reroutes use the same engine and options.
    public static func valhallaProvider() throws -> WellKnownRouteProvider {
        try WellKnownRouteProvider.valhalla(endpointUrl: endpoint, profile: "auto", optionsJson: nil)
            .withJsonOptions(options: [
                "directions_options": ["language": "tr-TR", "units": "kilometers"],
                "alternates": 2,
            ])
    }

    public func routes(from location: CLLocation, to destination: GeoPoint) async throws -> [RouteOption] {
        let waypoint = Waypoint(
            coordinate: GeographicCoordinate(lat: destination.latitude, lng: destination.longitude),
            kind: .break
        )
        let found = try await fetch(userLocation: UserLocation(clLocation: location), waypoints: [waypoint])
        return found.routes.enumerated().map { RouteOption(index: $0.offset, route: $0.element, isOffline: found.offline) }
    }

    /// Online first; with no connection or a failing server, the same request answered on the device.
    func fetch(userLocation: UserLocation, waypoints: [Waypoint]) async throws -> (routes: [Route], offline: Bool) {
        let request = try Self.urlRequest(for: adapter.generateRequest(userLocation: userLocation, waypoints: waypoints))
        do {
            return (try await online(request), false)
        } catch where Self.worthTryingOffline(error) {
            guard let offline, let body = request.httpBody else { throw error }
            let routes: [Route]
            do {
                routes = try adapter.parseResponse(response: try await offline(body))
            } catch {
                throw PlanningError.offlineUnavailable
            }
            guard !routes.isEmpty else { throw PlanningError.offlineUnavailable }
            return (routes, true)
        }
    }

    private func online(_ request: URLRequest) async throws -> [Route] {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Valhalla answers "no path" (error 442) with 400; anything else non-2xx is a service problem.
        if status == 400 { throw PlanningError.noRoute }
        guard (200 ..< 300).contains(status) else { throw PlanningError.service(status: status) }
        let routes = try adapter.parseResponse(response: data)
        guard !routes.isEmpty else { throw PlanningError.noRoute }
        return routes
    }

    /// No connection, or the public server failing (busy, down): the device can answer. "No path" cannot:
    /// the same tiles would say the same.
    static func worthTryingOffline(_ error: any Error) -> Bool {
        if error is URLError { return true }
        if case let PlanningError.service(status) = error { return status == 429 || status >= 500 || status == 0 }
        return false
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

/// Reroutes during guidance take the same path as planning: online first, the device without a connection.
extension RoutePlanner: @preconcurrency CustomRouteProvider {
    public func getRoutes(userLocation: UserLocation, waypoints: [Waypoint]) async throws -> [Route] {
        try await fetch(userLocation: userLocation, waypoints: waypoints).routes
    }
}

/// One route alternative, flattened for the UI.
public struct RouteOption: Identifiable {
    public let index: Int
    public let route: Route
    /// Computed on the device from the bundled Istanbul tiles (no connection): no live traffic for it.
    public var isOffline = false

    public var id: Int { index }
    public var distance: Double { route.distance }
    public var duration: TimeInterval { route.steps.reduce(0) { $0 + $1.duration } }
    public var coordinates: [CLLocationCoordinate2D] { route.geometry.map(\.clLocationCoordinate2D) }
    public var southWest: CLLocationCoordinate2D { route.bbox.sw.clLocationCoordinate2D }
    public var northEast: CLLocationCoordinate2D { route.bbox.ne.clLocationCoordinate2D }
    public var mainRoads: [String] {
        RouteSummary.mainRoads(route.steps.map { (name: $0.roadName, distance: $0.distance) })
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
