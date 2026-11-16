import CoreLocation
import Foundation

/// Scores a route with HERE Routing v8 Route Import: HERE matches the geometry to its network and returns
/// the time with live traffic (`duration`), without it (`baseDuration`) and the usual one (`typicalDuration`).
/// https://docs.here.com/routing/docs/routing-v8-route-import
///
/// HERE's terms allow showing this next to a third-party map with "© HERE" attribution; results are not
/// stored beyond the session (research §6).
public struct HERETrafficProvider: TrafficProvider {
    static let importURL = URL(string: "https://router.hereapi.com/v8/import")!
    static let flowURL = URL(string: "https://data.traffic.hereapi.com/v7/flow")!
    static let incidentsURL = URL(string: "https://data.traffic.hereapi.com/v7/incidents")!

    private let apiKey: String
    private let session: URLSession
    private let budget: RequestBudget

    /// nil when the build carries no key; the app then keeps saying "Trafik dahil değil".
    public init?(bundle: Bundle = .main, session: URLSession = .shared, budget: RequestBudget = .shared) {
        guard let key = HEREKey.read(from: bundle) else { return nil }
        self.init(apiKey: key, session: session, budget: budget)
    }

    init(apiKey: String, session: URLSession, budget: RequestBudget) {
        self.apiKey = apiKey
        self.session = session
        self.budget = budget
    }

    public func estimate(_ route: [CLLocationCoordinate2D]) async throws -> TrafficEstimate {
        guard route.count >= 2 else { throw TrafficError.notMatched }
        guard budget.spend(.routeImport) else { throw TrafficError.budgetExhausted }
        let (data, response) = try await session.data(for: request(for: route))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else { throw TrafficError.service(status: status) }
        return try HEREImportResponse.estimate(from: data)
    }

