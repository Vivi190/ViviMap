import CoreLocation
import Foundation

/// ADR-5 decision layer: suggest another route only for a clear and stable gain, never right before a turn.
/// The thresholds are the ADR's starting guesses; Phase 8 tunes them with recorded drives.
public struct RerouteAdvisor: Sendable {
    public struct Candidate: Equatable, Sendable {
        public let index: Int
        public let duration: TimeInterval

        public init(index: Int, duration: TimeInterval) {
            self.index = index
            self.duration = duration
        }
    }

    public var minimumGain: TimeInterval = 180
    public var minimumShare = 0.15
    public var cooldown: TimeInterval = 180
    public var quietZone: CLLocationDistance = 300

    public init() {}

    /// - Parameters:
    ///   - current: traffic time for the rest of the current route.
    ///   - alternatives: traffic times of genuinely different routes, measured by the same provider.
    ///   - sinceLastChange: seconds since the route last changed or a suggestion was shown.
    public func suggestion(
        current: TimeInterval,
        alternatives: [Candidate],
        distanceToManeuver: CLLocationDistance?,
        sinceLastChange: TimeInterval
    ) -> Candidate? {
        guard sinceLastChange >= cooldown,
              (distanceToManeuver ?? .infinity) >= quietZone,
              let best = alternatives.min(by: { $0.duration < $1.duration })
        else { return nil }
        let gain = current - best.duration
        return gain >= max(minimumGain, current * minimumShare) ? best : nil
    }
}

/// How much of one route runs along another; above 85 % the two count as the same route (ADR-5).
public enum RouteOverlap {
    public static let sameRoute = 0.85

    /// Share of `candidate`'s points within `tolerance` metres of the `reference` polyline.
    public static func share(
        of candidate: [CLLocationCoordinate2D],
        along reference: [CLLocationCoordinate2D],
        tolerance: CLLocationDistance = 30
    ) -> Double {
        guard !candidate.isEmpty, reference.count > 1 else { return 0 }
        let near = candidate.filter { point in
            zip(reference, reference.dropFirst()).contains { distance(point, $0, $1) <= tolerance }
        }
        return Double(near.count) / Double(candidate.count)
    }

    /// Point to segment distance in metres on a local flat projection (fine at city scale).
    static func distance(_ p: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        let metresPerDegreeLon = 111_320 * cos(p.latitude * .pi / 180)
        let ax = (a.longitude - p.longitude) * metresPerDegreeLon, ay = (a.latitude - p.latitude) * 110_540
        let bx = (b.longitude - p.longitude) * metresPerDegreeLon, by = (b.latitude - p.latitude) * 110_540
        let dx = bx - ax, dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared == 0 ? 0 : max(0, min(1, -(ax * dx + ay * dy) / lengthSquared))
        return hypot(ax + t * dx, ay + t * dy)
    }
}
