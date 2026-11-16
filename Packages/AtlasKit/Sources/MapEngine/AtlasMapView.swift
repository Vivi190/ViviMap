import CoreLocation
import DesignSystem
import MapLibre
import MapLibreSwiftDSL
import MapLibreSwiftUI
import SwiftUI

/// A stretch of road drawn in a traffic colour (MapEngine stays independent of the traffic provider).
public struct TrafficLine: Sendable {
    /// From flowing to standstill; `free` (green) only on the city layer.
    public enum Level: Int, Hashable, Sendable, CaseIterable {
        case free = 0, slow, heavy, stopped
    }

    public let level: Level
    public let coordinates: [CLLocationCoordinate2D]
    /// A motorway or trunk road: drawn a little wider on the city layer.
    public let isMajor: Bool

    public init(level: Level, coordinates: [CLLocationCoordinate2D], isMajor: Bool = false) {
        self.level = level
        self.coordinates = coordinates
        self.isMajor = isMajor
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

/// A place a search found, shown as a pin on the map; a tap hands its id back (`onPlaceTap`).
public struct MapPin: Sendable {
    public let id: String
    public let name: String
    public let coordinate: CLLocationCoordinate2D

    public init(id: String, name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
    }
}

/// A place badge of the base map that was tapped (a shop, a pharmacy, a station), as the tiles describe it.
public struct MapPlace: Sendable {
    /// The name its label shows: the Turkish one when the tiles have it.
    public let name: String
    public let coordinate: CLLocationCoordinate2D
    /// The tiles' `subclass`, which is the value of the OSM tag ("pharmacy", "station"), and their coarser
    /// `class` ("railway", "grocery"); nil when the tile has neither.
    public let kind: String?
    public let group: String?
    /// The search index's id when the badge is one of its businesses (BusinessOverlay); nil for the base map's.
    public let id: String?

    init?(_ feature: any MLNFeature) {
        self.init(attributes: feature.attributes, coordinate: feature.coordinate)
    }

    /// nil without a name: there is nothing to open a card with.
    init?(attributes: [String: Any], coordinate: CLLocationCoordinate2D) {
        guard let name = attributes["name:tr"] as? String ?? attributes["name"] as? String, !name.isEmpty else { return nil }
        self.name = name
        self.coordinate = coordinate
        kind = attributes["subclass"] as? String
        group = attributes["class"] as? String
        id = attributes["id"] as? String
    }
}

/// Full-screen Atlas map. Holds no state of its own: camera, appearance and 3D mode come from the caller,
/// and MapLibre's built-in ornaments are hidden because the app draws its own controls.
public struct AtlasMapView: View {
    @Binding private var camera: MapViewCamera
    /// MapLibre is following the car with the course up (its own report, not the camera binding).
    @State private var followsCourse = false
    private let appearance: MapAppearance
    private let showsBuildings3D: Bool
    private let destination: CLLocationCoordinate2D?
    private let stops: [CLLocationCoordinate2D]
    private let route: [CLLocationCoordinate2D]
    private let alternatives: [[CLLocationCoordinate2D]]
    private let routeIsMeasured: Bool
    private let routeLabels: [RouteLabel]
    private let traffic: [TrafficLine]
    private let areaTraffic: [TrafficLine]
    private let marks: [MapMark]
    private let maneuverArrow: [[CLLocationCoordinate2D]]
    private let roadMarks: RoadMarks
    private let incidents: [MapIncident]
    private let routeTrimmer: RouteLineTrimmer?
    private let trafficOverlay: TrafficOverlay?
    private let businesses: [MapBusiness]
    private let businessOverlay: BusinessOverlay?
    private let pins: [MapPin]
    private let showsGuidanceCursor: Bool
    private let onFollowingChanged: ((Bool) -> Void)?
    private let onTap: (() -> Void)?
    private let onPlaceTap: ((MapPlace) -> Void)?
    private let onRouteTap: ((Int) -> Void)?
    private let onLongPress: ((CLLocationCoordinate2D) -> Void)?
    private let onViewport: (MapViewProxy) -> Void
    private let puckSource: StaticLocationManager?
    private let isGuiding: Bool
    private let guidanceZoom: Double?
    private let isOffline: Bool

    /// `puckSource` replaces CoreLocation for the user puck (simulated drive); nil = real GPS.
    /// `isGuiding` moves the puck low on screen so the road ahead gets the room.
    /// `stops`: the stops on the way to `destination`, each with a pin of its own.
    public init(
        camera: Binding<MapViewCamera>,
        appearance: MapAppearance,
        showsBuildings3D: Bool,
        destination: CLLocationCoordinate2D? = nil,
        stops: [CLLocationCoordinate2D] = [],
        route: [CLLocationCoordinate2D] = [],
        alternatives: [[CLLocationCoordinate2D]] = [],
        routeIsMeasured: Bool = false,
        routeLabels: [RouteLabel] = [],
        traffic: [TrafficLine] = [],
        areaTraffic: [TrafficLine] = [],
        marks: [MapMark] = [],
        maneuverArrow: [[CLLocationCoordinate2D]] = [],
        roadMarks: RoadMarks = .none,
        incidents: [MapIncident] = [],
        routeTrimmer: RouteLineTrimmer? = nil,
        trafficOverlay: TrafficOverlay? = nil,
        businesses: [MapBusiness] = [],
        businessOverlay: BusinessOverlay? = nil,
        pins: [MapPin] = [],
        puckSource: StaticLocationManager? = nil,
        isGuiding: Bool = false,
        guidanceZoom: Double? = nil,
        isOffline: Bool = false,
        showsGuidanceCursor: Bool = false,
        onFollowingChanged: ((Bool) -> Void)? = nil,
        onTap: (() -> Void)? = nil,
        onPlaceTap: ((MapPlace) -> Void)? = nil,
        onRouteTap: ((Int) -> Void)? = nil,
        onLongPress: ((CLLocationCoordinate2D) -> Void)? = nil,
        onViewport: @escaping (MapViewProxy) -> Void = { _ in }
    ) {
        _camera = camera
        self.appearance = appearance
        self.showsBuildings3D = showsBuildings3D
        self.destination = destination
        self.stops = stops
        self.route = route
        self.alternatives = alternatives
        self.routeIsMeasured = routeIsMeasured
        self.routeLabels = routeLabels
        self.traffic = traffic
        self.areaTraffic = areaTraffic
        self.marks = marks
        self.maneuverArrow = maneuverArrow
        self.roadMarks = roadMarks
        self.incidents = incidents
        self.routeTrimmer = routeTrimmer
        self.trafficOverlay = trafficOverlay
        self.businesses = businesses
        self.businessOverlay = businessOverlay
        self.pins = pins
        self.puckSource = puckSource
        self.isGuiding = isGuiding
        self.guidanceZoom = guidanceZoom
        self.isOffline = isOffline
        self.showsGuidanceCursor = showsGuidanceCursor
        self.onFollowingChanged = onFollowingChanged
        self.onTap = onTap
        self.onPlaceTap = onPlaceTap
        self.onRouteTap = onRouteTap
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
        // Our own arrow marks the car while the map follows it in guidance; MapLibre's puck is then kept only
        // for its tracking.
        let ownCursor = showsGuidanceCursor && followsCourse
        let byLevel = Dictionary(grouping: traffic, by: \.level).mapValues { $0.map(\.coordinates) }
        let slow = byLevel[.slow] ?? [], heavy = byLevel[.heavy] ?? [], stopped = byLevel[.stopped] ?? []
        let closed = incidents.filter { $0.kind == .closure && $0.coordinates.count > 1 }.map(\.coordinates)
        let starts = Dictionary(grouping: incidents.compactMap { incident in incident.coordinates.first.map { (incident.kind, $0) } }, by: { $0.0 })
            .mapValues { pairs in pairs.map { $0.1 } }
        let closureStarts = starts[.closure] ?? [], accidentStarts = starts[.accident] ?? [], roadworkStarts = starts[.roadworks] ?? []
        let cityLines = areaTraffic
        let cityTraffic = trafficOverlay
        let shops = businesses
        let shopOverlay = businessOverlay
        let cameraMarks = marks.filter(\.isCamera).map(\.coordinate), bumpMarks = marks.filter { !$0.isCamera }.map(\.coordinate)
        // The chosen route's time last, so it sits on top where bubbles meet (Valhalla gives at most three).
        let labels = routeLabels.filter { !$0.isSelected } + routeLabels.filter(\.isSelected)
        let night = appearance == .night
        // Without a connection the shipped Istanbul tiles take over (when this build has them).
        let style = isOffline ? OfflineMap.styleURL(appearance) ?? appearance.styleURL : appearance.styleURL
        MapView(styleURL: style, camera: $camera, locationManager: puckSource) {
            // The city traffic layer is not here: TrafficOverlay keeps it on the style itself.
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
                               stops: NSExpression(forConstantValue: [10: 4.5, 14: 7.5, 18: 15]))
                    .renderBelow(.symbols)
                LineStyleLayer(identifier: "atlas-alternatives", source: others)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(appearance == .night ? Self.alternativeNight : Self.alternativeDay)
                    .lineWidth(interpolatedBy: .zoomLevel, curveType: .exponential,
                               parameters: NSExpression(forConstantValue: 1.5),
                               stops: NSExpression(forConstantValue: [10: 3, 14: 5, 18: 11]))
                    .renderBelow(.symbols)
            }
            if route.count > 1 {
                let line = ShapeSource(identifier: Self.routeSourceID) {
                    MLNPolylineFeature(coordinates: route)
                }
                // Below the labels so street names stay readable on top of the route.
                LineStyleLayer(identifier: "atlas-route-casing", source: line)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(appearance == .night ? Self.routeCasingNight : .white)
                    .lineWidth(interpolatedBy: .zoomLevel, curveType: .exponential,
                               parameters: NSExpression(forConstantValue: 1.5),
                               stops: NSExpression(forConstantValue: [10: 5.5, 14: 9, 18: 18]))
                    .renderBelow(.symbols)
                LineStyleLayer(identifier: "atlas-route", source: line)
                    .lineCap(.round)
                    .lineJoin(.round)
                    // With live traffic the route reads like the traffic layer: green where it flows, its slow
                    // stretches drawn over it. Without, the brand blue says nothing about traffic.
                    .lineColor(routeIsMeasured ? TrafficOverlay.color(.free, night: night) : Self.routeColor)
                    .lineWidth(interpolatedBy: .zoomLevel, curveType: .exponential,
                               parameters: NSExpression(forConstantValue: 1.5),
                               stops: NSExpression(forConstantValue: [10: 3.5, 14: 6, 18: 13]))
                    .renderBelow(.symbols)
            }
            // Traffic colours over the route line, worst on top.
            if !slow.isEmpty {
                Self.trafficLayer("route-slow", slow, TrafficOverlay.color(.slow, night: night))
            }
            if !heavy.isEmpty {
                Self.trafficLayer("route-heavy", heavy, TrafficOverlay.color(.heavy, night: night))
            }
            if !stopped.isEmpty {
                Self.trafficLayer("route-stopped", stopped, TrafficOverlay.color(.stopped, night: night))
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
                               stops: NSExpression(forConstantValue: [14: 6, 17: 11, 18: 15]))
                    .renderBelow(.symbols)
                LineStyleLayer(identifier: "atlas-maneuver", source: arrow)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineColor(.white)
                    .lineWidth(interpolatedBy: .zoomLevel, curveType: .exponential,
                               parameters: NSExpression(forConstantValue: 1.5),
                               stops: NSExpression(forConstantValue: [14: 3.5, 17: 7, 18: 10]))
                    .renderBelow(.symbols)
            }
            if !cameraMarks.isEmpty {
                Self.markLayer("camera", cameraMarks, Self.destinationColor)
            }
            if !bumpMarks.isEmpty {
                Self.markLayer("bump", bumpMarks, Self.bumpMark)
            }
            // A search's results as pins, their names under them where there is room. The chosen one has the
            // destination pin instead, drawn after these and so on top.
            if !pins.isEmpty {
                let results = ShapeSource(identifier: Self.resultsLayerID) {
                    pins.map { pin in
                        MLNPointFeature(coordinate: pin.coordinate) { $0.attributes = ["name": pin.name, "id": pin.id] } as MLNShape
                    }
                }
                // Names apart from the pins: a name that collides is left out, the pin stays.
                SymbolStyleLayer(identifier: Self.resultNamesLayerID, source: results)
                    .text(featurePropertyNamed: "name")
                    // The style's own font: MapLibre's default stack is not on the tile server.
                    .textFontNames(["Noto Sans Regular"])
                    .textFontSize(12)
                    .textAnchor("top")
                    .maximumTextWidth(8)
                    .textColor(night ? Self.resultTextNight : Self.resultTextDay)
                    .textHaloColor(night ? Self.routeCasingNight : .white)
                    .textHaloWidth(1.4)
                SymbolStyleLayer(identifier: Self.resultsLayerID, source: results)
                    .iconImage(Self.resultPin)
                    .iconAnchor("bottom")
                    .iconAllowsOverlap(true)
            }
            if !stops.isEmpty {
                let source = ShapeSource(identifier: "atlas-stops") {
                    stops.map { MLNPointFeature(coordinate: $0) as MLNShape }
                }
                SymbolStyleLayer(identifier: "atlas-stops", source: source)
                    .iconImage(Self.stopPin)
                    .iconAnchor("bottom")
                    .iconAllowsOverlap(true)
            }
            if let destination {
                let pin = ShapeSource(identifier: "atlas-destination") {
                    MLNPointFeature(coordinate: destination)
                }
                SymbolStyleLayer(identifier: "atlas-destination", source: pin)
                    .iconImage(Self.destinationPin)
                    .iconAnchor("bottom")
                    .iconAllowsOverlap(true)
            }
            // Each candidate's time on the map, over everything, as Apple Maps and Yandex show it.
            if labels.count > 0 {
                Self.routeLabelLayer(0, labels[0], night: night)
            }
            if labels.count > 1 {
                Self.routeLabelLayer(1, labels[1], night: night)
            }
            if labels.count > 2 {
                Self.routeLabelLayer(2, labels[2], night: night)
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
            .onTapMapGesture(on: Self.tapLayers) { _, features in
                // A tapped callout chooses its route and a tapped place badge opens that place; a tap anywhere
                // else is passed on (guidance shows its side buttons for it).
                if let route = features.lazy.compactMap({ ($0.attributes["route"] as? NSNumber)?.intValue }).first {
                    onRouteTap?(route)
                } else if let place = features.lazy.compactMap({ MapPlace($0) }).first {
                    onPlaceTap?(place)
                } else {
                    onTap?()
                }
            }
            .onMapUserTrackingModeChanged { mode, _ in
                // A gesture that stops the following is reported here even while the map is still moving, which
                // the camera binding misses.
                let follows = mode != MLNUserTrackingMode.none
                let course = mode == MLNUserTrackingMode.followWithCourse
                if followsCourse != course { followsCourse = course }
                onFollowingChanged?(follows)
            }
            .onMapStyleLoaded { style in
                // A day/night switch reloads the style, which resets layer visibility to the JSON default
                // and drops images added at runtime.
                style.layer(withIdentifier: MapLayerID.buildings3D)?.isVisible = show3D
                POIIcons.register(in: style)
                RoadShields.register(in: style)
                roadSigns.add(to: style)
                cityTraffic?.add(to: style, night: night)
                shopOverlay?.add(to: style)
            }
            .unsafeMapViewControllerModifier { controller in
                let mapView = controller.mapView
                if let routeTrimmer {
                    if routeTrimmer.mapView !== mapView { routeTrimmer.mapView = mapView }
                    routeTrimmer.hidesPuck = ownCursor
                }
                RouteLineTrimmer.setPuck(hidden: ownCursor, in: mapView)
                cityTraffic?.show(cityLines, in: mapView.style)
                shopOverlay?.show(shops, in: mapView.style)
                if !mapView.showsUserLocation { mapView.showsUserLocation = true }
                if !mapView.showsUserHeadingIndicator { mapView.showsUserHeadingIndicator = true }
                if let layer = mapView.style?.layer(withIdentifier: MapLayerID.buildings3D), layer.isVisible != show3D {
                    layer.isVisible = show3D
                }
                // Shops and cafés are noise while driving; street and place names stay.
                for id in MapLayerID.places + [BusinessOverlay.layerID] {
                    if let layer = mapView.style?.layer(withIdentifier: id), layer.isVisible == guiding {
                        layer.isVisible = !guiding
                    }
                }
                // Guidance: puck at ~70 % of the height (centre of the area below a 40 % top inset); on its side
                // the panels take a left column, so the puck centres in the map area to their right.
                // Otherwise the safe area, which is what MapLibre's automatic inset uses. Set directly
                // because swiftui-dsl's mapContentInset never resets once its value goes back to nil.
                let inset = guiding ? Self.guidanceInset(for: size) : mapView.safeAreaInsets
                if mapView.contentInset != inset {
                    mapView.automaticallyAdjustsContentInset = false
                    mapView.setContentInset(inset, animated: true, completionHandler: nil)
                }
                // Closer before a turn, farther on fast roads: eased here, because swiftui-dsl's course
                // tracking sets the zoom without animation and the map jumped. Only while it follows the car;
                // a driver who moved the map keeps their view.
                if guiding, let zoom, mapView.userTrackingMode != .none, abs(mapView.zoomLevel - zoom) > 0.05 {
                    mapView.setZoomLevel(zoom, animated: true)
                }
            }
            .overlay {
                if ownCursor {
                    // While it follows, MapLibre pins the tracked position to the centre of the area inside the
                    // content inset, so the arrow can be a plain view there.
                    GuidanceCursor()
                        .position(Self.guidanceAnchor(in: size))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: ownCursor)
    }

    /// Guidance keeps the car low on screen so the road ahead gets the room: the top 40 % is left to the turn
    /// card in portrait; on its side the panels take a left column and the top 30 %.
    nonisolated static func guidanceInset(for size: CGSize) -> UIEdgeInsets {
        size.width > size.height
            ? UIEdgeInsets(top: size.height * 0.3, left: min(size.width * 0.45, 420), bottom: 0, right: 0)
            : UIEdgeInsets(top: size.height * 0.4, left: 0, bottom: 0, right: 0)
    }

    /// Where the car is drawn while the map follows it: the centre of what the guidance inset leaves.
    nonisolated static func guidanceAnchor(in size: CGSize) -> CGPoint {
        let inset = guidanceInset(for: size)
        return CGPoint(
            x: inset.left + (size.width - inset.left - inset.right) / 2,
            y: inset.top + (size.height - inset.top - inset.bottom) / 2
        )
    }

    /// The route line's source and its traffic colours' (trafficLayer names them "atlas-traffic-" + name);
    /// RouteLineTrimmer swaps their data between SwiftUI updates.
    static let routeSourceID = "atlas-route"
    static let routeTrafficSources: [(TrafficLine.Level, String)] = [
        (.slow, "atlas-traffic-route-slow"), (.heavy, "atlas-traffic-route-heavy"), (.stopped, "atlas-traffic-route-stopped"),
    ]

    /// By default as wide as the route's inner line, so a slow stretch reads as the route turning orange or red.
    private static func trafficLayer(
        _ name: String,
        _ lines: [[CLLocationCoordinate2D]],
        _ color: UIColor,
        widths: [Int: Double] = [10: 3.5, 14: 6, 18: 13]
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

    private static let routeLabelLayers: Set<String> = ["atlas-route-label-0", "atlas-route-label-1", "atlas-route-label-2"]
    private static let resultsLayerID = "atlas-results"
    private static let resultNamesLayerID = "atlas-result-names"
    /// What a tap can hit: the route callouts, the place badges and the search results' pins.
    private static let tapLayers: Set<String> = routeLabelLayers.union(
        MapLayerID.places + [BusinessOverlay.layerID, resultsLayerID, resultNamesLayerID]
    )

    private static func routeLabelLayer(_ slot: Int, _ label: RouteLabel, night: Bool) -> some StyleLayerDefinition {
        let source = ShapeSource(identifier: "atlas-route-label-\(slot)") {
            MLNPointFeature(coordinate: label.coordinate) { $0.attributes = ["route": label.route] }
        }
        return SymbolStyleLayer(identifier: "atlas-route-label-\(slot)", source: source)
            .iconImage(RouteLabel.bubble(label, night: night))
            .iconAnchor("bottom")
            .iconAllowsOverlap(true)
    }

    /// The destination as Apple Maps and Yandex mark it: a red drop with a white rim and dot, its tip on the place
    /// (bottom-anchored). A plain dot covered the place's own icon and label.
    private static let destinationPin = drop(destinationColor, radius: 14, dot: 11)
    /// A search result: the same drop, smaller and in the app's blue, so the chosen place stands out in red.
    private static let resultPin = drop(POIIcons.rgb(0x1F6FEB), radius: 10, dot: 7)
    /// A stop on the way: the drop in orange, a little smaller than the destination's.
    private static let stopPin = drop(POIIcons.rgb(0xFF9500), radius: 12, dot: 9)
    private static let resultTextDay = POIIcons.rgb(0x2C2C2E)
    private static let resultTextNight = POIIcons.rgb(0xEEF1F6)

    /// A drop: a circle of `radius` running down to a tip as far below it, with a white rim and a white dot.
    private static func drop(_ color: UIColor, radius: CGFloat, dot: CGFloat) -> UIImage {
        let margin: CGFloat = 3, tipBelowCircle = radius
        let size = CGSize(width: radius * 2 + margin * 2, height: radius * 2 + tipBelowCircle + margin * 2)
        return UIGraphicsImageRenderer(size: size).image { context in
            let center = CGPoint(x: size.width / 2, y: margin + radius)
            let tip = CGPoint(x: size.width / 2, y: size.height - margin)
            // The sides run from the tip to where they touch the circle.
            let touch = acos(radius / (tip.y - center.y))
            let drop = UIBezierPath(arcCenter: center, radius: radius, startAngle: .pi / 2 + touch, endAngle: .pi / 2 - touch, clockwise: true)
            drop.addLine(to: tip)
            drop.close()
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            color.setFill()
            drop.fill()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            UIColor.white.setStroke()
            drop.lineWidth = 2
            drop.stroke()
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)).fill()
        }
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

    /// The driver's own bump marks.
    private static let bumpMark = UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1)
    private static let destinationColor = UIColor(Color.atlasCritical)
    private static let routeColor = UIColor(Color.atlasAccent)
    private static let routeCasingNight = UIColor(red: 0.04, green: 0.10, blue: 0.20, alpha: 1)
    /// Darker than the route blue, so the white arrow stands out on it and beside it.
    private static let maneuverCasing = UIColor(red: 0.03, green: 0.22, blue: 0.55, alpha: 1)
    private static let alternativeDay = UIColor(red: 0.33, green: 0.47, blue: 0.72, alpha: 1)
    private static let alternativeNight = UIColor(red: 0.36, green: 0.47, blue: 0.69, alpha: 1)

    private static let puckStyle = MapUserAnnotationStyle(
        approximateHaloBorderColor: .atlasAccent,
        approximateHaloFillColor: .atlasAccent,
        haloFillColor: .atlasAccent,
        puckArrowFillColor: .atlasAccent,
        puckFillColor: .atlasAccent
    )
}

/// The car while the map follows it in guidance: a large two-tone arrowhead with a white rim, laid back like
/// the tilted map so it reads as lying on the road. MapLibre's own puck for this mode is a 22 pt arrow in a
/// white disc with no size or shape setting; it is hidden while this shows.
private struct GuidanceCursor: View {
    private static let light = Color(red: 0.30, green: 0.62, blue: 1)
    private static let dark = Color(red: 0.05, green: 0.33, blue: 0.82)

