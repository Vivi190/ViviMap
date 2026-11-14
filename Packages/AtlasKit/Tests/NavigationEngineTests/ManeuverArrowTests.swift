import CoreLocation
@preconcurrency import FerrostarCoreFFI
import Testing
@testable import NavigationEngine

struct ManeuverArrowTests {
    /// 100 m north, then 100 m east: a right turn 100 m from the start.
    private let path: RoutePath = {
        let start = CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2)
        let corner = CLLocationCoordinate2D(latitude: 40.9 + 100 / 110_540, longitude: 29.2)
        let end = CLLocationCoordinate2D(latitude: corner.latitude, longitude: 29.2 + 100 / (111_320 * cos(40.9 * .pi / 180)))
        return RoutePath([start, corner, end])
    }()

    @Test func runsIntoTheTurnAndOutWithAHeadPointingOn() throws {
        let lines = ManeuverArrow.lines(along: path, maneuverAt: 100, after: 15)
        try #require(lines.count == 2)
        let shaft = lines[0], head = lines[1]
        let end = try #require(shaft.last)
        let first = try #require(path.project(shaft[0], tolerance: 1))
        let last = try #require(path.project(end, tolerance: 1))
        #expect(abs(first.offset - 70) < 1) // 30 m before the turn
        #expect(abs(last.offset - 115) < 1) // 15 m past it
        let corner = path.coordinates[1]
        #expect(shaft.contains { $0.latitude == corner.latitude && $0.longitude == corner.longitude })
        // The head trails back west of its tip, one wing on each side of the road.
        try #require(head.count == 3)
        let tip = head[1]
        #expect(head[0].longitude < tip.longitude && head[2].longitude < tip.longitude)
        #expect((head[0].latitude - tip.latitude) * (head[2].latitude - tip.latitude) < 0)
    }

    @Test func onlyWhereTheDirectionChanges() {
        #expect(ManeuverArrow.wanted(type: .turn, modifier: .left))
        #expect(ManeuverArrow.wanted(type: .roundabout, modifier: nil))
        #expect(!ManeuverArrow.wanted(type: .continue, modifier: .straight))
        #expect(!ManeuverArrow.wanted(type: .arrive, modifier: .right))
    }

    @Test func throughARoundaboutToItsExit() {
        #expect(ManeuverArrow.reach(type: .roundabout, nextStep: 60) == 65)
        #expect(ManeuverArrow.reach(type: .turn, nextStep: 400) == 15)
    }
}
