import CoreLocation
import Foundation

/// One directional road stretch from HERE Traffic flow.
public struct FlowSegment: Sendable {
    public let points: [CLLocationCoordinate2D]
    /// 0 free flow … 10 standstill or closed (HERE's scale).
    public let jamFactor: Double
    public let isClosed: Bool

    public init(points: [CLLocationCoordinate2D], jamFactor: Double, isClosed: Bool) {
        self.points = points
        self.jamFactor = jamFactor
        self.isClosed = isClosed
    }
}

/// A stretch of the route to colour by traffic.
public struct TrafficSection: Sendable {
    public enum Level: Int, Sendable, CaseIterable {
        case slow = 1, heavy, stopped
    }

    public let level: Level
    public let coordinates: [CLLocationCoordinate2D]
}

/// The city traffic layer: each slow, queuing or stopped stretch in HERE's own geometry (there is no route
/// to snap it to).
public enum AreaTraffic {
    /// Segments are directional: each is moved a few metres to the right of its travel direction (traffic
    /// keeps right), so the two directions of a street show side by side instead of one hiding the other.
    public static func sections(_ segments: [FlowSegment]) -> [TrafficSection] {
        segments.compactMap { segment in
            guard segment.points.count > 1, let level = RouteTraffic.level(segment) else { return nil }
            return TrafficSection(level: level, coordinates: offsetRight(segment.points, metres: 4))
        }
    }

    /// Each vertex shifted along the right-hand normal of the line through its neighbours.
    static func offsetRight(_ points: [CLLocationCoordinate2D], metres: Double) -> [CLLocationCoordinate2D] {
        points.indices.map { index in
            let before = points[max(index - 1, 0)], after = points[min(index + 1, points.count - 1)]
            let metresPerDegreeLon = 111_320 * cos(points[index].latitude * .pi / 180)
            let dx = (after.longitude - before.longitude) * metresPerDegreeLon
            let dy = (after.latitude - before.latitude) * 110_540
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0 else { return points[index] }
            // Right of the travel direction (dx, dy) is (dy, -dx).
            return CLLocationCoordinate2D(
                latitude: points[index].latitude - dx / length * metres / 110_540,
                longitude: points[index].longitude + dy / length * metres / metresPerDegreeLon
            )
        }
    }
}

public enum RouteTraffic {
    /// HERE's jam factor bands: under 4 flows (left uncoloured), 4–8 slow, 8–10 queuing, 10 or closed stopped.
    static func level(_ segment: FlowSegment) -> TrafficSection.Level? {
        if segment.isClosed || segment.jamFactor >= 10 { return .stopped }
        if segment.jamFactor >= 8 { return .heavy }
        if segment.jamFactor >= 4 { return .slow }
        return nil
    }

    /// The route's own geometry cut into coloured sections. Drawn over the route line, so they follow it
    /// exactly (HERE's road geometry sits a few metres off OSM's). An edge takes the worst level of the slow
    /// flow segments running along it in its direction; cross streets and the opposite carriageway, which the
    /// corridor query also returns, do not match.
    public static func sections(route: [CLLocationCoordinate2D], flow: [FlowSegment]) -> [TrafficSection] {
        let slow: [(FlowSegment, TrafficSection.Level)] = flow.compactMap { segment in
            guard segment.points.count > 1, let band = level(segment) else { return nil }
            return (segment, band)
        }
        guard route.count > 1, !slow.isEmpty else { return [] }
        var sections: [TrafficSection] = []
        var current: (level: TrafficSection.Level, coordinates: [CLLocationCoordinate2D])?
        for index in route.indices.dropLast() {
            let a = route[index], b = route[index + 1]
            if a.latitude == b.latitude, a.longitude == b.longitude {
                current?.coordinates.append(b) // duplicate point: no direction of its own
                continue
            }
            let level = edgeLevel(a, b, slow)
            if let level, level == current?.level {
                current?.coordinates.append(b)
            } else {
                if let done = current { sections.append(TrafficSection(level: done.level, coordinates: done.coordinates)) }
                current = level.map { ($0, [a, b]) }
            }
        }
        if let done = current { sections.append(TrafficSection(level: done.level, coordinates: done.coordinates)) }
        return sections
    }

    /// Worst level among flow segments passing within 15 m of the edge's middle, heading its way (±45°).
    static func edgeLevel(
        _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ slow: [(FlowSegment, TrafficSection.Level)]
    ) -> TrafficSection.Level? {
        let middle = CLLocationCoordinate2D(latitude: (a.latitude + b.latitude) / 2, longitude: (a.longitude + b.longitude) / 2)
        let heading = bearing(a, b)
        return slow.filter { segment, _ in
            zip(segment.points, segment.points.dropFirst()).contains { p, q in
                RouteOverlap.distance(middle, p, q) <= 15 && angle(bearing(p, q), heading) <= 45
            }
        }
        .map { $0.1 }
        .max { $0.rawValue < $1.rawValue }
    }

    static func angle(_ x: Double, _ y: Double) -> Double {
        let difference = abs(x - y).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dx = (b.longitude - a.longitude) * cos(a.latitude * .pi / 180)
        let dy = b.latitude - a.latitude
        return (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
}

enum HEREFlowResponse {
    private struct Body: Decodable {
        struct Result: Decodable {
            let location: Location
            let currentFlow: Flow?
        }

        struct Location: Decodable { let shape: Shape? }
        struct Shape: Decodable { let links: [Link] }
        struct Link: Decodable { let points: [Point] }
        struct Point: Decodable {
            let lat: Double
            let lng: Double
        }

        struct Flow: Decodable {
            let jamFactor: Double?
            let traversability: String?
        }

        let results: [Result]?
    }

    /// One segment per result, its links joined into a single line.
    static func segments(from data: Data) throws -> [FlowSegment] {
        try JSONDecoder().decode(Body.self, from: data).results?.compactMap { result in
            guard let flow = result.currentFlow, let links = result.location.shape?.links else { return nil }
            var points: [CLLocationCoordinate2D] = []
            for point in links.flatMap(\.points) {
                let coordinate = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lng)
                // Consecutive links share their joining point.
                if let last = points.last, last.latitude == coordinate.latitude, last.longitude == coordinate.longitude { continue }
                points.append(coordinate)
            }
            return FlowSegment(
                points: points,
                // -1 means HERE could not compute one: treat as unknown, i.e. not coloured.
                jamFactor: max(0, flow.jamFactor ?? 0),
                isClosed: flow.traversability == "closed"
            )
        } ?? []
    }
}
