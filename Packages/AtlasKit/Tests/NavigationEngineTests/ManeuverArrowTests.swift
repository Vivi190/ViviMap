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
        #expect(ManeuverArrow.reach(type: .roundabout, nextStep: 60) == 75)
        #expect(ManeuverArrow.reach(type: .turn, nextStep: 400) == 15)
    }
}

struct TrafficStripTests {
    /// 1 km due north; 200 m already driven, 800 m to go.
    private func at(_ metres: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: 40.9 + metres / 110_540, longitude: 29.2)
    }

    @Test func stretchesLandWhereTheyLieOnWhatIsLeft() throws {
        let path = RoutePath([at(0), at(1_000)])
        // In the path's own (geodesic) metres, as the session passes them: "1 km" here is ~1 004.6 m of it.
        let ranges = NavigationSession.fractions(
            of: [[at(400), at(600)], [at(50), at(150)], [CLLocationCoordinate2D(latitude: 40.95, longitude: 29.3)]],
            on: path, travelled: path.length * 0.2, remaining: path.length * 0.8
        )
        let ahead = try #require(ranges[0])
        #expect(abs(ahead.lowerBound - 0.25) < 0.001 && abs(ahead.upperBound - 0.5) < 0.001)
        #expect(ranges[1] == nil) // behind
        #expect(ranges[2] == nil) // off the route
    }
}
