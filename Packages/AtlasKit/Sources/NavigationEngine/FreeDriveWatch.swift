import CoreLocation
import Foundation
import RoadHazards

/// Warnings on a drive without a destination, as Yandex's navigator mode gives them: the speed bumps and
/// cameras ahead on the road being driven. There is no route to match them to, so the car's course stands in
/// for it: a hazard counts when it lies ahead along that line and close beside it.
///
/// shortcut: the course is a straight line, so on a bend a hazard of the road ahead can fall outside the
/// corridor until the car is nearly there, and a road running alongside within the corridor can lend it one;
/// upgrade to a path matched on the device's routing tiles if drives show either.
@MainActor
public final class FreeDriveWatch {
    public let voice = VoiceGuide()
    /// The kinds to warn about (the settings' camera and bump switches).
    public var kinds: Set<Hazard.Kind> = Set(Hazard.Kind.allCases)
    /// Off: nothing is said.
    public var isEnabled = true
    /// The driver's own marks, beside the shipped OpenStreetMap hazards.
    public var userHazards: [Hazard] = []

    private let bundled: [Hazard]
    /// Each hazard is said once an hour at most: a drive round the block passes the same bump again.
    private var announced: [Spot: Date] = [:]

    private struct Spot: Hashable {
        let kind: Hazard.Kind
        let latitude: Double
        let longitude: Double

        init(_ hazard: Hazard) {
            kind = hazard.kind
            latitude = hazard.latitude
            longitude = hazard.longitude
        }
    }

    public init(hazards: [Hazard] = HazardCatalog.bundled()?.hazards ?? []) {
        bundled = hazards
    }

    /// One GPS fix of a drive without guidance; says the hazard it brings in range, if any.
    public func ingest(_ fix: CLLocation) {
        guard isEnabled, !kinds.isEmpty, let sentence = update(fix) else { return }
        voice.speak(sentence)
    }

    /// The sentence for this fix, if a hazard not said lately has come in range.
    func update(_ fix: CLLocation) -> String? {
        // A course is only worth something when moving and placed: standing at a light it points anywhere.
        guard fix.speed >= Self.minimumSpeed, fix.course >= 0, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 30
        else { return nil }
        let candidates = (bundled + userHazards).filter { kinds.contains($0.kind) }
        guard let ahead = Self.ahead(of: fix.coordinate, course: fix.course, speed: fix.speed, hazards: candidates)
        else { return nil }
        let spot = Spot(ahead.hazard)
        if let said = announced[spot], fix.timestamp.timeIntervalSince(said) < 3600 { return nil }
        // A run of bumps (or a camera mapped twice) is one warning: its neighbours count as said with it.
        for hazard in candidates where hazard.kind == ahead.hazard.kind && Self.metres(hazard.coordinate, ahead.hazard.coordinate) <= 60 {
            announced[Spot(hazard)] = fix.timestamp
        }
        return HazardWatch.sentence(HazardAlert(kind: ahead.hazard.kind, distance: ahead.distance, maxspeed: ahead.hazard.maxspeed))
    }

    /// 18 km/h.
    static let minimumSpeed: CLLocationSpeed = 5

    /// The nearest hazard ahead on the course, in warning range for the speed (HazardWatch's distances).
    /// Ahead: more than 15 m along the course (the one under the car is being passed). Beside the line: a bump
    /// within 10 m of it, a camera, often mapped at the roadside, within 15 m; both 5 m more for every 100 m
    /// ahead, for the GPS course's error and the road's curve. A camera that looks the way the car drives
    /// watches the other carriageway (RouteHazards.along).
    static func ahead(
        of position: CLLocationCoordinate2D, course: CLLocationDirection, speed: CLLocationSpeed, hazards: [Hazard]
    ) -> (hazard: Hazard, distance: CLLocationDistance)? {
        let metresPerLon = 111_320 * cos(position.latitude * .pi / 180), metresPerLat = 110_540.0
        let heading = course * .pi / 180
        // The direction of travel as a unit vector (east, north).
        let forward = (east: sin(heading), north: cos(heading))
        var best: (hazard: Hazard, distance: CLLocationDistance)?
        for hazard in hazards {
            let east = (hazard.longitude - position.longitude) * metresPerLon
            let north = (hazard.latitude - position.latitude) * metresPerLat
            // A cheap box first: nothing further than the longest warning distance is looked at closely.
            guard abs(east) < 700, abs(north) < 700 else { continue }
            let along = east * forward.east + north * forward.north
            let beside = abs(east * forward.north - north * forward.east)
            guard along > 15, along <= HazardWatch.warningDistance(hazard.kind, speed: speed) else { continue }
            let corridor = (hazard.kind == .bump ? 10 : 15) + along * 0.05
            guard beside <= corridor else { continue }
            if hazard.kind == .camera, let direction = hazard.direction {
                let difference = abs(direction - course).truncatingRemainder(dividingBy: 360)
                guard min(difference, 360 - difference) > 60 else { continue }
            }
            if let current = best, current.distance <= along { continue }
            best = (hazard, along)
        }
        return best
    }

    private static func metres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> CLLocationDistance {
        let dx = (b.longitude - a.longitude) * 111_320 * cos(a.latitude * .pi / 180)
        let dy = (b.latitude - a.latitude) * 110_540
        return (dx * dx + dy * dy).squareRoot()
    }
}
