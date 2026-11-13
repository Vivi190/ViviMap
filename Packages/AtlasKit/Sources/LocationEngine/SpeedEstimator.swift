import Foundation

/// Turns raw GPS (Doppler) speed into a steady speedometer reading.
///
/// CoreLocation speed is already filtered, so smoothing stays light (~0.6 s) to avoid visible lag.
/// A start/stop hysteresis removes the jitter while standing still, and a reading goes stale after a GPS gap
/// (tunnels) instead of freezing on the last value.
public struct SpeedEstimator: Sendable {
    public struct Reading: Equatable, Sendable {
        /// Display speed in km/h; nil when there is no usable measurement.
        public var kmh: Int?
        /// False when the receiver reports poor or unknown speed accuracy.
        public var isReliable: Bool

        public init(kmh: Int?, isReliable: Bool) {
            self.kmh = kmh
            self.isReliable = isReliable
        }

        public static let unavailable = Reading(kmh: nil, isReliable: false)
    }

    static let startMoving = 1.4 // m/s ≈ 5 km/h
    static let stopMoving = 0.7 // m/s ≈ 2.5 km/h
    static let staleAfter: TimeInterval = 4
    static let tau: TimeInterval = 0.6
    static let tauUnreliable: TimeInterval = 1.5

    private var smoothed: Double?
    private var lastSample: Date?
    private var isMoving = false
    private var lastReliable = false

    public init() {}

    /// - Parameters:
    ///   - speed: `CLLocation.speed` in m/s; negative means invalid.
    ///   - speedAccuracy: `CLLocation.speedAccuracy` in m/s; negative means unknown.
    public mutating func update(speed: Double, speedAccuracy: Double, at timestamp: Date) -> Reading {
        guard speed >= 0 else {
            // This fix carries no speed: keep the last value until it goes stale.
            return reading(at: timestamp)
        }
        let reliable = speedAccuracy >= 0 && speedAccuracy <= max(1.0, speed * 0.2)
        if let previous = smoothed, let last = lastSample {
            let dt = min(max(timestamp.timeIntervalSince(last), 0.05), 5)
            let alpha = 1 - exp(-dt / (reliable ? Self.tau : Self.tauUnreliable))
            smoothed = previous + alpha * (speed - previous)
        } else {
            smoothed = speed
        }
        lastSample = timestamp
        lastReliable = reliable
        if let current = smoothed {
            if isMoving, current < Self.stopMoving {
                isMoving = false
            } else if !isMoving, current > Self.startMoving {
                isMoving = true
            }
        }
        return reading(at: timestamp)
    }

    public func reading(at now: Date) -> Reading {
        guard let smoothed, let lastSample, now.timeIntervalSince(lastSample) <= Self.staleAfter else {
            return .unavailable
        }
        return Reading(kmh: isMoving ? Int((smoothed * 3.6).rounded()) : 0, isReliable: lastReliable)
    }
}
