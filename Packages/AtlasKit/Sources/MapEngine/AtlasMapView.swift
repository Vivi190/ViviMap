import CoreLocation
import DesignSystem
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

/// Full-screen Atlas map. Holds no state of its own: camera, appearance and 3D mode come from the caller,
/// and MapLibre's built-in ornaments are hidden because the app draws its own controls.
public struct AtlasMapView: View {
    @Binding private var camera: MapViewCamera
    private let appearance: MapAppearance
    private let showsBuildings3D: Bool
    private let destination: CLLocationCoordinate2D?
    private let route: [CLLocationCoordinate2D]
    private let onViewport: (MapViewProxy) -> Void

    public init(
        camera: Binding<MapViewCamera>,
        appearance: MapAppearance,
        showsBuildings3D: Bool,
        destination: CLLocationCoordinate2D? = nil,
        route: [CLLocationCoordinate2D] = [],
        onViewport: @escaping (MapViewProxy) -> Void = { _ in }
    ) {
        _camera = camera
        self.appearance = appearance
        self.showsBuildings3D = showsBuildings3D
        self.destination = destination
        self.route = route
        self.onViewport = onViewport
    }

    public var body: some View {
        let show3D = showsBuildings3D
        MapView(styleURL: appearance.styleURL, camera: $camera) {
            if route.count > 1 {
                let line = ShapeSource(identifier: "atlas-route") {
                    MLNPolylineFeature(coordinates: route)
                }
                // Below the labels so street names stay readable on top of the route.
                LineStyleLayer(identifier: "atlas-route-casing", source: line)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(appearance == .night ? Self.routeCasingNight : .white)
                    .lineWidth(interpolatedBy: .zoomLevel, curveType: .exponential,
                               parameters: NSExpression(forConstantValue: 1.5),
                               stops: NSExpression(forConstantValue: [10: 6, 14: 10, 18: 28]))
                    .renderBelow(.symbols)
                LineStyleLayer(identifier: "atlas-route", source: line)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(Self.routeColor)
                    .lineWidth(interpolatedBy: .zoomLevel, curveType: .exponential,
                               parameters: NSExpression(forConstantValue: 1.5),
                               stops: NSExpression(forConstantValue: [10: 3.5, 14: 6.5, 18: 20]))
                    .renderBelow(.symbols)
            }
            if let destination {
                let pin = ShapeSource(identifier: "atlas-destination") {
                    MLNPointFeature(coordinate: destination)
                }
                CircleStyleLayer(identifier: "atlas-destination-halo", source: pin)
                    .radius(18)
                    .color(Self.destinationColor)
                    .circleOpacity(0.18)
                CircleStyleLayer(identifier: "atlas-destination", source: pin)
                    .radius(8)
                    .color(Self.destinationColor)
                    .strokeWidth(3)
                    .strokeColor(.white)
            }
        }
            .mapControls {
                // Empty: compass, logo and attribution are drawn by the app (attribution stays one tap away).
            }
            .mapUserAnnotationStyle(Self.puckStyle)
            .onMapViewProxyUpdate(updateMode: .realtime, onViewProxyChanged: onViewport)
            .onMapStyleLoaded { style in
                // A day/night switch reloads the style, which resets layer visibility to the JSON default.
                style.layer(withIdentifier: MapLayerID.buildings3D)?.isVisible = show3D
            }
            .unsafeMapViewControllerModifier { controller in
                let mapView = controller.mapView
                if !mapView.showsUserLocation { mapView.showsUserLocation = true }
                if !mapView.showsUserHeadingIndicator { mapView.showsUserHeadingIndicator = true }
                if let layer = mapView.style?.layer(withIdentifier: MapLayerID.buildings3D), layer.isVisible != show3D {
                    layer.isVisible = show3D
                }
            }
    }

    private static let destinationColor = UIColor(Color.atlasCritical)
    private static let routeColor = UIColor(Color.atlasAccent)
    private static let routeCasingNight = UIColor(red: 0.04, green: 0.10, blue: 0.20, alpha: 1)

    private static let puckStyle = MapUserAnnotationStyle(
        approximateHaloBorderColor: .atlasAccent,
        approximateHaloFillColor: .atlasAccent,
        haloFillColor: .atlasAccent,
        puckArrowFillColor: .atlasAccent,
        puckFillColor: .atlasAccent
    )
}
