import CoreLocation
import Foundation
import RoadHazards
import Testing
@testable import NavigationEngine

@MainActor
struct FreeDriveWatchTests {
    private let base = CLLocationCoordinate2D(latitude: 40.8890, longitude: 29.1900)
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A point `east` and `north` metres from `base`.
    private func point(east: Double, north: Double = 0) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: base.latitude + north / 110_540,
            longitude: base.longitude + east / (111_320 * cos(base.latitude * .pi / 180))
        )
    }

    /// Driving east at 50 km/h, `east` metres from `base`, `seconds` into the drive.
    private func fix(east: Double = 0, speed: Double = 13.9, course: Double = 90, seconds: Double = 0) -> CLLocation {
        CLLocation(
            coordinate: point(east: east), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            course: course, speed: speed, timestamp: start.addingTimeInterval(seconds)
        )
    }

    private func bump(east: Double, north: Double = 0) -> Hazard {
        let at = point(east: east, north: north)
        return Hazard(kind: .bump, latitude: at.latitude, longitude: at.longitude)
    }

    @Test func aBumpAheadIsSaidOnce() {
        let watch = FreeDriveWatch(hazards: [bump(east: 70)])
        #expect(watch.update(fix()) == "70 metre sonra kasis.")
        // A second later, nearer: already said.
        #expect(watch.update(fix(east: 14, seconds: 1)) == nil)
    }

    @Test func onlyTheRoadAheadCounts() {
        // On a road alongside (30 m off the course), behind the car, and not yet in range (84 m at 50 km/h).
        let watch = FreeDriveWatch(hazards: [bump(east: 70, north: 30), bump(east: -70), bump(east: 120)])
        #expect(watch.update(fix()) == nil)
        // Standing or crawling: the course says nothing.
        let slow = FreeDriveWatch(hazards: [bump(east: 70)])
        #expect(slow.update(fix(speed: 3)) == nil)
        #expect(slow.update(fix(course: -1)) == nil)
    }

    @Test func aCameraFacingTheCarIsSaidWithItsLimit() {
        let at = point(east: 250)
        let facing = Hazard(kind: .camera, latitude: at.latitude, longitude: at.longitude, maxspeed: 50, direction: 270)
        #expect(FreeDriveWatch(hazards: [facing]).update(fix()) == "250 metre sonra hız kamerası, hız sınırı 50.")
        // One looking the way the car drives watches the other carriageway.
        let away = Hazard(kind: .camera, latitude: at.latitude, longitude: at.longitude, maxspeed: 50, direction: 90)
        #expect(FreeDriveWatch(hazards: [away]).update(fix()) == nil)
    }

    @Test func aRunOfBumpsIsOneWarning() {
        let watch = FreeDriveWatch(hazards: [bump(east: 70), bump(east: 110)])
        #expect(watch.update(fix()) == "70 metre sonra kasis.")
        // The second bump of the run comes in range: it was said with the first.
        #expect(watch.update(fix(east: 40, seconds: 3)) == nil)
    }

    @Test func switchedOffKindsAreNotSaid() {
        let watch = FreeDriveWatch(hazards: [bump(east: 70)])
        watch.kinds = [.camera]
        watch.userHazards = []
        #expect(watch.update(fix()) == nil)
        // The driver's own marks count like the shipped ones.
        let marked = FreeDriveWatch(hazards: [])
        marked.userHazards = [bump(east: 60)]
        #expect(marked.update(fix()) == "60 metre sonra kasis.")
    }
}
