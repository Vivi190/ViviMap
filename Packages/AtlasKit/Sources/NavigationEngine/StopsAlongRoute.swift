import CoreLocation
import SearchEngine

/// A place on the way, for a stop: how far ahead of the car it meets the route, and on which side of it.
public struct PlaceAhead: Identifiable, Sendable {
    public enum Side: Sendable {
        case left, right
    }

    public let place: Place
    /// Metres along the route from the car to the point of the route nearest the place.
    public let ahead: CLLocationDistance
    /// Metres from the route to the place.
    public let offRoute: CLLocationDistance
    /// Seen in the direction of travel; nil for a place on the line itself.
    public let side: Side?

    public var id: String { place.id }
}

/// Places of one kind along the rest of the route, for a stop on the way (Yandex searches the route ahead while
/// driving, Google ranks by the detour). Pure, so the choice is testable without a drive.
enum StopsAlongRoute {
    /// Where the indexes are asked: every 1.5 km of the route ahead, 40 km at most. Each answers with the twelve
    /// nearest of a kind around a point; fuel stations lie a few kilometres apart, so the circles overlap.
    static let spacing: CLLocationDistance = 1500
    static let reach: CLLocationDistance = 40_000
    /// Farther from the line than this is not on the way.
    static let maxOffRoute: CLLocationDistance = 300
    /// Nearer than this the car is passing it already, too late to turn in.
    static let minAhead: CLLocationDistance = 200
    /// A metre off the route is driven there and back again, on smaller roads.
    static let offRouteWeight = 3.0
    /// In right-hand traffic a place on the left costs a turn across the traffic, on a divided road a U-turn to
    /// get there and another one to get back. Which kind of road it is is not known here: one cost for both.
    static let leftCost: CLLocationDistance = 1500

    /// The points to ask about, from the car on.
    static func points(on path: RoutePath, from car: CLLocationDistance) -> [CLLocationCoordinate2D] {
        guard car < path.length else { return [] }
        return stride(from: car, through: min(car + reach, path.length), by: spacing).map { path.point(at: $0).coordinate }
    }

    /// One list from the indexes' answers, the more trusted first: a place an earlier list has is left out of the
    /// later ones, and one that came back around several points is listed once.
    static func merged(_ lists: [[Place]]) -> [Place] {
        var kept: [Place] = []
        for list in lists {
            let earlier = kept
            var seen: Set<String> = []
            kept += list.filter { place in seen.insert(place.id).inserted && !earlier.contains { same($0, place) } }
        }
        return kept
    }

    /// The same business in two indexes, told apart as search does it (BusinessSearchProvider.same, internal to
    /// SearchEngine): within 100 m, and one name's words begin the other's ("Shell", "Shell Kartal").
    static func same(_ a: Place, _ b: Place) -> Bool {
        guard a.point.distance(to: b.point) <= 100 else { return false }
        let first = words(of: a.name), second = words(of: b.name)
        guard !first.isEmpty, !second.isEmpty else { return false }
        let (short, long) = first.count <= second.count ? (first, second) : (second, first)
        return Array(long.prefix(short.count)) == short
    }

    private static func words(of name: String) -> [String] {
        TurkishFold.fold(name).filter { $0 != "'" && $0 != "’" }.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// The places within reach of the route ahead, the cheapest to turn into first: the distance to drive there,
    /// each metre off the route three times, and a turn across the traffic for one on the left.
    static func ranked(_ places: [Place], on path: RoutePath, from car: CLLocationDistance, limit: Int = 12) -> [PlaceAhead] {
        // From behind the car: a place beside it has to meet the line there, not where the stretch ahead begins.
        let window = (car - maxOffRoute) ... (car + reach + maxOffRoute)
        let scored = places.compactMap { place -> (found: PlaceAhead, cost: Double)? in
            let point = place.point.coordinate
            guard let hit = path.project(point, tolerance: maxOffRoute, within: window), hit.offset - car >= minAhead else { return nil }
            let foot = path.point(at: hit.offset).coordinate
            let east = (point.longitude - foot.longitude) * 111_320 * cos(foot.latitude * .pi / 180)
            let north = (point.latitude - foot.latitude) * 110_540
            let course = hit.course * .pi / 180
            // Positive to the left of the way the car drives there.
            let across = sin(course) * north - cos(course) * east
            let side: PlaceAhead.Side? = abs(across) < 5 ? nil : across > 0 ? .left : .right
            let found = PlaceAhead(place: place, ahead: hit.offset - car, offRoute: hypot(east, north), side: side)
            return (found, found.ahead + offRouteWeight * found.offRoute + (side == .left ? leftCost : 0))
        }
        return scored.sorted { $0.cost < $1.cost }.prefix(limit).map { $0.found }
    }
}
