import CoreLocation
import Foundation

/// One directional road stretch from HERE Traffic flow.
public struct FlowSegment: Sendable {
    public let points: [CLLocationCoordinate2D]
    /// 0 free flow … 10 standstill or closed (HERE's scale).
    public let jamFactor: Double
    public let isClosed: Bool
    /// Measured now. False when the provider filled the value in from historical data or the speed limit: that
    /// is how the road usually moves, not how it moves now.
    public let isLive: Bool
    /// HERE's functional class, 1 (motorway) … 5 (local street); nil when not given.
    public let roadClass: Int?
    /// Current speed in m/s, not capped at the legal limit where the provider tells the two apart.
    public let speed: Double?
    /// Speed without traffic, m/s.
    public let freeFlow: Double?
    /// Metres along the stretch.
    public let length: Double

    /// `length` is measured along `points` when not given.
    public init(
        points: [CLLocationCoordinate2D],
        jamFactor: Double,
        isClosed: Bool,
        isLive: Bool = true,
        roadClass: Int? = nil,
        speed: Double? = nil,
        freeFlow: Double? = nil,
        length: Double? = nil
    ) {
        self.points = points
        self.jamFactor = jamFactor
        self.isClosed = isClosed
        self.isLive = isLive
        self.roadClass = roadClass
        self.speed = speed
        self.freeFlow = freeFlow
        self.length = length ?? FlowSegment.metres(along: points)
    }

    /// Metres along a line, on a local flat projection (fine at city scale).
    static func metres(along points: [CLLocationCoordinate2D]) -> Double {
        var total = 0.0
        for index in points.indices.dropFirst() {
            total += metres(points[index - 1], points[index])
        }
        return total
    }

    static func metres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dx = (b.longitude - a.longitude) * 111_320 * cos(a.latitude * .pi / 180)
        let dy = (b.latitude - a.latitude) * 110_540
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// A stretch of the route to colour by traffic.
public struct TrafficSection: Sendable {
    /// `free` only on the city layer; a route's flowing stretches stay route-blue.
    public enum Level: Int, Sendable, CaseIterable {
        case free = 0, slow, heavy, stopped
    }

    public let level: Level
    public let coordinates: [CLLocationCoordinate2D]
    /// A motorway or main artery (HERE classes 1–2): the city layer draws it a little wider.
    public var isMajor = false
}

/// The city traffic layer: every stretch measured now, in HERE's own geometry (there is no route to snap it
/// to), flowing ones too, green as Yandex draws them: with only the slow ones coloured, a quiet hour looked
/// like no data.
public enum AreaTraffic {
    /// Segments are directional and keep HERE's geometry: the map draws each a few points to the right of its
    /// own direction, so the two directions of a street show side by side at every zoom.
    /// Closed stretches are left out: road events draw closures, and a dark red line over one would read as
    /// the worst jam on the map. So are values that are not live: a road nobody measured gets no colour, not
    /// the green of its usual speed.
    public static func sections(_ segments: [FlowSegment]) -> [TrafficSection] {
        segments.compactMap { segment in
            guard segment.points.count > 1, !segment.isClosed, segment.isLive else { return nil }
            return TrafficSection(
                level: RouteTraffic.level(segment) ?? .free, coordinates: segment.points, isMajor: (segment.roadClass ?? 5) <= 2
            )
        }
    }

    /// Metres of measured main road an answer needs before it can speak for an area.
    static let scoredLength = 3000.0

    /// How much longer the main roads in the answer take than when they are free, on Yandex's scale of 0
    /// (clear) to 10: 7 × (T − 1), T being the time to drive them now over the time at free flow, so 7 is twice
    /// as long, the one figure Yandex has published for its scale. Only open, live stretches of classes 1–3
    /// count: side streets are most of the road length and are rarely jammed, so with them the figure would
    /// stay low in the rush hour and change with the zoom. A stretch faster than its free flow counts as free,
    /// so it cannot offset a jam elsewhere; a standing queue counts as 0.5 m/s, so it cannot outweigh every
    /// other road. nil with too little measured road.
    public static func score(_ segments: [FlowSegment]) -> Int? {
        var travelTime = 0.0, freeTime = 0.0, measured = 0.0
        for segment in segments {
            guard segment.isLive, !segment.isClosed else { continue }
            // No class given counts as a main road.
            if let roadClass = segment.roadClass, roadClass > 3 { continue }
            guard let speed = segment.speed, let freeFlow = segment.freeFlow, speed > 0, freeFlow > 0 else { continue }
            travelTime += segment.length / min(max(speed, 0.5), freeFlow)
            freeTime += segment.length / freeFlow
            measured += segment.length
        }
        guard measured >= scoredLength, freeTime > 0 else { return nil }
        let value: Double = (7 * (travelTime / freeTime - 1)).rounded()
        return Int(min(10, max(0, value)))
    }

