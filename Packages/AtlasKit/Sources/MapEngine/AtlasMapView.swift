import CoreLocation
import DesignSystem
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

/// A stretch of the route drawn in a traffic colour (MapEngine stays independent of the traffic provider).
public struct TrafficLine: Sendable {
    public enum Level: Hashable, Sendable {
        case slow, heavy, stopped
    }

    public let level: Level
    public let coordinates: [CLLocationCoordinate2D]

    public init(level: Level, coordinates: [CLLocationCoordinate2D]) {
        self.level = level
        self.coordinates = coordinates
    }
}

/// A camera or bump the driver marked, shown as a small dot.
public struct MapMark: Sendable {
    public let isCamera: Bool
    public let coordinate: CLLocationCoordinate2D

    public init(isCamera: Bool, coordinate: CLLocationCoordinate2D) {
        self.isCamera = isCamera
        self.coordinate = coordinate
    }
}

/// Full-screen Atlas map. Holds no state of its own: camera, appearance and 3D mode come from the caller,
/// and MapLibre's built-in ornaments are hidden because the app draws its own controls.
public struct AtlasMapView: View {
    @Binding private var camera: MapViewCamera
    private let appearance: MapAppearance
    private let showsBuildings3D: Bool
    private let destination: CLLocationCoordinate2D?
    private let route: [CLLocationCoordinate2D]
    private let alternatives: [[CLLocationCoordinate2D]]
    private let traffic: [TrafficLine]
    private let areaTraffic: [TrafficLine]
    private let marks: [MapMark]
    private let onLongPress: ((CLLocationCoordinate2D) -> Void)?
    private let onViewport: (MapViewProxy) -> Void
    private let puckSource: StaticLocationManager?
    private let isGuiding: Bool
    private let guidanceZoom: Double?
    private let isOffline: Bool

    /// `puckSource` replaces CoreLocation for the user puck (simulated drive); nil = real GPS.
    /// `isGuiding` moves the puck low on screen so the road ahead gets the room.
    public init(
        camera: Binding<MapViewCamera>,
        appearance: MapAppearance,
        showsBuildings3D: Bool,
        destination: CLLocationCoordinate2D? = nil,
        route: [CLLocationCoordinate2D] = [],
        alternatives: [[CLLocationCoordinate2D]] = [],
        traffic: [TrafficLine] = [],
        areaTraffic: [TrafficLine] = [],
        marks: [MapMark] = [],
        puckSource: StaticLocationManager? = nil,
        isGuiding: Bool = false,
        guidanceZoom: Double? = nil,
        isOffline: Bool = false,
        onLongPress: ((CLLocationCoordinate2D) -> Void)? = nil,
        onViewport: @escaping (MapViewProxy) -> Void = { _ in }
    ) {
        _camera = camera
        self.appearance = appearance
        self.showsBuildings3D = showsBuildings3D
        self.destination = destination
        self.route = route
        self.alternatives = alternatives
        self.traffic = traffic
        self.areaTraffic = areaTraffic
        self.marks = marks
        self.puckSource = puckSource
        self.isGuiding = isGuiding
        self.guidanceZoom = guidanceZoom
        self.isOffline = isOffline
        self.onLongPress = onLongPress
        self.onViewport = onViewport
    }

    public var body: some View {
        // The guidance inset needs the size SwiftUI is laying out now: on rotation the map is updated before
        // UIKit resizes it, and the old portrait bounds left the puck under the landscape panels.
        GeometryReader { geometry in
            map(size: geometry.size)
        }
    }

