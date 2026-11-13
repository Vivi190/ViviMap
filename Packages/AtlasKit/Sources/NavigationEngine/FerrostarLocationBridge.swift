import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI

/// Feeds Ferrostar from the app's single LocationProvider, so navigation, map and speedometer share one
/// GPS stream instead of each owning a CLLocationManager.
final class FerrostarLocationBridge: LocationProviding {
    weak var delegate: LocationManagingDelegate?
    // Fixes only arrive once location is authorized, so this is what Ferrostar needs to see.
    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    private(set) var lastLocation: UserLocation?
    var lastHeading: Heading? { nil }

    // LocationProvider owns the CLLocationManager and its lifecycle.
    func startUpdating() {}
    func stopUpdating() {}

    func forward(_ location: CLLocation) {
        let user = UserLocation(clLocation: location)
        lastLocation = user
        delegate?.locationManager(self, didUpdateLocations: [user])
    }
}