    /// The words Yandex's Turkish traffic feed puts next to each score.
    public static func label(score: Int) -> String {
        switch max(score, 0) {
        case 0, 1: "Trafik açık"
        case 2: "Trafik akıcı"
        case 3: "Yer yer yoğun, akıcı"
        case 4: "Yoğun, yer yer akıcı"
        case 5: "Yoğun trafik"
        case 6: "Çok yoğun trafik"
        case 7: "Trafik durma noktasında"
        case 8: "Kilometrelerce yoğunluk"
        case 9: "Trafik kilitlendi"
        default: "Yürümek daha hızlı"
        }
    }
}

public enum RouteTraffic {
    /// Jam factors from which a stretch is yellow, red and dark red. Set against Yandex Maps on the same Istanbul
    /// roads at the same minute (2026-11-16): Yandex drew 58 % green, 41 % yellow, 1 % red where HERE's own legend
    /// (4 / 8 / 10) gave 92 / 6 / 2. Yellow from 2 (about three quarters of the free-flow speed) brings the two
    /// pictures closest; red stays at 8 (about a third), where HERE is already redder than Yandex; dark red is
    /// a crawl under a tenth of the free-flow speed. 10 itself is reserved for closures.
    static let slowFrom = 2.0, heavyFrom = 8.0, stoppedFrom = 9.5

    /// Under `slowFrom` the road flows: nil, and a route leaves it uncoloured. A closed road is `stopped`
    /// whatever its jam factor, so a route keeps flagging the stretch it cannot use.
    static func level(_ segment: FlowSegment) -> TrafficSection.Level? {
        if segment.isClosed || segment.jamFactor >= stoppedFrom { return .stopped }
        if segment.jamFactor >= heavyFrom { return .heavy }
        if segment.jamFactor >= slowFrom { return .slow }
        return nil
    }

    /// The route's own geometry cut into coloured sections. Drawn over the route line, so they follow it
    /// exactly (HERE's road geometry sits a few metres off OSM's). An edge takes the worst level of the slow
    /// flow segments running along it in its direction; cross streets and the opposite carriageway, which the
    /// corridor query also returns, do not match.
    public static func sections(route: [CLLocationCoordinate2D], flow: [FlowSegment]) -> [TrafficSection] {
        let slow: [(FlowSegment, TrafficSection.Level)] = flow.compactMap { segment in
            // Live values only, as on the layer: a stretch that is merely slow at this hour on other days must
            // not be painted as a jam now. A closed stretch stays flagged whatever its confidence.
            guard segment.points.count > 1, segment.isLive || segment.isClosed, let band = level(segment) else { return nil }
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
        struct Link: Decodable {
            let points: [Point]
            let functionalClass: Int?
        }

        struct Point: Decodable {
            let lat: Double
            let lng: Double
        }

        /// The values of a whole result, or of one of its sub-segments (only those carry a `length`).
        struct Flow: Decodable {
            let jamFactor: Double?
            let traversability: String?
            let confidence: Double?
            let speed: Double?
            let speedUncapped: Double?
            let freeFlow: Double?
            let length: Double?
            let subSegments: [Flow]?
        }

        let results: [Result]?
    }

    /// HERE's confidence above this includes real-time data; 0.70 itself is historical data only, 0.5 and less
    /// the speed limit.
    private static let liveConfidence = 0.70

    /// A cut this close to a vertex, in metres, moves onto it. HERE's sub-segments end where two links meet
    /// and their lengths are whole metres, so most cuts land within a metre of a vertex; cut where they land,
    /// each piece would start or end with a stub shorter than that.
    private static let snap = 1.0

    /// One segment per result, its links joined into a single line. Where HERE splits a result into
    /// sub-segments (the long stretches of main roads, about half the road length of a city answer) each
    /// sub-segment is a segment of its own, so a colour changes where the traffic does and not kilometres away.
    static func segments(from data: Data) throws -> [FlowSegment] {
        let results: [Body.Result] = try JSONDecoder().decode(Body.self, from: data).results ?? []
        var segments: [FlowSegment] = []
        for result in results {
            guard let flow = result.currentFlow, let links = result.location.shape?.links else { continue }
            var points: [CLLocationCoordinate2D] = []
            // The most important class among the links (1 is a motorway).
            var roadClass: Int?
            for link in links {
                if let linkClass = link.functionalClass { roadClass = min(roadClass ?? linkClass, linkClass) }
                for point in link.points {
                    // Consecutive links share their joining point.
                    append(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lng), to: &points)
                }
            }
            let parts: [Body.Flow] = flow.subSegments ?? []
            let lengths: [Double] = parts.compactMap { $0.length }
            let pieces: [[CLLocationCoordinate2D]] = lengths.count == parts.count ? cut(points, lengths: lengths) : []
            if pieces.isEmpty {
                segments.append(segment(points, flow, of: flow, roadClass: roadClass))
            } else {
                for index in pieces.indices {
                    segments.append(segment(pieces[index], parts[index], of: flow, roadClass: roadClass))
                }
            }
        }
        return segments
    }

