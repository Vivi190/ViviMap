import CoreLocation
import Foundation

/// "Hız sınırı 50." when the driver stays clearly over the posted limit (NavigationSession.speedLimit).
/// Clearly over: more than 10 % and at least 6 km/h above, so GPS speed jitter and the speedometer's own offset
/// stay quiet; held for 3 s, so a moment of overtaking is not worth a word. Again at most once a minute.
struct SpeedingWatch {
    var isEnabled = true
    private var overSince: Date?
    private var lastWarning: Date?

    /// - Parameters:
    ///   - speedKmh: GPS speed.
    ///   - limit: posted limit in km/h; nil where none is known (no warning without a sign).
    ///   - time: the fix's timestamp, so the rhythm follows the drive rather than the wall clock.
    mutating func update(speedKmh: Double, limit: Int?, at time: Date) -> String? {
        guard isEnabled, let limit, speedKmh > Double(limit) + max(6, Double(limit) * 0.1) else {
            overSince = nil
            return nil
        }
        let since = overSince ?? time
        overSince = since
        guard time.timeIntervalSince(since) >= 3 else { return nil }
        if let lastWarning, time.timeIntervalSince(lastWarning) < 60 { return nil }
        lastWarning = time
        return "Hız sınırı \(limit)."
    }
}

/// A posted speed limit from the traffic provider, for one stretch of the road ahead. OpenStreetMap has
/// `maxspeed` on 9 to 16 % of the road length around Pendik, Kartal and Tuzla; the provider measured the route
/// anyway and knows the limit nearly everywhere.
public struct RouteSpeedLimit: Sendable {
    /// Where the stretch starts, in the provider's geometry (a few metres off the route's own line).
    public let start: CLLocationCoordinate2D
    /// Metres of road it covers.
    public let length: CLLocationDistance
    public let kmh: Int

    public init(start: CLLocationCoordinate2D, length: CLLocationDistance, kmh: Int) {
        self.start = start
        self.length = length
        self.kmh = kmh
    }
}

/// Those limits placed on a route, to look one up where the car is.
struct RouteLimits {
    /// Metres a stretch is taken to run on past its own length. The provider's metres and the path's differ:
    /// on two Istanbul routes of 6 and 24 km (2026-11-16) the next stretch began up to 12 m after the length
    /// of the one before it had run out, and the sign must not blink off in between.
    static let slack: CLLocationDistance = 30

    /// In driving order: where each stretch begins and ends on the path, in its metres.
    private(set) var marks: [(from: CLLocationDistance, to: CLLocationDistance, kmh: Int)] = []

    init() {}

    /// Each stretch goes where its start meets the path (within 30 m), not where the lengths before it add up
    /// to: the provider's line and the route's differ by metres, and parts of the provider's can be missing.
    /// A stretch whose start is off the path (the route has changed since) is left out.
    /// - Parameter start: nothing is placed before this distance along the path (where the car is).
    init(_ stretches: [RouteSpeedLimit], on path: RoutePath, from start: CLLocationDistance = 0) {
        var from = start
        for stretch in stretches {
            // Each from the one before it on: a road the route takes twice (a U-turn on a dual carriageway)
            // cannot match its earlier pass.
            guard let hit = path.project(stretch.start, tolerance: 30, within: from ... .infinity) else { continue }
            marks.append((from: hit.offset, to: hit.offset + stretch.length + Self.slack, kmh: stretch.kmh))
            from = max(from, hit.offset)
        }
    }

    /// The limit `travelled` metres along the path: that of the last stretch begun, while it still runs. The
    /// first stretch also holds over the last metres before it begins: the provider's line starts a step into
    /// the route, and a car standing at the start would have no sign.
    func limit(at travelled: CLLocationDistance) -> Int? {
        var mark = marks.last(where: { $0.from <= travelled })
        if mark == nil, let first = marks.first, first.from - travelled <= Self.slack { mark = first }
        guard let mark, travelled <= mark.to else { return nil }
        return mark.kmh
    }
}
