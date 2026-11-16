import Foundation

/// Decides when to speak for the current maneuver: early, close, and at the turn — scaled by speed so a
/// driver on D-100 hears it as many seconds ahead as one in a side street. Each stage is spoken once per step,
/// and a stage is left out when the next one would follow within about 8 s: a short step is not announced
/// twice in a row, and at speed a turn gets two prompts instead of three.
public struct AnnouncementPlanner: Sendable {
    public enum Stage: Int, Comparable, Sendable {
        case early, close, now

        public static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private var step: Int?
    private var spoken: Set<Stage> = []

    public init() {}

    /// - Parameters:
    ///   - step: identifies the maneuver (e.g. remaining step count); a new value resets the stages.
    ///   - distance: metres to the maneuver.
    ///   - speed: m/s (unknown or slow is treated as city speed).
    ///   - hasNow: false when there is nothing to say at the point itself (a destination with no side of the
    ///     street), so the close stage has nothing to make room for.
    ///   - holdsDistance: true while a sentence is being spoken. Early and close carry a distance that would be
    ///     out of date by the time a queued sentence is heard, so they wait for a later call; the stage at the
    ///     turn is never held.
    public mutating func stage(
        step: Int, distance: Double, speed: Double, hasNow: Bool = true, holdsDistance: Bool = false
    ) -> Stage? {
        if step != self.step {
            self.step = step
            spoken = []
        }
        let v = max(speed, 8) // ≈ 30 km/h floor so slow traffic still gets early warnings
        // 4 s, and never under 45 m: Ferrostar starts looking for the end of the step 30 m before it, and the
        // prompt has to be out before the card moves on to the next maneuver.
        let nowAt = max(v * 4, 45)
        let closeAt = min(max(v * 9, 120), 450)
        let earlyAt = min(max(v * 25, 400), 1500)
        let spacing = v * 8
        // Whether a close prompt at its own threshold leaves that much room before the one at the turn. Above
        // about 34 km/h it does not, and the early stage is then measured against the turn itself.
        let closeStands = !hasNow || closeAt - nowAt >= spacing
        let stage: Stage
        if distance <= nowAt {
            guard hasNow else { return nil }
            stage = .now
        } else if distance <= closeAt {
            if hasNow, distance - nowAt < spacing { return nil }
            stage = .close
        } else if distance <= earlyAt {
            let nearer = closeStands ? closeAt : nowAt
            if distance - nearer < spacing { return nil }
            stage = .early
        } else {
            return nil
        }
        // Never go back to a farther stage, never repeat one.
        guard !spoken.contains(where: { $0 >= stage }) else { return nil }
        if holdsDistance, stage != .now { return nil }
        spoken.insert(stage)
        return stage
    }
}
