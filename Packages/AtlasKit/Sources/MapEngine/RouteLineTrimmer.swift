import CoreLocation
import MapLibre
import MapLibreSwiftDSL

/// Starts the route line, and its traffic colours, at the car on every fix without a SwiftUI update. swiftui-dsl
/// rebuilds every layer on each update, so a line that changes once a second through SwiftUI would rebuild the
/// whole map once a second. This only swaps the data of the DSL's own sources, looked up by name each time (a
/// layer rebuild or a day/night style reload makes new ones), and the next SwiftUI update draws the same lines
/// from `route` and `traffic`.
@MainActor
public final class RouteLineTrimmer {
    weak var mapView: MLNMapView?

    public init() {}

    /// `traffic`: the route's slow stretches still ahead, already cut at the car.
    public func show(_ route: [CLLocationCoordinate2D], traffic: [TrafficLine]) {
        guard let style = mapView?.style else { return }
        if route.count > 1, let source = style.source(withIdentifier: AtlasMapView.routeSourceID) as? MLNShapeSource {
            source.shape = MLNPolylineFeature(coordinates: route)
        }
        // Only sources drawn at the last update exist; stretches only ever shrink between updates.
        for (level, identifier) in AtlasMapView.routeTrafficSources {
            guard let source = style.source(withIdentifier: identifier) as? MLNShapeSource else { continue }
            let lines = traffic.filter { $0.level == level && $0.coordinates.count > 1 }
            source.shape = MLNShapeCollection(shapes: lines.map { MLNPolylineFeature(coordinates: $0.coordinates) as MLNShape })
        }
    }
}
