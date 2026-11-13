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

        public var errorDescription: String? {
            switch self {
            case .noRoute: "Bu hedefe rota bulunamadı. Hedef kapalı bir alanda olabilir."
            case let .service(status): "Rota servisi yanıt vermedi (\(status)). Biraz sonra tekrar dene."
            }
        }
    }

    // FOSSGIS public Valhalla: fair use (1 request/s) for personal development; a self-hosted instance
    // replaces it later (docs/architecture.md, ADR-4).
    static let endpoint = "https://valhalla1.openstreetmap.de/route"

    let provider: WellKnownRouteProvider
    private let adapter: RouteAdapter
    private let session: URLSession

    public init(session: URLSession = .shared) throws {
        provider = try WellKnownRouteProvider.valhalla(endpointUrl: Self.endpoint, profile: "auto", optionsJson: nil)
            .withJsonOptions(options: [
                "directions_options": ["language": "tr-TR", "units": "kilometers"],
                "alternates": 2,
            ])
        adapter = try RouteAdapter.fromWellKnownRouteProvider(wellKnownRouteProvider: provider)
        self.session = session
    }

    public func routes(from location: CLLocation, to destination: GeoPoint) async throws -> [RouteOption] {
        let waypoint = Waypoint(
            coordinate: GeographicCoordinate(lat: destination.latitude, lng: destination.longitude),
            kind: .break
        )
        let request = try Self.urlRequest(for: adapter.generateRequest(userLocation: UserLocation(clLocation: location), waypoints: [waypoint]))
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Valhalla answers "no path" (error 442) with 400; anything else non-2xx is a service problem.
        if status == 400 { throw PlanningError.noRoute }
        guard (200 ..< 300).contains(status) else { throw PlanningError.service(status: status) }
        let routes = try adapter.parseResponse(response: data)
        guard !routes.isEmpty else { throw PlanningError.noRoute }
        return routes.enumerated().map { RouteOption(index: $0.offset, route: $0.element) }
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
        // FOSSGIS asks apps to identify themselves.
        urlRequest.setValue("Atlas-iOS/1.0 (personal navigation app)", forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("atlas-ios-personal", forHTTPHeaderField: "X-Client-Id")
        return urlRequest
    }
}

/// One route alternative, flattened for the UI.
public struct RouteOption: Identifiable {
    public let index: Int
    public let route: Route

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
        var total: [String: Double] = [:]
        var order: [String] = []
        for step in steps {
            guard let name = step.name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { continue }
            if total[name] == nil { order.append(name) }
            total[name, default: 0] += step.distance
        }
        let top = Set(order.sorted { total[$0]! > total[$1]! }.prefix(limit))
        return order.filter(top.contains)
    }
}