    var body: some View {
        ZStack {
            // Two facets, the right one in shade: the arrow reads as a solid shape, not a flat icon.
            ArrowHead(half: .left).fill(Self.light)
            ArrowHead(half: .right).fill(Self.dark)
            ArrowHead(half: nil).stroke(Color.white, style: StrokeStyle(lineWidth: 3.5, lineJoin: .round))
        }
        .frame(width: 50, height: 58)
        .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 4)
        .rotation3DEffect(.degrees(38), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
        .accessibilityHidden(true)
    }
}

/// A navigation arrowhead: tip up, notched base; one half of it for the two-tone fill.
private struct ArrowHead: Shape {
    enum Half { case left, right }

    let half: Half?

    func path(in rect: CGRect) -> Path {
        let tip = CGPoint(x: rect.midX, y: rect.minY)
        let notch = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.76)
        let left = CGPoint(x: rect.minX, y: rect.maxY)
        let right = CGPoint(x: rect.maxX, y: rect.maxY)
        var path = Path()
        path.move(to: tip)
        switch half {
        case .left?:
            path.addLine(to: notch)
            path.addLine(to: left)
        case .right?:
            path.addLine(to: right)
            path.addLine(to: notch)
        case nil:
            path.addLine(to: right)
            path.addLine(to: notch)
            path.addLine(to: left)
        }
        path.closeSubpath()
        return path
    }
}
