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
    /// (20 m). A camera's mapped direction is where it looks, so it faces the traffic it watches: in the
    /// bundled data (2026-11-14) 21 pairs of cameras stand 4 to 40 m apart looking opposite ways, and 39 of
    /// those 42 look against the traffic of their own carriageway, none along it. So only a camera looking
    /// the way the car drives (±60°) is left out: it watches the opposite carriageway. One with no mapped
    /// direction is kept.
    ///
    /// Hazards of one kind within 50 m of each other (a run of bumps, a camera mapped twice) count once.
    static func along(_ path: RoutePath, hazards: [Hazard]) -> [RouteHazard] {
        guard path.coordinates.count > 1 else { return [] }
        let lats = path.coordinates.map(\.latitude), lons = path.coordinates.map(\.longitude)
        let margin = 0.0005 // ~50 m, cheap box filter before the per-segment work
        let box = (lats.min()! - margin, lats.max()! + margin, lons.min()! - margin, lons.max()! + margin)
        let passed: [RouteHazard] = hazards.compactMap { hazard -> RouteHazard? in
            guard (box.0 ... box.1).contains(hazard.latitude), (box.2 ... box.3).contains(hazard.longitude),
                  let hit = path.project(hazard.coordinate, tolerance: hazard.kind == .bump ? 10 : 20)
            else { return nil }
            if let direction = hazard.direction {
                let difference = abs(direction - hit.course).truncatingRemainder(dividingBy: 360)
                guard min(difference, 360 - difference) > 60 else { return nil }
            }
            return RouteHazard(hazard: hazard, offset: hit.offset)
        }
        .sorted { $0.offset < $1.offset }
        var merged: [RouteHazard] = []
        var previous: [Hazard.Kind: CLLocationDistance] = [:]
        for item in passed {
            // Measured from the neighbour before it, kept or not: bumps 40 m apart all the way are one warning.
            let last = previous[item.hazard.kind]
            previous[item.hazard.kind] = item.offset
            if let last, item.offset - last <= 50 { continue }
            merged.append(item)
        }
        return merged
    }
}

/// Warns once per hazard, early enough for the speed: a camera at least 300 m (or 15 s) ahead, a bump at
/// least 80 m (or 6 s). Pure, so the timing is testable without a drive.
struct HazardWatch {
    /// Replaced when the route changes; what has been announced is kept.
    var hazards: [RouteHazard] = []
    var kinds: Set<Hazard.Kind> = Set(Hazard.Kind.allCases)
    /// By place rather than by position in `hazards`, so a camera already announced is not announced again
    /// from the start of a new route.
    private var announced: Set<Spot> = []

    private struct Spot: Hashable {
        let kind: Hazard.Kind
        let latitude: Double
        let longitude: Double
    }

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
    /// - Returns: the alert to show (nil = none in range; the nearer one when a camera and a bump both are)
    ///   and a sentence the first time a hazard comes in range.
    mutating func update(travelled: CLLocationDistance, speed: Double) -> (alert: HazardAlert?, sentence: String?) {
        var alert: HazardAlert?
        var sentence: String?
        // The next one of each kind: looking only at the nearest hazard, a bump 50 m before a camera kept the
        // camera (in range from 300 m) unannounced until the bump was passed.
        for kind in Hazard.Kind.allCases where kinds.contains(kind) {
            // Just passed (5 m) still counts as passed: the next one ahead is the one to show.
            guard let next = hazards.first(where: { $0.hazard.kind == kind && $0.offset > travelled - 5 }) else { continue }
            let distance = max(0, next.offset - travelled)
            guard distance <= Self.warningDistance(kind, speed: speed) else { continue }
            let candidate = HazardAlert(kind: kind, distance: distance, maxspeed: next.hazard.maxspeed)
            let spot = Spot(kind: kind, latitude: next.hazard.latitude, longitude: next.hazard.longitude)
            // One sentence per update: a second kind coming in range on the same fix is said on the next one.
            if sentence == nil, !announced.contains(spot) {
                announced.insert(spot)
                sentence = Self.sentence(candidate)
            }
            if let shown = alert, shown.distance <= distance { continue }
            alert = candidate
        }
        return (alert, sentence)
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
