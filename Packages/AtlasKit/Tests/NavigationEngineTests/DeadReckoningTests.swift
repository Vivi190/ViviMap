import Testing
@testable import NavigationEngine

struct DeadReckoningTests {
    @Test func movesOnAtTheLastSpeedOnceTheSignalIsGone() {
        // 20 m/s (72 km/h), 1 km before the next turn: after 5 s without a fix, 100 m on.
        #expect(DeadReckoning.offset(from: 2_000, speed: 20, elapsed: 5, maneuver: 3_000, length: 9_000) == 2_100)
        // A gap of a second or two is the GPS's usual rhythm.
        #expect(DeadReckoning.offset(from: 2_000, speed: 20, elapsed: 2, maneuver: 3_000, length: 9_000) == nil)
    }

    @Test func stopsShortOfTheNextManeuver() {
        // 60 s at 20 m/s would be 1.2 km: it waits 40 m before the turn instead.
        #expect(DeadReckoning.offset(from: 2_000, speed: 20, elapsed: 60, maneuver: 3_000, length: 9_000) == 2_960)
        // And before the end of the route.
        #expect(DeadReckoning.offset(from: 8_900, speed: 20, elapsed: 10, maneuver: 9_500, length: 9_000) == 8_960)
        // Already that near: nothing to move.
        #expect(DeadReckoning.offset(from: 2_970, speed: 20, elapsed: 5, maneuver: 3_000, length: 9_000) == nil)
    }

    @Test func noGuessForASlowCarOrALongSilence() {
        // Crawling in a queue (3 m/s): it may well be standing.
        #expect(DeadReckoning.offset(from: 2_000, speed: 3, elapsed: 10, maneuver: 3_000, length: 9_000) == nil)
        // Two minutes on, a guess is worth less than the car standing still on the map.
        #expect(DeadReckoning.offset(from: 2_000, speed: 20, elapsed: 121, maneuver: 9_000, length: 9_000) == nil)
    }
}
