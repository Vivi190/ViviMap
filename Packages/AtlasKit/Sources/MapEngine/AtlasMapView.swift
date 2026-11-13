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
    private let onViewport: (MapViewProxy) -> Void

    public init(
        camera: Binding<MapViewCamera>,
        appearance: MapAppearance,
        showsBuildings3D: Bool,
        onViewport: @escaping (MapViewProxy) -> Void = { _ in }
    ) {
        _camera = camera
        self.appearance = appearance
        self.showsBuildings3D = showsBuildings3D
        self.onViewport = onViewport
    }

    public var body: some View {
        let show3D = showsBuildings3D
        MapView(styleURL: appearance.styleURL, camera: $camera)
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

    private static let puckStyle = MapUserAnnotationStyle(
        approximateHaloBorderColor: .atlasAccent,
        approximateHaloFillColor: .atlasAccent,
        haloFillColor: .atlasAccent,
        puckArrowFillColor: .atlasAccent,
        puckFillColor: .atlasAccent
    )
}
