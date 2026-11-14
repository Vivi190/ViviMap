// MapEngine's public API uses MapLibreSwiftUI types (MapViewCamera, MapViewProxy), so importers get them
// without declaring the dependency themselves.
@_exported import MapLibreSwiftUI
import MapLibre

public extension MapViewProxy {
    /// The visible area in degrees, without importing MapLibre's bounds type.
    var visibleBox: (west: Double, south: Double, east: Double, north: Double) {
        let bounds = visibleCoordinateBounds
        return (bounds.sw.longitude, bounds.sw.latitude, bounds.ne.longitude, bounds.ne.latitude)
    }
}
