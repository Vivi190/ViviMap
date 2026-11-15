import CoreLocation
import DesignSystem
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

/// A stretch of the route drawn in a traffic colour (MapEngine stays independent of the traffic provider).
public struct TrafficLine: Sendable {
    /// `free` (green) only on the city layer.
    public enum Level: Hashable, Sendable {
        case free, slow, heavy, stopped
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

/// A road event for the map (HERE incidents, city layer): a closed stretch is drawn as a red dashed line, and
/// every event gets a sign at its start.
public struct MapIncident: Sendable {
    public enum Kind: Hashable, Sendable {
        case closure, accident, roadworks
    }

    public let kind: Kind
    public let coordinates: [CLLocationCoordinate2D]

    public init(kind: Kind, coordinates: [CLLocationCoordinate2D]) {
        self.kind = kind
        self.coordinates = coordinates
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
    private let maneuverArrow: [[CLLocationCoordinate2D]]
    private let roadMarks: RoadMarks
    private let incidents: [MapIncident]
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
        maneuverArrow: [[CLLocationCoordinate2D]] = [],
        roadMarks: RoadMarks = .none,
        incidents: [MapIncident] = [],
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
        self.maneuverArrow = maneuverArrow
        self.roadMarks = roadMarks
        self.incidents = incidents
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
        let roadSigns = roadMarks
        let guiding = isGuiding
        let zoom = guidanceZoom
        let byLevel = Dictionary(grouping: traffic, by: \.level).mapValues { $0.map(\.coordinates) }
        let slow = byLevel[.slow] ?? [], heavy = byLevel[.heavy] ?? [], stopped = byLevel[.stopped] ?? []
        let area = Dictionary(grouping: areaTraffic, by: \.level).mapValues { $0.map(\.coordinates) }
        let closed = incidents.filter { $0.kind == .closure && $0.coordinates.count > 1 }.map(\.coordinates)
        let starts = Dictionary(grouping: incidents.compactMap { incident in incident.coordinates.first.map { (incident.kind, $0) } }, by: { $0.0 })
            .mapValues { pairs in pairs.map { $0.1 } }
        let closureStarts = starts[.closure] ?? [], accidentStarts = starts[.accident] ?? [], roadworkStarts = starts[.roadworks] ?? []
        let areaFree = area[.free] ?? [], areaSlow = area[.slow] ?? [], areaHeavy = area[.heavy] ?? [], areaStopped = area[.stopped] ?? []
        let cameraMarks = marks.filter(\.isCamera).map(\.coordinate), bumpMarks = marks.filter { !$0.isCamera }.map(\.coordinate)
        // Without a connection the shipped Istanbul tiles take over (when this build has them).
        let style = isOffline ? OfflineMap.styleURL(appearance) ?? appearance.styleURL : appearance.styleURL
        MapView(styleURL: style, camera: $camera, locationManager: puckSource) {
            // City traffic layer ("Trafik"): lowest of ours, so routes and their colours stay on top; worst on top.
            if !areaFree.isEmpty {
                Self.trafficLayer("area-free", areaFree, Self.trafficFree, widths: Self.areaWidths)
            }
            if !areaSlow.isEmpty {
                Self.trafficLayer("area-slow", areaSlow, Self.trafficSlow, widths: Self.areaWidths)
            }
            if !areaHeavy.isEmpty {
                Self.trafficLayer("area-heavy", areaHeavy, Self.trafficHeavy, widths: Self.areaWidths)
            }
            if !areaStopped.isEmpty {
                Self.trafficLayer("area-stopped", areaStopped, Self.trafficStopped, widths: Self.areaWidths)
            }
            // Road events (HERE): closed stretches dashed red over the traffic colours; signs on top of everything.
            if !closed.isEmpty {
                let source = ShapeSource(identifier: "atlas-closures") {
                    closed.map { MLNPolylineFeature(coordinates: $0) as MLNShape }
                }
                LineStyleLayer(identifier: "atlas-closures", source: source)
                    .lineColor(Self.closureColor)
                    .lineWidth(interpolatedBy: .zoomLevel, curveType: .exponential,
                               parameters: NSExpression(forConstantValue: 1.5),
                               stops: NSExpression(forConstantValue: [10: 2, 14: 4, 18: 9]))
                    .lineDashPattern([1.5, 1])
                    .renderBelow(.symbols)
            }
            if !closureStarts.isEmpty {
                Self.incidentLayer("closure", closureStarts, Self.closureSign)
            }
            if !accidentStarts.isEmpty {
                Self.incidentLayer("accident", accidentStarts, Self.accidentSign)
            }
            if !roadworkStarts.isEmpty {
                Self.incidentLayer("roadworks", roadworkStarts, Self.roadworksSign)
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
            // The next turn as a white arrow over the route and its traffic colours, under the street names.
            if !maneuverArrow.isEmpty {
                let arrow = ShapeSource(identifier: "atlas-maneuver") {
                    maneuverArrow.map { MLNPolylineFeature(coordinates: $0) as MLNShape }
                }
                LineStyleLayer(identifier: "atlas-maneuver-casing", source: arrow)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(Self.maneuverCasing)
                    .lineWidth(interpolatedBy: .zoomLevel, curveType: .exponential,
                               parameters: NSExpression(forConstantValue: 1.5),
                               stops: NSExpression(forConstantValue: [14: 7, 17: 13, 18: 19]))
                    .renderBelow(.symbols)
                LineStyleLayer(identifier: "atlas-maneuver", source: arrow)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(.white)
                    .lineWidth(interpolatedBy: .zoomLevel, curveType: .exponential,
                               parameters: NSExpression(forConstantValue: 1.5),
                               stops: NSExpression(forConstantValue: [14: 4, 17: 8, 18: 12]))
                    .renderBelow(.symbols)
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
                // A day/night switch reloads the style, which resets layer visibility to the JSON default
                // and drops images added at runtime.
                style.layer(withIdentifier: MapLayerID.buildings3D)?.isVisible = show3D
                POIIcons.register(in: style)
                RoadShields.register(in: style)
                roadSigns.add(to: style)
            }
            .unsafeMapViewControllerModifier { controller in
                let mapView = controller.mapView
                if !mapView.showsUserLocation { mapView.showsUserLocation = true }
                if !mapView.showsUserHeadingIndicator { mapView.showsUserHeadingIndicator = true }
                if let layer = mapView.style?.layer(withIdentifier: MapLayerID.buildings3D), layer.isVisible != show3D {
                    layer.isVisible = show3D
                }
                // Shops and cafés are noise while driving; street and place names stay.
                for id in MapLayerID.places {
                    if let layer = mapView.style?.layer(withIdentifier: id), layer.isVisible == guiding {
                        layer.isVisible = !guiding
                    }
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

    /// About the width of the road it covers, as Yandex draws traffic.
    private static func incidentLayer(_ name: String, _ points: [CLLocationCoordinate2D], _ sign: UIImage) -> some StyleLayerDefinition {
        let source = ShapeSource(identifier: "atlas-incident-\(name)") {
            points.map { MLNPointFeature(coordinate: $0) as MLNShape }
        }
        return SymbolStyleLayer(identifier: "atlas-incident-\(name)", source: source)
            .iconImage(sign)
            .iconAllowsOverlap(true)
    }

    private static let closureColor = UIColor(red: 0.90, green: 0.22, blue: 0.21, alpha: 1)
    /// "No entry": a white bar on a red disc.
    private static let closureSign = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in
        let rect = CGRect(x: 0, y: 0, width: 20, height: 20)
        UIColor.white.setFill()
        UIBezierPath(ovalIn: rect).fill()
        closureColor.setFill()
        UIBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
        UIColor.white.setFill()
        UIBezierPath(roundedRect: CGRect(x: 4.5, y: 8.5, width: 11, height: 3), cornerRadius: 1.5).fill()
    }
    private static let accidentSign = POIIcons.badge("car.side.rear.and.collision.and.car.side.front", color: POIIcons.rgb(0xFF6B00), diameter: 20)
    private static let roadworksSign = POIIcons.badge("cone.fill", color: POIIcons.rgb(0xFF9500), diameter: 20)

    private static let areaWidths: [Int: Double] = [10: 2, 13: 3, 15: 4.5, 18: 11]

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

    private static let trafficFree = UIColor(red: 0.20, green: 0.70, blue: 0.33, alpha: 1)
    private static let trafficSlow = UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1)
    private static let trafficHeavy = UIColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1)
    private static let trafficStopped = UIColor(red: 0.50, green: 0.11, blue: 0.11, alpha: 1)
    private static let destinationColor = UIColor(Color.atlasCritical)
    private static let routeColor = UIColor(Color.atlasAccent)
    private static let routeCasingNight = UIColor(red: 0.04, green: 0.10, blue: 0.20, alpha: 1)
    /// Darker than the route blue, so the white arrow stands out on it and beside it.
    private static let maneuverCasing = UIColor(red: 0.03, green: 0.22, blue: 0.55, alpha: 1)
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
