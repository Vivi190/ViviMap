import CoreLocation
import Observation

/// The app's single CLLocationManager owner: latest fix, smoothed speed and authorization state.
///
/// MapLibre keeps its own manager for the user puck in Phase 1; Phase 2 feeds the puck from here so the
/// map, speedometer and navigation all see the same (snapped) position.
@MainActor
@Observable
public final class LocationProvider: NSObject {
    public private(set) var authorization: CLAuthorizationStatus = .notDetermined
    public private(set) var isPreciseLocation = true
    public private(set) var lastLocation: CLLocation?
    /// Flips to true once per session; observe this instead of `lastLocation` to avoid a re-render per fix.
    public private(set) var hasFix = false
    /// Seconds between the two most recent fixes, for diagnostics.
    public private(set) var updateInterval: TimeInterval?
    public private(set) var lastError: String?

    @ObservationIgnored private let manager = CLLocationManager()
    // Observed on purpose: views calling speedReading(at:) re-render on every fix, plus on their own timer
    // so a reading can go stale when fixes stop.
    private var estimator = SpeedEstimator()

    override public init() {
        super.init()
        manager.delegate = self
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        // Default pausing stops fixes during long red lights and never resumes them in the foreground.
        manager.pausesLocationUpdatesAutomatically = false
        refreshAuthorization()
        // The cached fix lets the map open near the user before the first live update.
        lastLocation = manager.location
    }

    public var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    public var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    public func start() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    public func stop() {
        manager.stopUpdatingLocation()
    }

    /// Speed as of `date`; goes stale when fixes stop arriving (tunnel, lost signal).
    public func speedReading(at date: Date) -> SpeedEstimator.Reading {
        estimator.reading(at: date)
    }

    public func quality(at date: Date) -> LocationQuality {
        guard let lastLocation else { return .unavailable }
        return LocationQuality(
            horizontalAccuracy: lastLocation.horizontalAccuracy,
            age: date.timeIntervalSince(lastLocation.timestamp)
        )
    }

    private func refreshAuthorization() {
        authorization = manager.authorizationStatus
        isPreciseLocation = manager.accuracyAuthorization == .fullAccuracy
    }

    private func ingest(_ location: CLLocation) {
        if let previous = lastLocation {
            let interval = location.timestamp.timeIntervalSince(previous.timestamp)
            guard interval >= 0 else { return } // out-of-order fix
            if interval > 0 { updateInterval = interval }
        }
        lastLocation = location
        if !hasFix { hasFix = true } // Observation notifies on every set, even with an equal value
        _ = estimator.update(speed: location.speed, speedAccuracy: location.speedAccuracy, at: location.timestamp)
        lastError = nil
    }
}

// The manager is created on the main thread, so CoreLocation calls the delegate there;
// @preconcurrency turns that assumption into a runtime check instead of hopping actors.
extension LocationProvider: @preconcurrency CLLocationManagerDelegate {
    public func locationManagerDidChangeAuthorization(_: CLLocationManager) {
        refreshAuthorization()
        if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    public func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            ingest(location)
        }
    }

    public func locationManager(_: CLLocationManager, didFailWithError error: any Error) {
        // kCLErrorLocationUnknown is transient (e.g. tunnels): keep the last fix and let staleness show it.
        if (error as? CLError)?.code != .locationUnknown {
            lastError = error.localizedDescription
        }
    }
}
