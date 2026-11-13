import Testing
@testable import NavigationEngine

struct GuidanceZoomTests {
    private func level(kmh: Double, turnIn distance: Double? = 1000, current: Double? = nil) -> Double {
        GuidanceZoom.level(speed: kmh / 3.6, distanceToManeuver: distance, current: current)
    }

    @Test func fasterIsFurtherOut() {
        #expect(level(kmh: 90) == 15.5) // D-100 / TEM
        #expect(level(kmh: 70) == 16.3)
        #expect(level(kmh: 40) == 17.0)
        #expect(level(kmh: 18) == 17.6)
    }

    @Test func aTurnCloseByPullsIn() {
        #expect(level(kmh: 90, turnIn: 120) == 17.6)
    }

    @Test func smallSpeedChangesDoNotMoveTheCamera() {
        #expect(level(kmh: 58, current: 17.0) == 17.0) // just over 55: stays
        #expect(level(kmh: 61, current: 17.0) == 16.3) // clearly over: steps out
        #expect(level(kmh: 52, current: 16.3) == 16.3)
        #expect(level(kmh: 49, current: 16.3) == 17.0)
    }
}