    /// A stretch with the values of `part`; what a sub-segment leaves out comes from the result it is part of.
    private static func segment(
        _ points: [CLLocationCoordinate2D], _ part: Body.Flow, of whole: Body.Flow, roadClass: Int?
    ) -> FlowSegment {
        let jamFactor: Double = part.jamFactor ?? whole.jamFactor ?? 0
        // A closed road has no confidence at all: nothing is measured there.
        let confidence: Double = part.confidence ?? whole.confidence ?? 0
        let speed: Double? = part.speedUncapped ?? part.speed ?? whole.speedUncapped ?? whole.speed
        return FlowSegment(
            points: points,
            // -1 means HERE could not compute one: treat as unknown, i.e. not coloured.
            jamFactor: max(0, jamFactor),
            isClosed: (part.traversability ?? whole.traversability) == "closed",
            isLive: confidence > liveConfidence,
            roadClass: roadClass,
            speed: speed,
            freeFlow: part.freeFlow ?? whole.freeFlow
        )
    }

    /// `points` cut into one line per length, in order. The lengths are HERE's and the line is measured on a
    /// flat projection, so they are scaled to fill the line; a cut inside an edge is interpolated. Empty when
    /// there is nothing to cut by.
    static func cut(_ points: [CLLocationCoordinate2D], lengths: [Double]) -> [[CLLocationCoordinate2D]] {
        guard points.count > 1, !lengths.isEmpty else { return [] }
        var declared = 0.0
        for length in lengths {
            guard length.isFinite, length >= 0 else { return [] }
            declared += length
        }
        // Metres from the start of the line to each vertex.
        var along: [Double] = [0]
        for index in 1 ..< points.count {
            along.append(along[index - 1] + FlowSegment.metres(points[index - 1], points[index]))
        }
        let total: Double = along[points.count - 1]
        guard declared > 0, total > 0 else { return [] }
        let scale: Double = total / declared

        var pieces: [[CLLocationCoordinate2D]] = []
        var piece: [CLLocationCoordinate2D] = [points[0]]
        // The first vertex not yet in a piece.
        var vertex = 1
        var covered = 0.0
        for length in lengths.dropLast() {
            covered += length
            let end: Double = covered * scale
            while vertex < points.count && along[vertex] <= end + snap {
                append(points[vertex], to: &piece)
                vertex += 1
            }
            let cutPoint: CLLocationCoordinate2D
            if vertex == points.count || end - along[vertex - 1] <= snap {
                // On the last vertex taken: it is within the snap distance, or the line ends there.
                cutPoint = points[vertex - 1]
            } else {
                let before: Double = end - along[vertex - 1]
                let after: Double = along[vertex] - end
                let share: Double = before / (before + after)
                let a = points[vertex - 1], b = points[vertex]
                cutPoint = CLLocationCoordinate2D(
                    latitude: a.latitude + (b.latitude - a.latitude) * share,
                    longitude: a.longitude + (b.longitude - a.longitude) * share
                )
            }
            append(cutPoint, to: &piece)
            pieces.append(piece)
            piece = [cutPoint]
        }
        // The last piece takes the rest of the line.
        while vertex < points.count {
            append(points[vertex], to: &piece)
            vertex += 1
        }
        pieces.append(piece)
        return pieces
    }

    /// Adds a point unless it repeats the last one.
    private static func append(_ point: CLLocationCoordinate2D, to line: inout [CLLocationCoordinate2D]) {
        if let last = line.last, last.latitude == point.latitude, last.longitude == point.longitude { return }
        line.append(point)
    }
}
