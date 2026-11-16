import CoreLocation
import Foundation

/// A closure, an accident or road works on the road ahead, as the traffic provider reports it with each
/// traffic round.
public struct RoadEvent: Sendable {
    public enum Kind: Sendable {
        case closure, accident, roadworks
    }

    public let kind: Kind
    /// Where it begins, in the provider's geometry (a few metres off the route's own line).
    public let coordinate: CLLocationCoordinate2D

    public init(kind: Kind, coordinate: CLLocationCoordinate2D) {
        self.kind = kind
        self.coordinate = coordinate
    }
}

/// Says each road event on the route once, early enough to act on: from a kilometre ahead, or from a minute's
/// drive when that is more (2 km at 120 km/h). Timed the way HazardWatch times cameras and bumps, and pure for
/// the same reason.
struct RoadEventWatch {
    /// The events on the current route with the distance from its start at which each begins, in driving
    /// order. Replaced after every traffic round and when the route changes; what has been said is kept.
    private(set) var events: [(event: RoadEvent, offset: CLLocationDistance)] = []
    /// By place rather than by position in `events`: the next round reports the same event again, and so
    /// does a new route that still passes it.
    private var announced: [RoadEvent] = []

    static func warningDistance(speed: Double) -> CLLocationDistance {
        max(1000, speed * 60)
    }

    /// Puts `events` on `path`: one counts when it begins within 30 m of the route, at that distance along it.
    mutating func place(_ events: [RoadEvent], on path: RoutePath) {
        var placed: [(event: RoadEvent, offset: CLLocationDistance)] = []
        for event in events {
            if let hit = path.project(event.coordinate, tolerance: 30) { placed.append((event: event, offset: hit.offset)) }
        }
        self.events = placed.sorted { $0.offset < $1.offset }
    }

    /// - Parameters:
    ///   - travelled: metres driven along the route.
    ///   - speed: m/s.
    /// - Returns: a sentence the first time an event comes within warning range; one per call, so a second
    ///   event in range on the same fix is said on the next one.
    mutating func update(travelled: CLLocationDistance, speed: Double) -> String? {
        for (event, offset) in events {
            let distance: CLLocationDistance = offset - travelled
            // Behind the car: passed, or begun before the car reached the measured stretch.
            guard distance > 0 else { continue }
            guard distance <= Self.warningDistance(speed: speed) else { break }
            if announced.contains(where: { Self.same($0, event) }) { continue }
            announced.append(event)
            // First heard of with the car all but on it: nothing left to say that the driver does not see.
            if distance >= 50 { return TurkishInstructions.roadEvent(event.kind, distance: distance) }
        }
        return nil
    }

    /// One event reported twice: the same kind beginning within 200 m. The provider's point for where an event
    /// begins moves a little from one round to the next.
    private static func same(_ a: RoadEvent, _ b: RoadEvent) -> Bool {
        guard a.kind == b.kind else { return false }
        let dx: Double = (a.coordinate.longitude - b.coordinate.longitude) * 111_320 * cos(a.coordinate.latitude * .pi / 180)
        let dy: Double = (a.coordinate.latitude - b.coordinate.latitude) * 110_540
        return dx * dx + dy * dy < 200 * 200
    }
}
