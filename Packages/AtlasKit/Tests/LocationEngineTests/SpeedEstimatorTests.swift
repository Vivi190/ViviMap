import Foundation
import Testing
@testable import LocationEngine

struct SpeedEstimatorTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Feeds one sample per second and returns the last reading.
    private func feed(_ estimator: inout SpeedEstimator, _ speeds: [Double], accuracy: Double = 0.3,
                      startAt offset: TimeInterval = 0) -> SpeedEstimator.Reading {
        var reading = SpeedEstimator.Reading.unavailable
        for (index, speed) in speeds.enumerated() {
            reading = estimator.update(speed: speed, speedAccuracy: accuracy,
                                       at: t0.addingTimeInterval(offset + Double(index)))
        }
        return reading
    }

    @Test func standingStillJitterShowsZero() {
        var estimator = SpeedEstimator()
        for speed in [0.3, 0.9, 0.5, 1.1, 0.2, 1.2] {
            let reading = estimator.update(speed: speed, speedAccuracy: 0.4, at: t0)
            #expect(reading.kmh == 0)
        }
    }

    @Test func convergesToSteadySpeed() {
        var estimator = SpeedEstimator()
        let reading = feed(&estimator, Array(repeating: 13.89, count: 6)) // 50 km/h
        #expect(reading.kmh == 50)
        #expect(reading.isReliable)
    }

    @Test func hysteresisKeepsSlowCrawlVisibleUntilStopThreshold() {
        var estimator = SpeedEstimator()
        _ = feed(&estimator, [2.0, 2.0, 2.0])
        let crawling = feed(&estimator, Array(repeating: 1.0, count: 6), startAt: 3) // above stop threshold
        #expect(crawling.kmh == 4)
        let stopped = feed(&estimator, Array(repeating: 0.2, count: 6), startAt: 9)
        #expect(stopped.kmh == 0)
    }

    @Test func invalidSpeedHoldsThenGoesStale() {
        var estimator = SpeedEstimator()
        _ = feed(&estimator, Array(repeating: 10, count: 5))
        let held = estimator.update(speed: -1, speedAccuracy: -1, at: t0.addingTimeInterval(6))
        #expect(held.kmh == 36)
        #expect(estimator.reading(at: t0.addingTimeInterval(4 + 4.5)) == .unavailable)
    }

    @Test func poorOrUnknownAccuracyIsMarkedUnreliable() {
        var estimator = SpeedEstimator()
        #expect(feed(&estimator, [10, 10, 10], accuracy: 3).isReliable == false)
        var unknown = SpeedEstimator()
        #expect(feed(&unknown, [10, 10, 10], accuracy: -1).isReliable == false)
        var good = SpeedEstimator()
        #expect(feed(&good, [10, 10, 10], accuracy: 0.5).isReliable)
    }
}