    func request(for route: [CLLocationCoordinate2D]) throws -> URLRequest {
        var components = URLComponents(url: Self.importURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "transportMode", value: "car"),
            URLQueryItem(name: "return", value: "summary,typicalDuration"),
            URLQueryItem(name: "apiKey", value: apiKey),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ImportBody(trace: HERETrace.points(route)))
        return request
    }

    /// Traffic v7 flow in a 400 m corridor around the route (POST: a long corridor overflows the URL). Wide
    /// enough for the roads beside the route as well, so one answer colours the route and draws the traffic
    /// around it while guiding. Classes 1–4, as on the city layer: measured 2026-11-16 on a 19.6 km route
    /// through Istanbul, 89 KB gzipped (541 results), against 33 KB for a 20 m corridor of every class, in
    /// which only 2 of 163 results were local streets.
    /// https://docs.here.com/traffic-api/docs/geospatial-filters-here-traffic-api-v7-concepts
    public func flow(along route: [CLLocationCoordinate2D]) async throws -> [FlowSegment] {
        guard route.count >= 2 else { return [] }
        guard budget.spend(.flow) else { throw TrafficError.budgetExhausted }
        let (data, response) = try await session.data(for: flowRequest(for: route))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else { throw TrafficError.service(status: status) }
        return try HEREFlowResponse.segments(from: data)
    }

    func flowRequest(for route: [CLLocationCoordinate2D]) throws -> URLRequest {
        var components = URLComponents(url: Self.flowURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // HERE caps a corridor at 300 points.
        let corridor = HERETrace.points(route, limit: 300).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        request.httpBody = try JSONEncoder().encode(FlowBody(
            in: .init(type: "corridor", corridor: FlexiblePolyline.encode(corridor), radius: Self.corridorRadius),
            locationReferencing: ["shape"],
            functionalClasses: [1, 2, 3, 4]
        ))
        return request
    }

    /// Traffic v7 flow in a box, at every jam factor: flowing roads are drawn too, green. The wider the box, the
    /// fewer road classes it asks for, so the answer stays a size a phone can take (areaFlowRequest).
    public func flow(in area: TrafficArea) async throws -> [FlowSegment] {
        guard area.fitsHERE else { return [] }
        guard budget.spend(.areaFlow) else { throw TrafficError.budgetExhausted }
        let (data, response) = try await session.data(for: areaFlowRequest(for: area))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else { throw TrafficError.service(status: status) }
        return try HEREFlowResponse.segments(from: data)
    }

    public func incidents(in area: TrafficArea) async throws -> [TrafficIncident] {
        guard area.fitsHERE else { return [] }
        guard budget.spend(.incidents) else { throw TrafficError.budgetExhausted }
        let (data, response) = try await session.data(for: incidentsRequest(for: area))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else { throw TrafficError.service(status: status) }
        return try HEREIncidentsResponse.incidents(from: data)
    }

    func incidentsRequest(for area: TrafficArea) -> URLRequest {
        var components = URLComponents(url: Self.incidentsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "in", value: "bbox:\(area.west),\(area.south),\(area.east),\(area.north)"),
            URLQueryItem(name: "locationReferencing", value: "shape"),
            URLQueryItem(name: "apiKey", value: apiKey),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        return request
    }

    func areaFlowRequest(for area: TrafficArea) throws -> URLRequest {
        var components = URLComponents(url: Self.flowURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "apiKey", value: apiKey)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Fewer road classes the larger the box, as Yandex thins its traffic out with the zoom (motorways and
        // trunk roads only from about zoom 11 out) and so the answer stays a size a phone can take. Measured
        // 2026-11-14 on a 0.30° x 0.15° box around Kartal–Tuzla: classes 1–3 gave 815 segments in 200 KB
        // (gzip), 1–4 gave 5 098 in 944 KB; the widest box the layer asks for, 0.99° x 0.7° over the whole city
        // with classes 1–2 (2026-11-16), gave 712 results in 223 KB. Never class 5 (local streets): asked for,
        // they were 8 of 750 results; HERE barely measures them.
        //
        // The box is built from 0.01° steps and a fixed margin, so its span is often one of these limits give or
        // take the last digit of a Double. That digit must not decide: the classes would change from one pan to
        // the next.
        let span: Double = area.span - 1e-9
        let classes: [Int]
        if span > 0.30 {
            classes = [1, 2]
        } else if span > 0.20 {
            classes = [1, 2, 3]
        } else {
            classes = [1, 2, 3, 4]
        }
        request.httpBody = try JSONEncoder().encode(AreaFlowBody(
            in: .init(type: "bbox", west: area.west, south: area.south, east: area.east, north: area.north),
            locationReferencing: ["shape"],
            // Flowing roads too, drawn green; HERE ignores minJamFactor unless maxJamFactor is sent too.
            minJamFactor: 0,
            maxJamFactor: 10,
            functionalClasses: classes
        ))
        return request
    }

    private struct AreaFlowBody: Encodable {
        struct Box: Encodable {
            let type: String
            let west: Double
            let south: Double
            let east: Double
            let north: Double
        }

        let `in`: Box
        let locationReferencing: [String]
        let minJamFactor: Double
        let maxJamFactor: Double
        /// Omitted when nil: every road class.
        let functionalClasses: [Int]?
    }

    private struct ImportBody: Encodable {
        let trace: [HERETrace.Point]
    }

    private struct FlowBody: Encodable {
        struct Area: Encodable {
            let type: String
            let corridor: String
            let radius: Int
        }

        let `in`: Area
        let locationReferencing: [String]
        let functionalClasses: [Int]
    }

    /// Metres on each side of the route in a corridor flow request.
    static let corridorRadius = 400
}

/// The key comes from the HERE_API_KEY build setting via Info.plist (CI secret), never from the source.
enum HEREKey {
    static func read(from bundle: Bundle) -> String? {
        normalized(bundle.object(forInfoDictionaryKey: "HEREAPIKey") as? String)
    }

    /// Empty or an unexpanded "$(HERE_API_KEY)" means the build had no key.
    static func normalized(_ raw: String?) -> String? {
        guard let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty, !key.hasPrefix("$(") else {
            return nil
        }
        return key
    }
}

enum HERETrace {
    struct Point: Encodable, Equatable {
        let lat: Double
        let lng: Double
    }

    /// At most `limit` points, evenly picked, both ends kept. Valhalla geometry is a few hundred points for
    /// a city route, so only long trips are thinned; the payload stays far below HERE's 50 000-point cap.
    static func points(_ route: [CLLocationCoordinate2D], limit: Int = 1000) -> [Point] {
        let picked: [CLLocationCoordinate2D]
        if route.count <= limit {
            picked = route
        } else {
            let step = Double(route.count - 1) / Double(limit - 1)
            picked = (0 ..< limit).map { route[Int((Double($0) * step).rounded())] }
        }
        return picked.map { Point(lat: $0.latitude, lng: $0.longitude) }
    }
}

enum HEREImportResponse {
    private struct Body: Decodable {
        struct Route: Decodable { let sections: [Section] }
        struct Section: Decodable { let summary: Summary? }
        struct Summary: Decodable {
            let duration: Double
            let baseDuration: Double?
            let typicalDuration: Double?
        }

        let routes: [Route]?
    }

    /// Sums the sections: HERE splits an imported trace at U-turns or links closed to cars.
    static func estimate(from data: Data) throws -> TrafficEstimate {
        let summaries = try JSONDecoder().decode(Body.self, from: data).routes?.first?.sections.compactMap(\.summary) ?? []
        guard !summaries.isEmpty else { throw TrafficError.notMatched }
        let typical = summaries.compactMap(\.typicalDuration)
        return TrafficEstimate(
            duration: summaries.reduce(0) { $0 + $1.duration },
            baseDuration: summaries.reduce(0) { $0 + ($1.baseDuration ?? $1.duration) },
            // A partial sum would understate the usual time, so only when every section has it.
            typicalDuration: typical.count == summaries.count ? typical.reduce(0, +) : nil
        )
    }
}
