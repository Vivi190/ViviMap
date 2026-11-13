import Foundation
import Testing
@testable import TripHistory

@MainActor
struct TripLogTests {
    private func log() -> TripLog {
        TripLog(defaults: UserDefaults(suiteName: "atlas.test.\(UUID())")!)
    }

    private func trip(minutes predicted: Double, took actual: Double, traffic: Bool = true, arrived: Bool = true) -> Trip {
        let start = Date(timeIntervalSince1970: 1_794_000_000)
        return Trip(
            startedAt: start, endedAt: start.addingTimeInterval(actual * 60), destination: "Kartal", distance: 6200,
            predicted: predicted * 60, predictedWithTraffic: traffic, arrived: arrived
        )
    }

    @Test func keepsNewestFirstAndSkipsMistakenStarts() {
        let log = log()
        log.record(trip(minutes: 16, took: 19))
        log.record(trip(minutes: 10, took: 0.5)) // under a minute
        log.record(trip(minutes: 20, took: 22))
        #expect(log.trips.map(\.predicted) == [20 * 60, 16 * 60])
    }

    @Test func persists() {
        let defaults = UserDefaults(suiteName: "atlas.test.\(UUID())")!
        TripLog(defaults: defaults).record(trip(minutes: 16, took: 19))
        #expect(TripLog(defaults: defaults).trips.count == 1)
    }

    @Test func calibrationIsTheMedianOfRealDrives() {
        let log = log()
        log.record(trip(minutes: 20, took: 22)) // 1.10
        log.record(trip(minutes: 10, took: 12)) // 1.20
        #expect(log.calibration(withTraffic: true) == nil) // too few yet
        log.record(trip(minutes: 30, took: 30)) // 1.00
        log.record(trip(minutes: 4, took: 9)) // too short to count
        log.record(trip(minutes: 20, took: 40, arrived: false)) // ended on the way
        log.record(trip(minutes: 20, took: 30, traffic: false)) // other kind of estimate
        let result = log.calibration(withTraffic: true)
        #expect(result?.drives == 3)
        #expect(abs((result?.ratio ?? 0) - 1.10) < 1e-9)
    }
}
