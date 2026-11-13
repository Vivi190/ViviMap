import Foundation

/// Decides when to speak for the current maneuver: early, close, and at the turn — scaled by speed so a
/// driver on D-100 hears it as many seconds ahead as one in a side street. Each stage is spoken once per step.
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
    ///   - speed: current speed in m/s (unknown or slow is treated as city speed).
    public mutating func stage(step: Int, distance: Double, speed: Double) -> Stage? {
        if step != self.step {
            self.step = step
            spoken = []
        }
        let v = max(speed, 8) // ≈ 30 km/h floor so slow traffic still gets early warnings
        let stage: Stage
        if distance <= max(v * 3, 25) {
            stage = .now
        } else if distance <= min(max(v * 9, 120), 450) {
            stage = .close
        } else if distance <= min(max(v * 25, 400), 1500) {
            stage = .early
        } else {
            return nil
        }
        // Never go back to a farther stage, never repeat one.
        guard !spoken.contains(where: { $0 >= stage }) else { return nil }
        spoken.insert(stage)
        return stage
    }
}
