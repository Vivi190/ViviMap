import CoreLocation
import MapLibre
import MapLibreSwiftUI
import UIKit

public enum TrackingMode: Sendable {
    case none
    case follow
    /// Map rotates with the device heading (standing/walking) or the GPS course (driving).
    case followDirection
}

public extension MapViewCamera {
    var trackingMode: TrackingMode {
        switch state {
        case .trackingUserLocation: .follow
        case .trackingUserLocationWithHeading, .trackingUserLocationWithCourse: .followDirection
        default: .none
        }
    }

    /// Frames a box (e.g. a route) with room for the floating chrome.
    static func fitting(southWest: CLLocationCoordinate2D, northEast: CLLocationCoordinate2D, padding: UIEdgeInsets) -> MapViewCamera {
        .boundingBox(MLNCoordinateBounds(sw: southWest, ne: northEast), edgePadding: padding)
    }

    /// Next state for the location button: free → follow → follow direction → follow.
    /// `isDriving` picks course over compass heading, because the compass is unreliable inside a car.
    func nextTrackingCamera(zoom: Double, pitch: Double, isDriving: Bool) -> MapViewCamera {
        switch trackingMode {
        case .none, .followDirection:
            .trackUserLocation(zoom: zoom, pitch: pitch)
        case .follow:
            isDriving
                ? .trackUserLocationWithCourse(zoom: zoom, pitch: pitch)
                : .trackUserLocationWithHeading(zoom: zoom, pitch: pitch)
        }
    }
}
