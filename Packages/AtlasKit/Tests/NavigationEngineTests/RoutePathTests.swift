import CoreLocation
import Testing
@testable import NavigationEngine

struct RoutePathTests {
    private let start = CLLocationCoordinate2D(latitude: 40.0, longitude: 29.0)
    // ~85 m east, then ~111 m north.
    private let corner = CLLocationCoordinate2D(latitude: 40.0, longitude: 29.001)
    private let end = CLLocationCoordinate2D(latitude: 40.001, longitude: 29.001)

    @Test func interpolatesAlongTheLine() {
        let path = RoutePath([start, corner, end])
        let firstLeg = path.offsets[1]
        #expect(abs(firstLeg - 85.2) < 1)
        let middle = path.point(at: firstLeg / 2)
        #expect(abs(middle.coordinate.longitude - 29.0005) < 1e-6)
        #expect(abs(middle.coordinate.latitude - 40.0) < 1e-9)
    }

    @Test func courseFollowsTheSegmentBeingDriven() {
        let path = RoutePath([start, corner, end])
        #expect(abs(path.point(at: 10).course - 90) < 0.1) // east
        #expect(path.point(at: path.offsets[1] + 10).course < 0.1) // north
        // Exactly on the corner: already heading into the next segment.
        #expect(path.point(at: path.offsets[1]).course < 0.1)
    }

    @Test func clampsToTheEnds() {
        let path = RoutePath([start, corner, end])
        let before = path.point(at: -50).coordinate
        let after = path.point(at: path.length + 500).coordinate
        #expect(before.latitude == start.latitude && before.longitude == start.longitude)
        #expect(abs(after.latitude - end.latitude) < 1e-9 && abs(after.longitude - end.longitude) < 1e-9)
    }

    @Test func duplicatePointsDoNotTurnTheCourseNorth() {
        let path = RoutePath([start, start, corner])
        #expect(abs(path.point(at: 0).course - 90) < 0.1)
    }

    @Test func fixCarriesSpeedAndCourse() {
        let fix = RoutePath([start, corner]).fix(at: 20, speed: 12, timestamp: .now)
        #expect(fix.speed == 12)
        #expect(abs(fix.course - 90) < 0.1)
        #expect(fix.horizontalAccuracy == 5)
    }

    @Test func remainderStartsWhereTheDriverIs() {
        let path = RoutePath([start, corner, end])
        let rest = path.remainder(after: 40)
        #expect(rest.count == 3)
        #expect(abs(rest[0].longitude - (29.0 + 0.001 * 40 / path.offsets[1])) < 1e-9)
        #expect(rest[1].longitude == corner.longitude && rest[2].latitude == end.latitude)
        // Past the corner only the last leg is left.
        #expect(path.remainder(after: path.offsets[1] + 10).count == 2)
    }

    @Test func degenerateInputs() {
        #expect(RoutePath([]).length == 0)
        #expect(RoutePath([start]).length == 0)
        #expect(RoutePath([start]).point(at: 10).coordinate.latitude == start.latitude)
    }
}
