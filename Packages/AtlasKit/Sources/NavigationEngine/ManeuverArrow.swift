import CoreLocation
@preconcurrency import FerrostarCoreFFI

/// The white arrow on the route at the next turn, as Apple's and Google's maps draw it: the road into the
/// maneuver and out of it, with a head where to go. Lines in map coordinates, no images.
enum ManeuverArrow {
    /// Only for maneuvers that change direction; going straight on or arriving needs no arrow.
    static func wanted(type: ManeuverType?, modifier: ManeuverModifier?) -> Bool {
        switch type {
        case .roundabout?, .rotary?, .roundaboutTurn?: true
        case .depart?, .arrive?, .notification?, nil: false
        default: modifier != nil && modifier != .straight
        }
    }

    /// How far past the maneuver the arrow runs: through a roundabout and 15 m into its exit (the step after
    /// it), so the head points down the road to take; ending at the exit, it pointed round the circle (CI 3c).
    static func reach(type: ManeuverType?, nextStep: CLLocationDistance?) -> CLLocationDistance {
        switch type {
        case .roundabout?, .rotary?, .roundaboutTurn?: min((nextStep ?? 0) + 15, 150)
        default: 15
        }
    }

    /// Shaft from 30 m before the maneuver to `after` metres past it, and a V-shaped head at its tip.
    static func lines(along path: RoutePath, maneuverAt offset: CLLocationDistance, after: CLLocationDistance) -> [[CLLocationCoordinate2D]] {
        let end = min(offset + after, path.length)
        let shaft = path.slice(from: max(0, offset - 30), to: end)
        guard shaft.count > 1 else { return [] }
        let tip = path.point(at: end)
        let back = tip.course + 180
        let head = [move(tip.coordinate, metres: 9, bearing: back - 40), tip.coordinate, move(tip.coordinate, metres: 9, bearing: back + 40)]
        return [shaft, head]
    }

    private static func move(_ c: CLLocationCoordinate2D, metres: Double, bearing: Double) -> CLLocationCoordinate2D {
        let angle = bearing * .pi / 180
        return CLLocationCoordinate2D(
            latitude: c.latitude + metres * cos(angle) / 110_540,
            longitude: c.longitude + metres * sin(angle) / (111_320 * cos(c.latitude * .pi / 180))
        )
    }
}
