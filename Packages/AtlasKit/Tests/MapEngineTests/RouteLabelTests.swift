import CoreLocation
import Testing
@testable import MapEngine

struct RouteLabelTests {
    /// Metres east and north of a point in Kartal.
    private func at(_ east: Double, _ north: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: 40.9 + north / 110_540,
            longitude: 29.2 + east / (111_320 * cos(40.9 * .pi / 180))
        )
    }

    private func same(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D) -> Bool {
        guard let a else { return false }
        return abs(a.latitude - b.latitude) < 1e-9 && abs(a.longitude - b.longitude) < 1e-9
    }

    /// Straight north 2 km, and a detour bulging 1 km east between the same ends.
    private var straight: [CLLocationCoordinate2D] { [at(0, 0), at(0, 500), at(0, 1_000), at(0, 1_500), at(0, 2_000)] }
    private var detour: [CLLocationCoordinate2D] { [at(0, 0), at(600, 500), at(1_000, 1_000), at(600, 1_500), at(0, 2_000)] }

    @Test func eachBubbleSitsWhereOnlyItsRouteGoes() {
        #expect(same(RouteLabel.place(on: detour, awayFrom: [straight]), at(1_000, 1_000)))
        #expect(same(RouteLabel.place(on: straight, awayFrom: [detour]), at(0, 1_000)))
    }

    @Test func aLoneRouteGetsItsMiddle() {
        #expect(same(RouteLabel.place(on: straight, awayFrom: []), at(0, 1_000)))
        #expect(RouteLabel.place(on: [], awayFrom: [straight]) == nil)
    }

    @Test func samplingKeepsBothEnds() {
        let line = (0..<1_000).map { at(0, Double($0)) }
        let points = RouteLabel.sample(line, to: 80)
        #expect(points.count <= 81)
        #expect(same(points.first, line[0]) && same(points.last, line[999]))
    }

    @Test func longerTimesGetWiderBubbles() {
        let short = RouteLabel.bubble("9 dk", selected: true, night: false)
        let long = RouteLabel.bubble("1 sa 25 dk", selected: false, night: true)
        #expect(long.size.width > short.size.width)
        #expect(long.size.height == short.size.height)
    }
}
