import CoreLocation
import Foundation
import RoadHazards

/// A hazard on the route, placed by its distance from the route start.
public struct RouteHazard: Sendable, Equatable {
    public let hazard: Hazard
    public let offset: CLLocationDistance
}

/// What the banner shows: the next hazard ahead and how far it is.
public struct HazardAlert: Sendable, Equatable {
    public let kind: Hazard.Kind
    public let distance: CLLocationDistance
    public let maxspeed: Int?
}

enum RouteHazards {
    /// Hazards the route actually passes. Bumps sit on the road (10 m); cameras are often mapped beside it
    /// (20 m). A camera mapped with a direction only counts for traffic going that way (±60°), so the one
    /// on the opposite carriageway stays quiet.
    static func along(_ path: RoutePath, hazards: [Hazard]) -> [RouteHazard] {
        guard path.coordinates.count > 1 else { return [] }
        let lats = path.coordinates.map(\.latitude), lons = path.coordinates.map(\.longitude)
        let margin = 0.0005 // ~50 m, cheap box filter before the per-segment work
        let box = (lats.min()! - margin, lats.max()! + margin, lons.min()! - margin, lons.max()! + margin)
        return hazards.compactMap { hazard in
            guard (box.0 ... box.1).contains(hazard.latitude), (box.2 ... box.3).contains(hazard.longitude),
                  let hit = path.project(hazard.coordinate, tolerance: hazard.kind == .bump ? 10 : 20)
            else { return nil }
            if let direction = hazard.direction {
                let difference = abs(direction - hit.course).truncatingRemainder(dividingBy: 360)
                guard min(difference, 360 - difference) <= 60 else { return nil }
            }
            return RouteHazard(hazard: hazard, offset: hit.offset)
        }
        .sorted { $0.offset < $1.offset }
    }
}

/// Warns once per hazard, early enough for the speed: a camera at least 300 m (or 15 s) ahead, a bump at
/// least 80 m (or 6 s). Pure, so the timing is testable without a drive.
struct HazardWatch {
    var hazards: [RouteHazard] = []
    var kinds: Set<Hazard.Kind> = Set(Hazard.Kind.allCases)
    private var announced: Set<Int> = []

    init(hazards: [RouteHazard] = []) {
        self.hazards = hazards
    }

    static func warningDistance(_ kind: Hazard.Kind, speed: Double) -> CLLocationDistance {
        switch kind {
        case .camera: max(300, speed * 15)
        case .bump: max(80, speed * 6)
        }
    }

    /// - Parameters:
    ///   - travelled: metres driven along the route.
    ///   - speed: m/s.
    /// - Returns: the alert to show (nil = none in range) and a sentence the first time it comes in range.
    mutating func update(travelled: CLLocationDistance, speed: Double) -> (alert: HazardAlert?, sentence: String?) {
        // Just passed (5 m) still counts as passed: the next one ahead is the one to show.
        guard let index = hazards.indices.first(where: { hazards[$0].offset > travelled - 5 && kinds.contains(hazards[$0].hazard.kind) })
        else { return (nil, nil) }
        let next = hazards[index]
        let distance = max(0, next.offset - travelled)
        guard distance <= Self.warningDistance(next.hazard.kind, speed: speed) else { return (nil, nil) }
        let alert = HazardAlert(kind: next.hazard.kind, distance: distance, maxspeed: next.hazard.maxspeed)
        guard !announced.contains(index) else { return (alert, nil) }
        announced.insert(index)
        return (alert, Self.sentence(alert))
    }

    static func sentence(_ alert: HazardAlert) -> String {
        let place = alert.distance < 30 ? "" : "\(TurkishInstructions.distancePhrase(alert.distance)) sonra "
        switch alert.kind {
        case .camera:
            let limit = alert.maxspeed.map { ", hız sınırı \($0)" } ?? ""
            return place.isEmpty ? "Hız kamerası\(limit)." : "\(place)hız kamerası\(limit)."
        case .bump:
            return place.isEmpty ? "Kasis." : "\(place)kasis."
        }
    }
}
