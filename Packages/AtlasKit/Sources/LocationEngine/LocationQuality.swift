import CoreLocation

/// How much the current fix can be trusted. Drives the GPS status chip; thresholds are first guesses to be
/// calibrated with real drives in Istanbul (Phase 8).
public enum LocationQuality: Equatable, Sendable {
    case good, fair, poor, unavailable

    /// - Parameters:
    ///   - horizontalAccuracy: radius in metres; negative means invalid.
    ///   - age: seconds since the fix was produced.
    public init(horizontalAccuracy: CLLocationAccuracy, age: TimeInterval) {
        if horizontalAccuracy < 0 || age > 10 {
            self = .unavailable
        } else if horizontalAccuracy <= 12 {
            self = .good
        } else if horizontalAccuracy <= 35 {
            self = .fair
        } else {
            self = .poor
        }
    }
}
