import CoreLocation
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

    /// A margin of the driver's own replaces the rule: 10 km/h over a 50 is 60, so 59 stays quiet.
    @Test func theDriversMarginIsTheLine() {
        var watch = SpeedingWatch()
        watch.margin = 10
        for second in 0 ... 5 { #expect(watch.update(speedKmh: 59, limit: 50, at: at(Double(second))) == nil) }
        #expect(watch.update(speedKmh: 61, limit: 50, at: at(10)) == nil)
        #expect(watch.update(speedKmh: 61, limit: 50, at: at(13)) == "Hız sınırı 50.")
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

/// The traffic provider's speed limits, placed along the route.
struct RouteLimitsTests {
    // East along a street from Kartal, a point every 0.001° (about 84 m), 842 m long.
    private let path = RoutePath((0 ... 10).map { CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2 + Double($0) * 0.001) })

    /// A stretch starting at `longitude` on the street, or `north` metres beside it.
    private func stretch(_ longitude: Double, north: Double = 0, length: Double, kmh: Int) -> RouteSpeedLimit {
        RouteSpeedLimit(
            start: CLLocationCoordinate2D(latitude: 40.9 + north / 110_540, longitude: longitude), length: length, kmh: kmh
        )
    }

    /// The limit at each of `places`, metres along the route.
    private func found(_ limits: RouteLimits, at places: [Double]) -> [Int?] {
        places.map { limits.limit(at: $0) }
    }

    @Test func theLimitIsThatOfTheStretchTheCarIsOn() {
        // The provider's line lies a few metres beside the route's (5 m here). The second stretch starts at the
        // fourth point, about 252 m along, and is 400 m long.
        let limits = RouteLimits([stretch(29.2, north: 5, length: 250, kmh: 50), stretch(29.203, north: 5, length: 400, kmh: 30)], on: path)
        #expect(limits.marks.count == 2)
        #expect(abs(limits.marks[1].from - path.offsets[3]) < 1)
        #expect(found(limits, at: [0, 100, 240]) == [50, 50, 50])
        #expect(found(limits, at: [260, 600]) == [30, 30])
        // A little past its length it still holds (the two sources measure a road a few metres apart); then no
        // limit is known, and none is shown.
        #expect(limits.limit(at: 670) == 30)
        #expect(limits.limit(at: 700) == nil)
    }

    /// The provider's lengths are not added up: its line can lack a part (no limit there, or no match).
    @Test func aStretchLiesWhereItsStartMeetsTheRoute() {
        // 100 m at 50, then nothing known, then 100 m at 70 from the seventh point (about 505 m along).
        let limits = RouteLimits([stretch(29.2, length: 100, kmh: 50), stretch(29.206, length: 100, kmh: 70)], on: path)
        #expect(found(limits, at: [50, 120]) == [50, 50])
        #expect(found(limits, at: [300, 500]) == [nil, nil])
        #expect(found(limits, at: [510, 620]) == [70, 70])
        #expect(limits.limit(at: 650) == nil)
    }

    /// After a reroute the stretches are placed on the new route: those on roads it no longer takes go.
    @Test func aStretchOffTheRouteIsDroppedAndTheRestStay() {
        let limits = RouteLimits([stretch(29.201, north: 200, length: 300, kmh: 90), stretch(29.204, length: 200, kmh: 50)], on: path)
        #expect(limits.marks.count == 1)
        #expect(found(limits, at: [100, 350, 560]) == [nil, 50, 50])
        #expect(limits.limit(at: 580) == nil)
        // The first stretch placed (it begins about 337 m along) already holds a few metres before its start.
        #expect(found(limits, at: [300, 320]) == [nil, 50])
        // Nothing is placed behind where the car is.
        #expect(RouteLimits([stretch(29.201, length: 300, kmh: 50)], on: path, from: 500).marks.isEmpty)
        #expect(RouteLimits().limit(at: 100) == nil)
    }

    /// East along a dual carriageway, a U-turn, and back on the other side 12 m to the north.
    @Test func aRoadTakenTwiceMatchesThePassBeingDriven() {
        let north = 40.9 + 12 / 110_540.0
        let there = (0 ... 5).map { CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2 + Double($0) * 0.001) }
        let back = (0 ... 5).map { CLLocationCoordinate2D(latitude: north, longitude: 29.205 - Double($0) * 0.001) }
        let loop = RoutePath(there + back)
        // The third stretch starts 4 m from the first carriageway and 8 m from the second: on its own it would
        // go to the first pass, but it follows a stretch of the way back.
        let between = CLLocationCoordinate2D(latitude: 40.9 + 4 / 110_540.0, longitude: 29.202)
        #expect(abs((loop.project(between, tolerance: 30)?.offset ?? 0) - loop.offsets[2]) < 1)
        let limits = RouteLimits([
            RouteSpeedLimit(start: there[1], length: 300, kmh: 50),
            RouteSpeedLimit(start: back[1], length: 100, kmh: 30),
            RouteSpeedLimit(start: between, length: 100, kmh: 70),
        ], on: loop)
        #expect(limits.marks.count == 3)
        #expect(abs(limits.marks[0].from - loop.offsets[1]) < 1)
        #expect(abs(limits.marks[1].from - loop.offsets[7]) < 1)
        #expect(abs(limits.marks[2].from - loop.offsets[9]) < 1)
    }
}
