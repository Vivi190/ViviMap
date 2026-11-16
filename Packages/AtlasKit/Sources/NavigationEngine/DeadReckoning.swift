import CoreLocation
import Foundation

/// In a tunnel the GPS goes quiet: the car stops on the map and a turn right after the exit is announced late
/// or not at all. With no fix for a few seconds while the car was moving on its route, it is moved along the
/// route at the speed it last had, as Yandex, Google and Apple Maps do; the first real fix takes over.
///
/// It never runs past the next maneuver: a made-up position there would end the step, and a real fix behind
/// it would then be off the new step and start a reroute. So it stops short of the maneuver, where the prompts
/// for it have been said, and waits there for the real fix.
struct DeadReckoning {
    /// No fix for this long counts as lost (CoreLocation sends one a second while driving).
    static let silence: TimeInterval = 3
    /// Moving at least this fast (18 km/h) when the signal went; slower, the car may be standing in a queue.
    static let minimumSpeed: CLLocationSpeed = 5
    /// After this long a guess is worth less than the car standing still on the map.
    static let longest: TimeInterval = 120
    /// How far before the next maneuver it stops: beyond the 30 m at which a step may end.
    static let beforeManeuver: CLLocationDistance = 40

    /// Where the car is taken to be `elapsed` seconds after its last real fix, in metres along the route;
    /// nil when it is not worth a guess (too soon, too late, too slow).
    /// - Parameters:
    ///   - from: metres along the route at the last real fix.
    ///   - maneuver: metres along the route of the next maneuver at that fix.
    ///   - length: the route's length.
    static func offset(
        from: CLLocationDistance, speed: CLLocationSpeed, elapsed: TimeInterval,
        maneuver: CLLocationDistance, length: CLLocationDistance
    ) -> CLLocationDistance? {
        guard elapsed >= silence, elapsed <= longest, speed >= minimumSpeed else { return nil }
        let limit = min(maneuver, length) - beforeManeuver
        guard limit > from else { return nil }
        return min(from + speed * elapsed, limit)
    }
}
