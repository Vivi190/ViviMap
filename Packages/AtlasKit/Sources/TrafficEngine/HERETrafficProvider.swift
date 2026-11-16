import CoreLocation
import Foundation

/// Scores a route with HERE Routing v8 Route Import: HERE matches the geometry to its network and returns
/// the time with live traffic (`duration`), without it (`baseDuration`) and the usual one (`typicalDuration`).
/// The same answer carries the matched line cut into spans with their speed limits, and the road events
/// (closures, accidents, road works) on it.
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
            // The matched line, its spans and the road events on it come in the same answer as the times: the
            // speed limits and events along the route cost no request of their own (HERE asks for `polyline`
            // whenever `spans` is given, and for `incidents` in both to tie an event to its spans).
            URLQueryItem(name: "return", value: "polyline,summary,typicalDuration,incidents"),
            URLQueryItem(name: "spans", value: "maxSpeed,length,incidents"),
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

        struct Section: Decodable {
            let summary: Summary?
            /// The matched line as a flexible polyline; the spans point into it.
            let polyline: String?
            let spans: [Span]
            /// The road events on the section; the spans name them by their place in this list.
            let incidents: [Incident]

            private enum CodingKeys: String, CodingKey {
                case summary, polyline, spans, incidents
            }

            /// The line, its spans and the events are extras: an answer without them, or with ones that cannot
            /// be read, still gives the times.
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                summary = try container.decodeIfPresent(Summary.self, forKey: .summary)
                polyline = try? container.decode(String.self, forKey: .polyline)
                spans = (try? container.decode([Span].self, forKey: .spans)) ?? []
                incidents = (try? container.decode([Incident].self, forKey: .incidents)) ?? []
            }
        }

        /// A run of the section's line with the same attributes.
        struct Span: Decodable {
            /// Index of its first point in the section's line.
            let offset: Int?
            /// Metres.
            let length: Double?
            /// Metres per second. Where there is no limit HERE writes the word "unlimited", read here as none.
            let maxSpeed: Double?
            /// The section's events that apply along the span.
            let incidents: [Int]
            /// The section's events that block the junction at the end of the span.
            let intersectionIncidents: [Int]

            private enum CodingKeys: String, CodingKey {
                case offset, length, maxSpeed, incidents, intersectionIncidents
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                offset = try? container.decode(Int.self, forKey: .offset)
                length = try? container.decode(Double.self, forKey: .length)
                maxSpeed = try? container.decode(Double.self, forKey: .maxSpeed)
                incidents = (try? container.decode([Int].self, forKey: .incidents)) ?? []
                intersectionIncidents = (try? container.decode([Int].self, forKey: .intersectionIncidents)) ?? []
            }
        }

        /// A road event as the Routing API gives it (`TrafficIncident` in its definition): no geometry of its
        /// own, the spans that name it say where it lies.
        struct Incident: Decodable {
            /// `accident`, `construction`, `roadClosure`, `congestion` …: an open list.
            let type: String?
            /// `critical` means the stretch cannot be driven.
            let criticality: String?
            let description: String?
            let id: String?
        }

        struct Summary: Decodable {
            let duration: Double
            let baseDuration: Double?
            let typicalDuration: Double?
        }

        let routes: [Route]?
    }

    /// Sums the sections: HERE splits an imported trace at U-turns or links closed to cars.
    static func estimate(from data: Data) throws -> TrafficEstimate {
        let sections: [Body.Section] = try JSONDecoder().decode(Body.self, from: data).routes?.first?.sections ?? []
        let summaries: [Body.Summary] = sections.compactMap { $0.summary }
        guard !summaries.isEmpty else { throw TrafficError.notMatched }
        let typical = summaries.compactMap(\.typicalDuration)
        var events: [TrafficIncident] = []
        var seen: Set<String> = []
        for section in sections {
            events += Self.events(in: section, seen: &seen)
        }
        return TrafficEstimate(
            duration: summaries.reduce(0) { $0 + $1.duration },
            baseDuration: summaries.reduce(0) { $0 + ($1.baseDuration ?? $1.duration) },
            // A partial sum would understate the usual time, so only when every section has it.
            typicalDuration: typical.count == summaries.count ? typical.reduce(0, +) : nil,
            limits: sections.flatMap { limits(in: $0) },
            events: events
        )
    }

    /// The closures, accidents and road works of a section in driving order, each with the stretch of the
    /// section's line covered by the spans that name it. One no span names has no place and is left out.
    /// - Parameter seen: HERE's ids of the events already taken: one that runs across two sections of a split
    ///   answer counts once.
    private static func events(in section: Body.Section, seen: inout Set<String>) -> [TrafficIncident] {
        guard !section.incidents.isEmpty, let encoded = section.polyline else { return [] }
        let line: [CLLocationCoordinate2D] = FlexiblePolyline.decode(encoded)
        // Per event, the first and the last point of the line it reaches.
        var reach: [Int: (from: Int, to: Int)] = [:]
        func cover(_ incident: Int, _ from: Int, _ to: Int) {
            let known = reach[incident]
            reach[incident] = (from: min(known?.from ?? from, from), to: max(known?.to ?? to, to))
        }
        for (position, span) in section.spans.enumerated() {
            guard let offset = span.offset, line.indices.contains(offset) else { continue }
            // A span ends where the next one begins, the last one where the line does.
            let next: Int? = position + 1 < section.spans.count ? section.spans[position + 1].offset : nil
            let end: Int = min(max(next ?? line.count - 1, offset), line.count - 1)
            for incident in span.incidents { cover(incident, offset, end) }
            for incident in span.intersectionIncidents { cover(incident, end, end) }
        }
        var events: [TrafficIncident] = []
        for (index, stretch) in reach.sorted(by: { ($0.value.from, $0.key) < ($1.value.from, $1.key) }) {
            guard section.incidents.indices.contains(index) else { continue }
            let incident = section.incidents[index]
            guard let kind = eventKind(incident) else { continue }
            if let id = incident.id, !seen.insert(id).inserted { continue }
            events.append(TrafficIncident(
                kind: kind, points: Array(line[stretch.from ... stretch.to]), summary: incident.description ?? ""
            ))
        }
        return events
    }

    /// Closures, accidents and road works, as on the city layer; congestion belongs to the flow colours, and
    /// the rest (weather, events) says little to a driver. HERE marks a stretch that cannot be driven as
    /// `critical` whatever closed it.
    private static func eventKind(_ incident: Body.Incident) -> TrafficIncident.Kind? {
        if incident.type == "roadClosure" || incident.criticality == "critical" { return .closure }
        if incident.type == "accident" { return .accident }
        if incident.type == "construction" { return .roadworks }
        return nil
    }

    /// The spans of a section that carry a speed limit, each from the point of the section's line it starts at.
    private static func limits(in section: Body.Section) -> [SpeedLimitStretch] {
        guard let encoded = section.polyline else { return [] }
        let line: [CLLocationCoordinate2D] = FlexiblePolyline.decode(encoded)
        var stretches: [SpeedLimitStretch] = []
        for span in section.spans {
            guard let offset = span.offset, line.indices.contains(offset), let length = span.length, length > 0,
                  let limit = kmh(span.maxSpeed)
            else { continue }
            stretches.append(SpeedLimitStretch(start: line[offset], length: length, kmh: limit))
        }
        return stretches
    }

    /// The limit as its sign reads, km/h. HERE gives metres per second in single precision (50 km/h arrives as
    /// 13.8888893), so the product is a hair off the sign's number and rounding gives it back. nil for no
    /// number, none above zero, or one no sign carries.
    static func kmh(_ metresPerSecond: Double?) -> Int? {
        guard let metresPerSecond, metresPerSecond.isFinite else { return nil }
        let value: Double = (metresPerSecond * 3.6).rounded()
        return (1 ... 200).contains(value) ? Int(value) : nil
    }
}