    @ViewBuilder
    private func map(size: CGSize) -> some View {
        let show3D = showsBuildings3D
        let guiding = isGuiding
        let zoom = guidanceZoom
        let byLevel = Dictionary(grouping: traffic, by: \.level).mapValues { $0.map(\.coordinates) }
        let slow = byLevel[.slow] ?? [], heavy = byLevel[.heavy] ?? [], stopped = byLevel[.stopped] ?? []
        let area = Dictionary(grouping: areaTraffic, by: \.level).mapValues { $0.map(\.coordinates) }
        let areaSlow = area[.slow] ?? [], areaHeavy = area[.heavy] ?? [], areaStopped = area[.stopped] ?? []
        let cameraMarks = marks.filter(\.isCamera).map(\.coordinate), bumpMarks = marks.filter { !$0.isCamera }.map(\.coordinate)
        // Without a connection the shipped Istanbul tiles take over (when this build has them).
        let style = isOffline ? OfflineMap.styleURL(appearance) ?? appearance.styleURL : appearance.styleURL
        MapView(styleURL: style, camera: $camera, locationManager: puckSource) {
            // City traffic layer ("Trafik"): lowest of ours and thinner, so routes and their colours stay on top.
            if !areaSlow.isEmpty {
                Self.trafficLayer("area-slow", areaSlow, Self.trafficSlow, widths: Self.areaWidths)
            }
            if !areaHeavy.isEmpty {
                Self.trafficLayer("area-heavy", areaHeavy, Self.trafficHeavy, widths: Self.areaWidths)
            }
            if !areaStopped.isEmpty {
                Self.trafficLayer("area-stopped", areaStopped, Self.trafficStopped, widths: Self.areaWidths)
            }
            // Other candidates in a paler blue under the chosen route, so the driver sees where each one goes.
            if !alternatives.isEmpty {
                let others = ShapeSource(identifier: "atlas-alternatives") {
                    alternatives.map { MLNPolylineFeature(coordinates: $0) as MLNShape }
                }
                LineStyleLayer(identifier: "atlas-alternatives-casing", source: others)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(appearance == .night ? Self.routeCasingNight : .white)
                    .lineWidth(interpolatedBy: .zoomLevel, curveType: .exponential,
                               parameters: NSExpression(forConstantValue: 1.5),
                               stops: NSExpression(forConstantValue: [10: 5, 14: 8.5, 18: 24]))
                    .renderBelow(.symbols)
                LineStyleLayer(identifier: "atlas-alternatives", source: others)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(appearance == .night ? Self.alternativeNight : Self.alternativeDay)
                    .lineWidth(interpolatedBy: .zoomLevel, curveType: .exponential,
                               parameters: NSExpression(forConstantValue: 1.5),
                               stops: NSExpression(forConstantValue: [10: 3, 14: 5.5, 18: 17]))
                    .renderBelow(.symbols)
            }
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
            // Traffic colours over the route line, worst on top.
            if !slow.isEmpty {
                Self.trafficLayer("route-slow", slow, Self.trafficSlow)
            }
            if !heavy.isEmpty {
                Self.trafficLayer("route-heavy", heavy, Self.trafficHeavy)
            }
            if !stopped.isEmpty {
                Self.trafficLayer("route-stopped", stopped, Self.trafficStopped)
            }
            if !cameraMarks.isEmpty {
                Self.markLayer("camera", cameraMarks, Self.destinationColor)
            }
            if !bumpMarks.isEmpty {
                Self.markLayer("bump", bumpMarks, Self.trafficSlow)
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
            .onLongPressMapGesture { context in
                // Fire once when the press is recognised, not on every movement after it.
                if context.state == .began { onLongPress?(context.coordinate) }
            }
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
                // Guidance: puck at ~70 % of the height (centre of the area below a 40 % top inset); on its side
                // the panels take a left column, so the puck centres in the map area to their right.
                // Otherwise the safe area, which is what MapLibre's automatic inset uses. Set directly
                // because swiftui-dsl's mapContentInset never resets once its value goes back to nil.
                let inset = !guiding ? mapView.safeAreaInsets
                    : size.width > size.height
                    ? UIEdgeInsets(top: size.height * 0.3, left: min(size.width * 0.45, 420), bottom: 0, right: 0)
                    : UIEdgeInsets(top: size.height * 0.4, left: 0, bottom: 0, right: 0)
                if mapView.contentInset != inset {
                    mapView.automaticallyAdjustsContentInset = false
                    mapView.setContentInset(inset, animated: true, completionHandler: nil)
                }
                // Closer before a turn, farther on fast roads: eased here, because swiftui-dsl's course
                // tracking sets the zoom without animation and the map jumped. Only while it follows the car;
                // a driver who moved the map keeps their view.
                if guiding, let zoom, mapView.userTrackingMode == .followWithCourse, abs(mapView.zoomLevel - zoom) > 0.05 {
                    mapView.setZoomLevel(zoom, animated: true)
                }
            }
    }

    /// By default as wide as the route's inner line, so a slow stretch reads as the route turning orange or red.
    private static func trafficLayer(
        _ name: String,
        _ lines: [[CLLocationCoordinate2D]],
        _ color: UIColor,
        widths: [Int: Double] = [10: 3.5, 14: 6.5, 18: 20]
    ) -> some StyleLayerDefinition {
        let source = ShapeSource(identifier: "atlas-traffic-\(name)") {
            lines.map { MLNPolylineFeature(coordinates: $0) as MLNShape }
        }
        return LineStyleLayer(identifier: "atlas-traffic-\(name)", source: source)
            .lineCap(.round)
            .lineJoin(.round)
            .lineColor(color)
            .lineWidth(interpolatedBy: .zoomLevel, curveType: .exponential,
                       parameters: NSExpression(forConstantValue: 1.5),
                       stops: NSExpression(forConstantValue: widths))
            .renderBelow(.symbols)
    }

    private static let areaWidths: [Int: Double] = [10: 1.5, 14: 3.5, 18: 9]

    private static func markLayer(_ name: String, _ points: [CLLocationCoordinate2D], _ color: UIColor) -> some StyleLayerDefinition {
        let source = ShapeSource(identifier: "atlas-mark-\(name)") {
            points.map { MLNPointFeature(coordinate: $0) as MLNShape }
        }
        return CircleStyleLayer(identifier: "atlas-mark-\(name)", source: source)
            .radius(6)
            .color(color)
            .strokeWidth(2)
            .strokeColor(.white)
    }

    private static let trafficSlow = UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1)
    private static let trafficHeavy = UIColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1)
    private static let trafficStopped = UIColor(red: 0.50, green: 0.11, blue: 0.11, alpha: 1)
    private static let destinationColor = UIColor(Color.atlasCritical)
    private static let routeColor = UIColor(Color.atlasAccent)
    private static let routeCasingNight = UIColor(red: 0.04, green: 0.10, blue: 0.20, alpha: 1)
    private static let alternativeDay = UIColor(red: 0.53, green: 0.69, blue: 0.96, alpha: 1)
    private static let alternativeNight = UIColor(red: 0.27, green: 0.40, blue: 0.62, alpha: 1)

    private static let puckStyle = MapUserAnnotationStyle(
        approximateHaloBorderColor: .atlasAccent,
        approximateHaloFillColor: .atlasAccent,
        haloFillColor: .atlasAccent,
        puckArrowFillColor: .atlasAccent,
        puckFillColor: .atlasAccent
    )
}
