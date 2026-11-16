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

    /// Which candidate routes to offer, `limit` at most (the route card has three tiles), as their places in
    /// `shapes`, in the order given. The first `own` are the router's own answer and are not judged against each
    /// other; the rest are extra candidates (a route asked for with other preferences), offered only when they
    /// run along another road than every route before them. When more than `limit` remain: the router's first,
    /// then one at a time the candidate that shares least with those already kept.
    public static func choice(of shapes: [[CLLocationCoordinate2D]], own: Int, limit: Int = 3) -> [Int] {
        var candidates: [Int] = Array(shapes.indices.prefix(max(own, 0)))
        for extra in shapes.indices.dropFirst(candidates.count) {
            if candidates.allSatisfy({ share(of: shapes[extra], along: shapes[$0]) < sameRoute }) { candidates.append(extra) }
        }
        guard candidates.count > limit, let first = candidates.first else { return candidates }
        var kept: [Int] = [first]
        var rest: [Int] = Array(candidates.dropFirst())
        while kept.count < limit, !rest.isEmpty {
            // How much of each remaining candidate runs along the kept route it is most like.
            let likeness: [Double] = rest.map { candidate in
                kept.map { share(of: shapes[candidate], along: shapes[$0]) }.max() ?? 0
            }
            var pick = 0
            for index in likeness.indices where likeness[index] < likeness[pick] { pick = index }
            kept.append(rest.remove(at: pick))
        }
        return kept.sorted()
    }

    /// Which of `fresh` (the router's new answer) takes the place of a candidate found to run through a closed
    /// stretch: the first that keeps off at least part of `closed` (points on that stretch) and runs along
    /// another road than each of `others`, the candidates beside it on the card. nil when none does: the
    /// router found no way round, or only ways the card already shows.
    public static func replacement(
        among fresh: [[CLLocationCoordinate2D]], besides others: [[CLLocationCoordinate2D]], avoiding closed: [CLLocationCoordinate2D]
    ) -> Int? {
        fresh.indices.first { index in
            // 5 m: on the very road. The other carriageway of a dual road is further away than that.
            share(of: closed, along: fresh[index], tolerance: 5) < 1
                && others.allSatisfy { share(of: fresh[index], along: $0) < sameRoute }
        }
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
