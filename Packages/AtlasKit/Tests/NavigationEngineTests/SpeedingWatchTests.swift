import Foundation
import Testing
@testable import NavigationEngine

struct SpeedingWatchTests {
    private let start = Date(timeIntervalSince1970: 1_794_000_000)

    private func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    @Test func aFewKilometresOverIsNotWorthAWord() {
        var watch = SpeedingWatch()
        // 50 + max(6, 5) = 56 is the line; 55 stays quiet however long.
        for second in 0 ... 10 { #expect(watch.update(speedKmh: 55, limit: 50, at: at(Double(second))) == nil) }
    }

    @Test func clearlyOverForThreeSecondsWarnsOnce() {
        var watch = SpeedingWatch()
        #expect(watch.update(speedKmh: 62, limit: 50, at: at(0)) == nil)
        #expect(watch.update(speedKmh: 62, limit: 50, at: at(2)) == nil)
        #expect(watch.update(speedKmh: 62, limit: 50, at: at(3)) == "Hız sınırı 50.")
        #expect(watch.update(speedKmh: 62, limit: 50, at: at(30)) == nil)
        // Still over a minute later: once more.
        #expect(watch.update(speedKmh: 62, limit: 50, at: at(63)) == "Hız sınırı 50.")
    }

    @Test func overtakingAndSlowingDownStartOver() {
        var watch = SpeedingWatch()
        #expect(watch.update(speedKmh: 70, limit: 50, at: at(0)) == nil)
        #expect(watch.update(speedKmh: 48, limit: 50, at: at(2)) == nil)
        #expect(watch.update(speedKmh: 70, limit: 50, at: at(4)) == nil) // the 3 s count started again at 4
        #expect(watch.update(speedKmh: 70, limit: 50, at: at(7)) == "Hız sınırı 50.")
    }

    @Test func noSignOrSwitchedOffMeansSilence() {
        var unsigned = SpeedingWatch()
        #expect(unsigned.update(speedKmh: 140, limit: nil, at: at(0)) == nil)
        #expect(unsigned.update(speedKmh: 140, limit: nil, at: at(10)) == nil)
        var off = SpeedingWatch()
        off.isEnabled = false
        #expect(off.update(speedKmh: 140, limit: 50, at: at(0)) == nil)
        #expect(off.update(speedKmh: 140, limit: 50, at: at(10)) == nil)
    }

    @Test func motorwayToleranceIsTenPercent() {
        var watch = SpeedingWatch()
        // 120 + 12 = 132: 131 is fine, 135 for three seconds is not.
        #expect(watch.update(speedKmh: 131, limit: 120, at: at(0)) == nil)
        #expect(watch.update(speedKmh: 131, limit: 120, at: at(5)) == nil)
        #expect(watch.update(speedKmh: 135, limit: 120, at: at(6)) == nil)
        #expect(watch.update(speedKmh: 135, limit: 120, at: at(9)) == "Hız sınırı 120.")
    }
}
