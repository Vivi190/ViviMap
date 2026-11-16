import AppCore
import CoreLocation
import DesignSystem
import Diagnostics
import LocationEngine
import MapEngine
import NavigationEngine
import RoadHazards
import RoutingEngine
import SearchEngine
import SwiftUI
import TrafficEngine
import TripHistory

enum Defaults {
    static var istanbul: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: 41.0082, longitude: 28.9784) }
}

/// Viewport values MapLibre reports on every frame. Kept out of HomeScreen's state so that only the views
/// reading them (the compass) re-render while the map moves.
@MainActor
@Observable
final class MapViewport {
    var bearing: Double = 0
    var zoom: Double = 15
    var pitch: Double = 0
    var center = Defaults.istanbul
    /// What the screen shows, snapped outward to 0.01° (~1 km) so a small move keeps the same value.
    var area: TrafficArea?
    /// What the screen shows, as it is. Not observed: it changes with every frame, and its one reader
    /// (BusinessLoader) asks for it when the map has come to rest.
    @ObservationIgnored var box: (west: Double, south: Double, east: Double, north: Double)?

    func update(from proxy: MapViewProxy) {
        if abs(proxy.direction - bearing) > 0.5 { bearing = proxy.direction }
        zoom = proxy.zoomLevel
        pitch = proxy.pitch
        center = proxy.centerCoordinate
        let box = proxy.visibleBox, step = 0.01
        self.box = box
        let visible = TrafficArea(
            west: (box.west / step).rounded(.down) * step,
            south: (box.south / step).rounded(.down) * step,
            east: (box.east / step).rounded(.up) * step,
            north: (box.north / step).rounded(.up) * step
        )
        if visible != area { area = visible }
    }
}

struct HomeScreen: View {
    enum Sheet: String, Identifiable {
        case search, mapSettings, diagnostics, attribution, stops
        var id: String { rawValue }
    }

    @Environment(AppSettings.self) private var settings
    @Environment(LocationProvider.self) private var location
    @Environment(UserHazardStore.self) private var userHazards
    @Environment(TripLog.self) private var trips
    @Environment(\.openURL) private var openURL
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var camera: MapViewCamera
    @State private var viewport = MapViewport()
    @State private var isNight: Bool
    @State private var is3D = false
    @State private var awaitingFirstFix: Bool
    @State private var sheet: Sheet?
    @State private var search = SearchController()
    @State private var selectedPlace: Place?
    /// Phone number and website of the place on the card, looked up in the business index when it changes.
    @State private var placeContact: OfflinePlaceIndex.Contact?
    /// The fees of an İSPARK car park on the card, asked for when it opens.
    @State private var placeFees: String?
    @State private var routes: [RouteOption] = []
    @State private var routeSelection = 0
    /// The driver chose a route by hand: traffic times arriving later must not move the selection.
    @State private var userPickedRoute = false
    /// MapLibre stopped following the car (a gesture or the route overview), as it reports itself. The camera
    /// binding misses gestures made while the map is still moving, which it always is behind a driving car.
    @State private var mapDetached = false
    /// Where each candidate's time bubble sits (RouteLabel.place), worked out once per route request.
    @State private var routeLabelPoints: [Int: CLLocationCoordinate2D] = [:]
    /// Routes to the place on the card, asked for as soon as the card opens (as Apple Maps does), so "Rota" shows
    /// the route card at once instead of after a server round trip.
    @State private var prefetch: RoutePrefetch?

    struct RoutePrefetch {
        let id: UUID
        let point: GeoPoint
        let origin: CLLocation
        let date: Date
        /// The route settings it was asked with: tolls avoided, ferries avoided.
        let preferences: [Bool]
        /// Done once `routes` is in (still nil then: the request failed). RouteOption is not Sendable, so the
        /// task hands its result over through this state rather than as its value.
        let task: Task<Void, Never>
        var routes: [RouteOption]?

        /// Still the routes the driver would get now: same place and setting, asked for moments ago from here.
        func fits(_ point: GeoPoint, from here: CLLocation, preferences: [Bool]) -> Bool {
            point == self.point && preferences == self.preferences
                && here.distance(from: origin) < 150 && Date.now.timeIntervalSince(date) < 120
        }
    }
    @State private var isPlanning = false
    @State private var routeError: String?
    @State private var simulator = DriveSimulator()
    /// Feeds the user puck during a simulated drive; nil = real GPS.
    @State private var simulatedPuck: StaticLocationManager?
    /// Starts the route line at the car on every fix while guiding (NavigationSession.onRouteAhead).
    @State private var routeTrimmer = RouteLineTrimmer()
    /// Draws the city traffic lines straight on the map style (TrafficOverlay).
    @State private var trafficOverlay = TrafficOverlay()
    /// Draws the search index's businesses as badges at street zoom (BusinessOverlay).
    @State private var businessOverlay = BusinessOverlay()
    /// The businesses in view, loaded where the map comes to rest (BusinessLoader).
    @State private var mapBusinesses: [MapBusiness] = []
    /// A search's results as pins on the map ("Haritada göster"), until taken off or guidance starts.
    @State private var resultPins: [Place] = []
    /// What they are, for the chip under the search bar: the query, with the place a list is around.
    @State private var resultsTitle = ""
    /// A later start chosen on the route card: the routes' times are then the traffic expected at that time.
    /// nil is now.
    @State private var departure: Date?
    /// The drive to Home and Work from here with live traffic, for their chips (ShortcutTimesLoader).
    @State private var shortcutTimes: [SearchController.Slot: TimeInterval] = [:]
    /// Feeds the user puck during real guidance with the fix snapped to the route (NavigationSession.onPuck).
    @State private var guidedPuck: StaticLocationManager?
    @State private var trafficEstimates: [Int: TrafficEstimate] = [:]
    @State private var trafficStatus = RouteCard.TrafficStatus.unavailable
    /// Slow stretches per route alternative, fetched for the one on screen.
    @State private var previewTraffic: [Int: [TrafficSection]] = [:]
    /// Traffic around each measured alternative, from the same answer: guidance opens with it on the map.
    @State private var previewAround: [Int: [TrafficSection]] = [:]
    /// Points on a closed stretch that an alternative's own flow showed on it once its time had been measured
    /// (RouteTraffic.closedPoints). The plan's imports are spent by then, so the card keeps the alternative and
    /// guidance takes the way round the stretch as soon as it starts on it.
    @State private var previewClosed: [Int: [CLLocationCoordinate2D]] = [:]
    /// Bumped per route request so a late traffic answer never lands on newer routes.
    @State private var planGeneration = 0
    @State private var trafficWatch = TrafficWatch()
    @State private var connectivity = Connectivity()
    @State private var cityTraffic = CityTraffic()
    /// Kept across drives, like the system's own navigation mute.
    @State private var isMuted = false
    /// Returns a guided map to the car after the driver looked around (see `.onChange(of: camera)`).
    @State private var recenterTask: Task<Void, Never>?
    /// The guidance side buttons are on screen (a tap on the map shows them for a few seconds).
    @State private var showsGuidanceControls = false
    @State private var hideControlsTask: Task<Void, Never>?
    /// The 0.6 s between centring on the car and following it (recenterOnCourse): not "the driver moved the map".
    @State private var isRecentering = false
    @State private var guidanceActivity = GuidanceActivity()
    /// What the driver was told when a real (not simulated) drive started, for the trip log.
    @State private var tripStart: TripStart?

    struct TripStart {
        let date: Date
        let destination: String
        let distance: Double
        let predicted: TimeInterval
        let withTraffic: Bool
    }

    private let planner: RoutePlanner?
    private let navigation: NavigationSession?
    private let traffic: (any TrafficProvider)?
    private static let pitch3D: Double = 55

    init(
        startsTracking: Bool,
        initiallyNight: Bool,
        planner: RoutePlanner?,
        navigation: NavigationSession?,
        traffic: (any TrafficProvider)?
    ) {
        _camera = State(initialValue: startsTracking ? .trackUserLocation(zoom: 15.5) : .center(Defaults.istanbul, zoom: 10))
        _awaitingFirstFix = State(initialValue: !startsTracking)
        _isNight = State(initialValue: initiallyNight)
        self.planner = planner
        self.navigation = navigation
        self.traffic = traffic
    }

    private var activeRoute: RouteOption? {
        routes.isEmpty ? nil : routes[min(routeSelection, routes.count - 1)]
    }

    private var isNavigating: Bool { navigation?.isActive == true }

    // swiftui-dsl registers a map gesture once, when the map appears, with the closure from that first render:
    // returning nil while guiding never reached it, and a long press mid-drive replaced the destination (trip
    // log, arrival sharing, parking). So the closure itself checks, when the press happens.
    private var longPressHandler: (CLLocationCoordinate2D) -> Void {
        { coordinate in
            if navigation?.isActive != true { pick(coordinate) }
        }
    }

    /// A place badge of the map was tapped. Not while guiding, and not while routes are on screen: there a
    /// stray tap beside a route would replace the destination being chosen (a long press still does, on purpose).
    private var placeTapHandler: (MapPlace) -> Void {
        { badge in
            if navigation?.isActive != true, routes.isEmpty, !isPlanning { pick(badge) }
        }
    }

    private var routeTapHandler: (Int) -> Void {
        { index in
            guard navigation?.isActive != true else { return }
            routeSelection = index
            userPickedRoute = true
        }
    }

    private var startHandler: (() -> Void)? {
        if navigation == nil { return nil }
        return { startNavigation(simulated: false) }
    }

    private var simulateHandler: (() -> Void)? {
        if navigation == nil || !settings.showsDriveSimulation { return nil }
        return { startNavigation(simulated: true) }
    }

    /// The route guidance is on, nil when not guiding: the traffic watch restarts with it (start, reroute,
    /// accepted suggestion).
    private var guidanceRoute: TrafficWatch.RouteKey? {
        guard isNavigating, let coordinates = navigation?.routeCoordinates, coordinates.count > 1 else { return nil }
        return TrafficWatch.RouteKey(coordinates)
    }

    /// During guidance the session's geometry wins: it changes after a reroute (read for that, so a reroute redraws
    /// the map), drawn from the car on (routeAhead, not observed; RouteLineTrimmer moves it between redraws).
    private var displayedRoute: [CLLocationCoordinate2D] {
        if isNavigating, let navigation, navigation.routeCoordinates.count > 1 {
            return navigation.routeAhead.count > 1 ? navigation.routeAhead : navigation.routeCoordinates
        }
        return activeRoute?.coordinates ?? []
    }

    /// The "Trafik" layer: switched on, a HERE key in this build, online, and not while guiding (the route
    /// carries its own colours then).
    private var showsCityTraffic: Bool {
        settings.showsTrafficLayer && traffic != nil && connectivity.isOnline && !isNavigating
    }

    /// The other candidates while choosing a route; none while guiding.
    private var alternativeRoutes: [[CLLocationCoordinate2D]] {
        guard !isNavigating, let active = activeRoute else { return [] }
        return routes.filter { $0.index != active.index }.map(\.coordinates)
    }

    /// The candidates' callouts on the map while choosing: the chosen route's time and distance, the others'
    /// difference from it; tapping one (or a tile in the card) chooses that route.
    private var routeLabels: [RouteLabel] {
        guard !isNavigating, let active = activeRoute else { return [] }
        let chosen = RouteCard.time(of: active, traffic: trafficEstimates, status: trafficStatus)
        var labels: [RouteLabel] = []
        for option in routes {
            guard let point = routeLabelPoints[option.index] else { continue }
            let time = RouteCard.time(of: option, traffic: trafficEstimates, status: trafficStatus)
            if option.index == active.index {
                labels.append(RouteLabel(
                    route: option.index, coordinate: point,
                    text: Formatting.duration(seconds: time), detail: Formatting.distance(meters: option.distance), tone: .selected
                ))
            } else {
                let minutes = Int((abs(time - chosen) / 60).rounded())
                labels.append(RouteLabel(
                    route: option.index, coordinate: point,
                    text: "\(time < chosen ? "−" : "+")\(minutes) dk", tone: time < chosen ? .faster : .slower
                ))
            }
        }
        return labels
    }

    private var hazardKinds: Set<Hazard.Kind> {
        var kinds: Set<Hazard.Kind> = []
        if settings.warnsCameras { kinds.insert(.camera) }
        if settings.warnsBumps { kinds.insert(.bump) }
        return kinds
    }

    /// The traffic layer: the roads around what is on screen; while guiding, the roads around the rest of the
    /// route (from the guidance rounds, no request of its own), as Yandex keeps jams visible on the way.
    private var areaTraffic: [TrafficLine] {
        guard settings.showsTrafficLayer else { return [] }
        if isNavigating { return trafficWatch.around.map { TrafficLine($0) } }
        return showsCityTraffic ? cityTraffic.lines : []
    }

    /// The search results as pins: not while routes are on screen or guiding. The chosen one has the
    /// destination pin instead.
    private var displayedPins: [MapPin] {
        guard !isNavigating, routes.isEmpty else { return [] }
        return resultPins.filter { $0.id != selectedPlace?.id }.map {
            MapPin(id: $0.id, name: $0.name, coordinate: $0.point.coordinate)
        }
    }

    /// Live traffic is known for the route on screen; it is then drawn in traffic colours instead of blue.
    private var routeIsMeasured: Bool {
        if isNavigating { return trafficWatch.arrival != nil }
        return activeRoute.map { previewTraffic[$0.index] != nil } ?? false
    }

    private var displayedTraffic: [TrafficLine] {
        if isNavigating, let navigation { return Self.trafficAhead(trafficWatch.sections, on: navigation) }
        return (activeRoute.flatMap { previewTraffic[$0.index] } ?? []).map { TrafficLine($0) }
    }

    /// Closures, accidents and road works: all around with the "Trafik" layer; while guiding, the ones on the rest
    /// of the route as of the last traffic round (they come with its time, no request of their own), as Yandex
    /// shows road events on the way.
    private var displayedIncidents: [MapIncident] {
        if showsCityTraffic { return cityTraffic.incidents.map { MapIncident($0) } }
        guard isNavigating, settings.showsTrafficLayer else { return [] }
        return trafficWatch.events.map { MapIncident($0) }
    }

    /// While guiding, the slow stretches still ahead, cut at the car along the line it drives on, so none floats
    /// behind it once the line under it is gone (RouteLineTrimmer keeps them so between redraws).
    private static func trafficAhead(_ sections: [TrafficSection], on navigation: NavigationSession) -> [TrafficLine] {
        zip(sections, navigation.stretchesAhead(sections.map(\.coordinates))).compactMap { section, line in
            line.map { TrafficLine(section, coordinates: $0) }
        }
    }

    var body: some View {
        ZStack {
            AtlasMapView(
                camera: $camera,
                appearance: isNight ? .night : .day,
                // Flat while guiding: extruded buildings hide the route line in narrow streets (MapLibre depth-tests
                // lines against them whatever the layer order); the tilted camera stays.
                showsBuildings3D: is3D && !isNavigating,
                destination: selectedPlace?.point.coordinate,
                stops: isNavigating ? navigation?.stops.map(\.coordinate) ?? [] : [],
                route: displayedRoute,
                alternatives: alternativeRoutes,
                routeIsMeasured: routeIsMeasured,
                routeLabels: routeLabels,
                traffic: displayedTraffic,
                areaTraffic: areaTraffic,
                marks: userHazards.hazards.map { MapMark(isCamera: $0.kind == .camera, coordinate: $0.coordinate) },
                maneuverArrow: isNavigating ? navigation?.maneuverArrow ?? [] : [],
                roadMarks: Self.roadMarks,
                incidents: displayedIncidents,
                routeTrimmer: routeTrimmer,
                trafficOverlay: trafficOverlay,
                businesses: isNavigating ? [] : mapBusinesses,
                businessOverlay: businessOverlay,
                pins: displayedPins,
                puckSource: simulatedPuck ?? guidedPuck,
                isGuiding: isNavigating,
                guidanceZoom: isNavigating ? navigation?.guidanceZoom : nil,
                isOffline: !connectivity.isOnline,
                // Until arrival: afterwards the map goes back to live GPS and MapLibre's own puck.
                showsGuidanceCursor: isNavigating && navigation?.hasArrived != true,
                onFollowingChanged: followingHandler,
                onTap: mapTapHandler,
                onPlaceTap: placeTapHandler,
                onRouteTap: routeTapHandler,
                onLongPress: longPressHandler
            ) { proxy in
                viewport.update(from: proxy)
            }
            .ignoresSafeArea()

            if let navigation, navigation.isActive {
                navigationOverlay(navigation)
            } else {
                overlay
            }
            // Here rather than in the overlay: a request made while guiding must be seen (and dropped) then, not
            // fire when the overlay comes back after "Bitir".
            ShortcutListener(inbox: ShortcutInbox.shared, hasFix: location.hasFix) { openShortcut($0) }
        }
        .preferredColorScheme(isNight ? .dark : .light)
        .sensoryFeedback(.impact(weight: .medium), trigger: selectedPlace?.point)
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .environment(settings)
                .environment(location)
                .environment(userHazards)
                .environment(trips)
                .preferredColorScheme(isNight ? .dark : .light)
        }
        .task(id: settings.appearanceMode) {
            // Re-evaluated every minute; reads here are not observed, so GPS fixes don't re-render the screen.
            while !Task.isCancelled {
                let anchor = location.lastLocation?.coordinate ?? Defaults.istanbul
                let night = settings.appearanceMode.isNight(at: .now, latitude: anchor.latitude, longitude: anchor.longitude)
                if night != isNight { isNight = night }
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onAppear {
            search.origin = { [location] in location.lastLocation.map { GeoPoint($0.coordinate) } }
        }
        .task(id: guidanceRoute) { await watchTraffic() }
        .onChange(of: hazardKinds) { _, kinds in navigation?.hazardKinds = kinds }
        .onChange(of: navigation?.hasArrived) { _, arrived in
            if arrived == true {
                recordTrip(arrived: true)
                guidanceActivity.end()
                // Ferrostar keeps reporting the arrival fix once the trip is complete: back to live GPS so the
                // arrow follows the car to its parking space, and nothing keeps the screen or background GPS on
                // if the driver walks away without ending guidance.
                guidedPuck = nil
                location.setNavigating(false)
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
        .onChange(of: departure) { _, _ in
            // The same routes, measured again for the new start; a new generation drops answers for the old one.
            guard !routes.isEmpty, !isNavigating, let place = selectedPlace, let here = location.lastLocation else { return }
            planGeneration += 1
            scoreTraffic(routes, from: here, to: place, generation: planGeneration)
        }
        .onChange(of: routeSelection) { _, index in
            if let option = routes.first(where: { $0.index == index }) { loadFlow(for: option, generation: planGeneration) }
        }
        .onChange(of: location.hasFix) { _, hasFix in
            // First fix after a cold start: jump to the user unless they already moved the map.
            guard hasFix, awaitingFirstFix else { return }
            awaitingFirstFix = false
            if camera.trackingMode == .none, !userMovedMap, selectedPlace == nil {
                camera = .trackUserLocation(zoom: 15.5)
            }
        }
        .onChange(of: camera) { _, _ in scheduleReturn() }
        .onChange(of: mapDetached) { _, _ in scheduleReturn() }
        .onChange(of: selectedPlace) { _, place in
            placeContact = place.flatMap { OfflinePlaceIndex.businesses?.contact(of: $0) }
            placeFees = nil
            if let place, place.id.hasPrefix("ispark-") {
                Task {
                    let fees = await ISPARKCarParks().fees(of: place)
                    if selectedPlace?.id == place.id { placeFees = fees }
                }
            }
        }
        .onChange(of: [settings.avoidsTolls, settings.avoidsFerries]) { _, _ in
            // The routes (or the "no such route" message) on screen were planned with the old settings.
            if let place = selectedPlace, !isNavigating, !routes.isEmpty || routeError != nil { planRoute(to: place) }
        }
    }

    /// While guiding, a driver who moved the map or looked at the whole route gets the road ahead back by
    /// itself 12 s after the last change the map reports; every further gesture restarts the wait.
    private func scheduleReturn() {
        recenterTask?.cancel()
        guard isNavigating, mapDetached, let navigation else { return }
        recenterTask = Task {
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, isNavigating, mapDetached else { return }
            recenterOnCourse(zoom: navigation.guidanceZoom)
        }
    }

    /// MapLibre's own word on whether it follows the car (AtlasMapView.onFollowingChanged).
    private var followingHandler: (Bool) -> Void {
        { follows in
            if mapDetached == follows { mapDetached = !follows }
        }
    }

    // MARK: Overlay

    private var overlay: some View {
        VStack(spacing: Spacing.s) {
            HStack(alignment: .top, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SearchBarButton { sheet = .search }
                        .frame(maxWidth: isLandscape ? 420 : .infinity)
                    if selectedPlace == nil, search.home != nil || search.work != nil {
                        ShortcutChips(hasHome: search.home != nil, hasWork: search.work != nil, times: shortcutTimes) { slot in
                            if !openShortcut(slot), let place = slot == .home ? search.home : search.work {
                                select(place)
                                routeError = "Konumunuz henüz bilinmiyor."
                            }
                        }
                    }
                    if selectedPlace == nil, !resultPins.isEmpty {
                        ResultsChip(title: resultsTitle, count: resultPins.count, onList: { sheet = .search }, onClear: clearResults)
                    }
                    GPSStatusChip(openSettings: openSettings, showDiagnostics: { sheet = .diagnostics })
                    if !connectivity.isOnline { offlineChip }
                    if settings.showsTrafficLayer, let notice = cityTraffic.notice {
                        StatusChip(systemImage: "car.2.fill", title: notice, tone: .warning)
                    } else if showsCityTraffic, let score = cityTraffic.score {
                        // The roads around on a scale drivers know from Yandex, 0 clear … 10 gridlock
                        // (AreaTraffic.score); its badge turns yellow from 4 and red from 7.
                        StatusChip(
                            systemImage: "car.2.fill",
                            title: "\(score) puan · \(AreaTraffic.label(score: score))",
                            tone: score >= 7 ? .critical : score >= 4 ? .warning : .neutral
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(spacing: Spacing.m) {
                    controls
                    CompassButton(viewport: viewport, action: resetNorth)
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                SpeedOverlay()
                Spacer(minLength: 0)
                if selectedPlace == nil {
                    Button { sheet = .attribution } label: {
                        // Plain small print, as map apps do; still one tap from the full credits.
                        Text(showsCityTraffic ? "© OpenStreetMap · HERE" : "© OpenStreetMap")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.s)
                            .padding(.vertical, Spacing.xs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Harita kaynakları"))
                }
            }
            if let place = selectedPlace {
                Group {
                    if routes.isEmpty {
                        placeCard(place)
                    } else {
                        routeCard(place)
                    }
                }
                .frame(maxWidth: isLandscape ? 420 : .infinity)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.snappy(duration: 0.3), value: selectedPlace)
        .animation(.snappy(duration: 0.3), value: routes.isEmpty)
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        // In the background so they take no room in the layout.
        .background {
            if showsCityTraffic, let traffic {
                CityTrafficLoader(viewport: viewport, cityTraffic: cityTraffic, provider: traffic)
            }
            if !isNavigating, let index = OfflinePlaceIndex.businesses {
                BusinessLoader(viewport: viewport, index: index) { mapBusinesses = $0 }
            }
            if selectedPlace == nil, !isNavigating, connectivity.isOnline, let planner, let traffic,
               search.home != nil || search.work != nil {
                ShortcutTimesLoader(home: search.home, work: search.work, planner: planner, traffic: traffic) { shortcutTimes = $0 }
            }
        }
    }

    private var controls: some View {
        MapControlGroup {
            MapControlButton(systemImage: "map", label: "Harita ayarları") { sheet = .mapSettings }
            MapControlDivider()
            MapControlTextButton(title: is3D ? "2D" : "3D", label: "Üç boyutlu görünüm", isActive: is3D, action: toggle3D)
            if traffic != nil {
                MapControlDivider()
                MapControlButton(systemImage: "car.2.fill", label: "Trafik", isActive: settings.showsTrafficLayer) {
                    settings.showsTrafficLayer.toggle()
                }
            }
            MapControlDivider()
            MapControlButton(
                systemImage: locationSymbol,
                label: "Konumumu göster",
                isActive: camera.trackingMode != .none,
                action: locationTapped
            )
        }
        .sensoryFeedback(.selection, trigger: camera.trackingMode)
        .sensoryFeedback(.selection, trigger: is3D)
    }

    private var locationSymbol: String {
        switch camera.trackingMode {
        case .none: "location"
        case .follow: "location.fill"
        case .followDirection: "location.north.line.fill"
        }
    }

    private var userMovedMap: Bool {
        switch camera.lastReasonForChange {
        case .gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom, .gestureTilt:
            true
        default:
            false
        }
    }

    // MARK: Actions

    private func locationTapped() {
        guard location.isAuthorized else {
            if location.isDenied { openSettings() } else { location.start() }
            return
        }
        let isDriving = (location.speedReading(at: .now).kmh ?? 0) >= 15
        camera = camera.nextTrackingCamera(zoom: max(viewport.zoom, 15), pitch: is3D ? Self.pitch3D : 0, isDriving: isDriving)
    }

    private func toggle3D() {
        is3D.toggle()
        let pitch = is3D ? Self.pitch3D : 0
        // Extruded buildings start at z15, so entering 3D zooms in far enough to see them.
        let zoom = is3D ? max(viewport.zoom, 16) : viewport.zoom
        if camera.trackingMode == .none {
            camera = .center(viewport.center, zoom: zoom, pitch: pitch, direction: viewport.bearing)
        } else {
            camera = camera.retracked(zoom: zoom, pitch: pitch)
        }
    }

    private func resetNorth() {
        if camera.trackingMode == .followDirection {
            camera = .trackUserLocation(zoom: viewport.zoom, pitch: viewport.pitch)
        } else if camera.trackingMode == .follow {
            camera.setDirection(0)
        } else {
            camera = .center(viewport.center, zoom: viewport.zoom, pitch: viewport.pitch, direction: 0)
        }
    }

    private func select(_ place: Place) {
        // Picked from another search than the one on the map: its pins are done with.
        if !resultPins.contains(where: { $0.id == place.id }) {
            resultPins = []
            resultsTitle = ""
        }
        search.remember(place)
        show(place)
        camera = .center(place.point.coordinate, zoom: max(viewport.zoom, 16), pitch: is3D ? Self.pitch3D : 0)
    }

    /// Siri / Shortcuts "Eve git", "İşe git": straight to the route card, as the search sheet's shortcut does.
    /// Nothing saved yet: the search sheet, where its menu offers "Ev olarak kaydet".
    /// Returns false to be asked again when the first fix arrives.
    private func openShortcut(_ slot: SearchController.Slot) -> Bool {
        // Not while guiding: it would take the driver off the guidance they follow. Dropped, not kept.
        guard !isNavigating else { return true }
        guard let place = slot == .home ? search.home : search.work else {
            sheet = .search
            return true
        }
        // Planning needs a fix; a cold start from Siri has none for a moment.
        guard location.lastLocation != nil else { return false }
        sheet = nil
        select(place)
        planRoute(to: place)
        return true
    }

    /// Long press on the map: drop a pin there (address filled in when Photon knows it).
    /// Not added to recents and the camera stays put.
    private func pick(_ coordinate: CLLocationCoordinate2D) {
        let point = GeoPoint(coordinate)
        show(Place(id: "picked", name: "Seçilen konum", subtitle: "Adres aranıyor…", point: point, category: nil))
        Task {
            let place = await search.place(at: point)
            if selectedPlace?.point == point { selectedPlace = place }
        }
    }

    /// The card opens at once with the name the map shows; address, kind and area follow from the search
    /// service. An area (a mall, a hospital) changes where the route should end, so its routes are asked again.
    private func pick(_ badge: MapPlace) {
        // A search result's pin: the place as the search found it; the map stays where it is.
        if let id = badge.id, let place = resultPins.first(where: { $0.id == id }) {
            search.remember(place)
            show(place)
            return
        }
        // One of the index's own businesses: its record is on the device, address included.
        if let id = badge.id, let place = OfflinePlaceIndex.businesses?.place(id: id) {
            show(place)
            return
        }
        let point = GeoPoint(badge.coordinate)
        let category = PlaceSymbol.category(mapKind: badge.kind, mapGroup: badge.group)
        show(Place(id: "map", name: badge.name, subtitle: "Adres aranıyor…", point: point, category: category))
        Task {
            let place = await search.place(named: badge.name, category: category, at: point)
            guard selectedPlace?.point == point else { return }
            selectedPlace = place
            if place.areaSpan != nil, routes.isEmpty, !isPlanning { prefetchRoutes(to: place) }
        }
    }

    private func show(_ place: Place) {
        routes = []
        routeError = nil
        // Routes still coming for the previous place must not land on this one's card.
        planGeneration += 1
        isPlanning = false
        selectedPlace = place
        sheet = nil
        departure = nil
        // The closed roads found on the way to the last place say nothing about the way to this one.
        planner?.closedRoads = []
        prefetchRoutes(to: place)
    }

    private func prefetchRoutes(to place: Place) {
        prefetch?.task.cancel()
        prefetch = nil
        guard let planner, let here = location.lastLocation else { return }
        planner.avoidsTolls = settings.avoidsTolls
        planner.avoidsFerries = settings.avoidsFerries
        let id = UUID()
        let task = Task {
            let found = try? await planner.plan(from: here, to: place)
            if prefetch?.id == id { prefetch?.routes = found }
        }
        prefetch = RoutePrefetch(id: id, point: place.point, origin: here, date: .now, preferences: [settings.avoidsTolls, settings.avoidsFerries], task: task)
    }

    private func placeCard(_ place: Place) -> some View {
        PlaceCard(
            place: place,
            contact: placeContact,
            fees: placeFees,
            // The fastest of the routes asked for when the card opened, once they are in.
            drivingTime: prefetch.flatMap { $0.point == place.point ? $0.routes?.map(\.duration).min() : nil },
            // Not while its address is still being looked up: the place has no identity of its own yet.
            isSaved: ["map", "picked"].contains(place.id) ? nil : search.isSaved(place),
            onToggleSaved: { search.toggleSaved(place) },
            isPlanning: isPlanning,
            error: routeError,
            onRoute: { planRoute(to: place) },
            onSave: { search.save(place, as: $0) },
            onMark: { userHazards.mark($0, latitude: place.point.latitude, longitude: place.point.longitude) },
            onParking: search.canShowNearby ? {
                search.showNearby(.parking, around: place)
                sheet = .search
            } : nil,
            onClose: { clearPlace() }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func routeCard(_ place: Place) -> some View {
        RouteCard(
            place: place,
            routes: routes,
            traffic: trafficEstimates,
            trafficStatus: trafficStatus,
            // What these routes were planned with; the switch may have moved since (re-planning clears them).
            avoidsTolls: planner?.avoidsTolls == true,
            error: routeError,
            departure: $departure,
            selection: Binding(
                get: { routeSelection },
                set: { index in
                    routeSelection = index
                    userPickedRoute = true
                }
            ),
            onStart: startHandler,
            onSimulate: simulateHandler,
            onClose: {
                routes = []
                camera = .center(place.point.coordinate, zoom: 16, pitch: is3D ? Self.pitch3D : 0)
            }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// What still works without a connection: with the shipped Istanbul packages, map and routes; without
    /// them, only what MapLibre happens to have cached.
    private var offlineChip: some View {
        StatusChip(
            systemImage: "wifi.slash",
            title: OfflineMap.packages == nil ? "İnternet yok" : "İnternet yok · çevrimdışı harita",
            tone: .warning
        )
        .accessibilityIdentifier("offline.chip")
    }

    /// iPhone on its side (car mounts): panels move into a left column and the map gets the rest.
    private var isLandscape: Bool { verticalSizeClass == .compact }

    /// Sound, places on the way and sharing, out of the way while driving: shown for a few seconds after a tap on
    /// the map and while the map is not following the car. The overview button is in the bottom strip; the way
    /// back to the car ("Rotaya devam et") appears above it.
    private func navigationControls(_ navigation: NavigationSession) -> some View {
        MapControlGroup {
            MapControlButton(
                systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: isMuted ? "Sesli yönlendirmeyi aç" : "Sesli yönlendirmeyi kapat",
                isActive: isMuted
            ) {
                isMuted.toggle()
                navigation.voice.isMuted = isMuted
            }
            // The shipped indexes answer it; builds without them have nothing to search.
            if search.canShowNearby, !navigation.hasArrived {
                MapControlDivider()
                MapControlButton(systemImage: "magnifyingglass", label: "Yol üstünde ara") { sheet = .stops }
            }
            ArrivalShareButton(navigation: navigation, place: selectedPlace, trafficArrival: trafficWatch.arrival)
        }
    }

    private func navigationOverlay(_ navigation: NavigationSession) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            navigationColumn(navigation)
                .frame(maxWidth: isLandscape ? 380 : .infinity)
                // Its full width before the spacer gets any: the corner beside it would otherwise halve it.
                .layoutPriority(1)
            if isLandscape {
                // On its side the phone has the far right for these; upright they sit in the column's top row.
                Spacer(minLength: 0)
                guidanceCorner(navigation)
            }
        }
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .animation(.snappy(duration: 0.3), value: trafficWatch.suggestion?.option.id)
        .animation(.easeOut(duration: 0.2), value: showsGuidanceControls || mapDetached)
    }

    /// Top right while guiding: speed and limit, and under them sound and sharing while they are called for.
    private func guidanceCorner(_ navigation: NavigationSession) -> some View {
        VStack(alignment: .trailing, spacing: Spacing.m) {
            GuidanceSpeed(navigation: navigation)
            if showsGuidanceControls || mapDetached {
                navigationControls(navigation)
                    .transition(.opacity)
            }
        }
    }

    /// Guidance, laid out as drivers know it from Yandex Navigator: the turn panel top left, speed and limit top
    /// right, the road name over one slim trip row at the bottom; the middle stays map.
    private func navigationColumn(_ navigation: NavigationSession) -> some View {
        VStack(spacing: Spacing.s) {
            HStack(alignment: .top, spacing: Spacing.s) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    NavigationBanner(navigation: navigation)
                    HazardChipSlot(navigation: navigation)
                    // A tunnel or weak signal must read as "no GPS", not as a frozen app.
                    GPSStatusChip(openSettings: openSettings, showDiagnostics: { sheet = .diagnostics })
                    if !connectivity.isOnline { offlineChip }
                    if simulatedPuck != nil {
                        // Always visible: a simulated drive must never pass for real guidance.
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(Color.atlasWarning)
                            Text("Simülasyon")
                        }
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, Spacing.m)
                            .padding(.vertical, Spacing.s)
                            .atlasFloatingSurface(in: Capsule())
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("nav.simulation")
                    }
                }
                Spacer(minLength: 0)
                if !isLandscape { guidanceCorner(navigation) }
            }
            if let suggestion = trafficWatch.suggestion {
                RouteSuggestionBanner(suggestion: suggestion, onAccept: acceptSuggestion) { trafficWatch.dismiss() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
            GuidanceRoadRow(navigation: navigation, isDetached: mapDetached && !isRecentering) {
                recenterOnCourse(zoom: navigation.guidanceZoom)
            }
            NavigationBottomBar(
                navigation: navigation,
                trafficArrival: trafficWatch.arrival,
                onParking: search.canShowNearby ? { findParking() } : nil,
                trafficSections: trafficWatch.sections,
                isOverview: mapDetached,
                onOverview: { showRouteOverview(navigation) },
                onEnd: { endNavigation() }
            )
        }
    }

    /// A tap on the map while guiding: the side buttons for six seconds.
    private var mapTapHandler: () -> Void {
        {
            guard navigation?.isActive == true else { return }
            showsGuidanceControls = true
            hideControlsTask?.cancel()
            hideControlsTask = Task {
                try? await Task.sleep(for: .seconds(6))
                if !Task.isCancelled { showsGuidanceControls = false }
            }
        }
    }

    /// Traffic rounds while guiding; the task is cancelled when navigation ends (its id changes).
    private func watchTraffic() async {
        guard isNavigating, let traffic, let planner, let navigation, let destination = selectedPlace,
              navigation.routeCoordinates.count > 1 else { return }
        // A route the card or an accepted suggestion already measured: next look in a full interval. One
        // nothing is known about (a reroute, or traffic failed on the card): soon.
        var wait: Duration = trafficWatch.follows(navigation.routeCoordinates) ? TrafficWatch.interval : .seconds(10)
        // A closed stretch the route card found on this route: the way round it is not left for a round's time.
        let next = wait
        if trafficWatch.hasKnownClosure { wait = .seconds(1) }
        while !Task.isCancelled {
            try? await Task.sleep(for: wait)
            // After the look at a known closure, the round this route was due anyway.
            wait = wait == .seconds(1) ? next : TrafficWatch.interval
            guard !Task.isCancelled, let position = location.lastLocation else { continue }
            let detour = await trafficWatch.check(
                navigation: navigation, planner: planner, traffic: traffic, position: position, destination: destination
            )
            // Guidance moved round a closed road: a simulated drive continues along the new route from here.
            if let detour, simulatedPuck != nil { simulate(detour, from: position) }
        }
    }

    private func acceptSuggestion() {
        guard let navigation, let position = location.lastLocation,
              let option = trafficWatch.accept(navigation: navigation, from: position) else { return }
        // A simulated drive continues along the new route from here.
        if simulatedPuck != nil { simulate(option, from: position) }
    }

    /// "Yol üstünde ara": guidance moves, without ending, onto a route from the car through `stop` to the
    /// destination; nil drops the stop and leads straight there again.
    private func routeVia(_ stop: Place?) {
        sheet = nil
        guard let navigation, let planner, let destination = selectedPlace, let position = location.lastLocation else { return }
        Task {
            do {
                // The device first, as for any new route while driving: the car moves on while the server answers.
                guard let option = try await planner.routes(
                    from: position, via: stop.map { [$0.point] } ?? [], to: destination.point,
                    areaSpan: destination.areaSpan, deviceFirst: true
                ).first, navigation.isActive else { return }
                try navigation.switchRoute(to: option, from: position, announcing: stop == nil ? "Ara durak kaldırıldı." : "Ara durak eklendi.")
                if simulatedPuck != nil { simulate(option, from: position) }
            } catch {
                if navigation.isActive { navigation.voice.speak(stop == nil ? "Ara durak kaldırılamadı." : "Ara durağa rota bulunamadı.") }
            }
        }
    }

    private func startNavigation(simulated: Bool) {
        guard let navigation, let route = activeRoute else { return }
        // A simulated drive starts on the route itself; real guidance starts from the GPS fix.
        let start = simulated
            ? route.coordinates.first.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
            : location.lastLocation
        guard let start else {
            routeError = "Konumunuz henüz bilinmiyor."
            return
        }
        // What the route card showed for this route: the spoken start, the bar and the lock screen open with
        // the same time and colours instead of the free-flow ones until the first traffic round.
        let estimate = trafficStatus == .ready && departure == nil ? trafficEstimates[route.index] : nil
        do {
            navigation.hazardKinds = hazardKinds
            navigation.userHazards = userHazards.hazards
            navigation.warnsSpeeding = settings.warnsSpeeding
            navigation.speedingMargin = settings.speedingMargin
            navigation.speaksTurns = settings.speaksTurns
            navigation.voice.isMuted = isMuted
            try navigation.start(route, from: start, expectedDuration: estimate?.duration)
            // The drive has its destination: the other results are done with.
            resultPins = []
            resultsTitle = ""
            // The speed limits that came with this route's times (shown where OpenStreetMap has none) and the
            // road events on it (said once each on the way).
            navigation.setSpeedLimits((estimate?.limits ?? []).map { RouteSpeedLimit($0) })
            navigation.setRoadEvents((estimate?.events ?? []).compactMap { RoadEvent($0) })
            trafficWatch.begin(
                on: route.coordinates, duration: estimate?.duration,
                sections: previewTraffic[route.index] ?? [], around: previewAround[route.index] ?? [],
                events: estimate?.events ?? [], closed: previewClosed[route.index] ?? []
            )
            navigation.onRouteAhead = { [routeTrimmer, trafficWatch, weak navigation] ahead in
                guard let navigation else { return }
                routeTrimmer.show(ahead, traffic: Self.trafficAhead(trafficWatch.sections, on: navigation))
            }
            location.setNavigating(true)
            // The screen stays on while guiding (it can still be locked by hand; guidance continues).
            UIApplication.shared.isIdleTimerDisabled = true
            if simulated {
                simulate(route, from: start)
            } else {
                let puck = StaticLocationManager(initialLocation: start)
                guidedPuck = puck
                navigation.onPuck = { puck.lastLocation = $0 }
                if let place = selectedPlace {
                    tripStart = TripStart(
                        date: .now, destination: place.name, distance: route.distance,
                        predicted: estimate?.duration ?? route.duration, withTraffic: estimate != nil
                    )
                }
            }
            recenterOnCourse(zoom: navigation.guidanceZoom)
            guidanceActivity.start(
                destination: selectedPlace?.name ?? "Hedef",
                navigation: navigation,
                traffic: trafficWatch,
                arrival: Date.now.addingTimeInterval(estimate?.duration ?? route.duration)
            )
        } catch {
            routeError = "Navigasyon başlatılamadı."
        }
    }

    /// Start and "Konumumu göster": onto the last fix first, then follow. swiftui-dsl sets the zoom right after
    /// the tracking mode, which cuts MapLibre's own fly-to short, so the map stayed where it was until the next
    /// fix and guidance opened on the route preview's centre instead of the car.
    private func recenterOnCourse(zoom: Double) {
        // Set here as well as by the map's own report (followingHandler): the button must not wait for it.
        mapDetached = false
        guard let here = (simulatedPuck ?? guidedPuck)?.lastLocation ?? location.lastLocation else { return followCourse(zoom: zoom) }
        let direction = settings.guidesNorthUp ? 0 : here.course >= 0 ? here.course : viewport.bearing
        isRecentering = true
        camera = .center(here.coordinate, zoom: zoom, pitch: settings.guidesNorthUp ? 0 : Self.pitch3D, direction: direction)
        // After MapLibre's 0.3 s centre and pitch animations; following earlier would cut them short too.
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if isNavigating { followCourse(zoom: zoom) }
            isRecentering = false
        }
    }

    private func followCourse(zoom: Double) {
        // North up: flat and following the car without turning, as the driver chose in the settings.
        camera = settings.guidesNorthUp
            ? .trackUserLocation(zoom: zoom, pitch: 0, pitchRange: .fixed(0))
            : .trackUserLocationWithCourse(zoom: zoom, pitch: Self.pitch3D, pitchRange: .fixed(Self.pitch3D))
    }

    /// The whole rest of the route, framed between the banner and the bottom bar; "Konumumu göster" returns.
    private func showRouteOverview(_ navigation: NavigationSession) {
        let rest = navigation.remainingRoute()
        guard rest.count > 1 else { return }
        let lats = rest.map(\.latitude), lons = rest.map(\.longitude)
        // MapLibre adds this padding to the guidance content inset, which already keeps the top 40 % (turn card)
        // clear: a 230 pt top padding left the route about 60 pt of map and zoomed out to half the city.
        camera = .fitting(
            southWest: CLLocationCoordinate2D(latitude: lats.min()!, longitude: lons.min()!),
            northEast: CLLocationCoordinate2D(latitude: lats.max()!, longitude: lons.max()!),
            padding: isLandscape
                ? UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 70)
                : UIEdgeInsets(top: 40, left: 40, bottom: 210, right: 70)
        )
        mapDetached = true
    }

    /// Drives the route at the average speed Valhalla assumed, so the simulated arrival matches the estimate.
    /// Fixes go to the puck and through LocationProvider, i.e. the same path as GPS (speedometer, guidance).
    private func simulate(_ route: RouteOption, from start: CLLocation) {
        let puck = simulatedPuck ?? StaticLocationManager(initialLocation: start)
        simulatedPuck = puck
        simulator.start(along: route.coordinates, speed: route.distance / max(route.duration, 1)) { [location] fix in
            puck.lastLocation = fix
            location.simulate(fix)
        }
    }

    /// Logged at arrival (so a late tap on "Bitir" does not lengthen the drive) or when ended on the way.
    /// The arrival time comes from the session: with the screen locked this may run only on unlock.
    private func recordTrip(arrived: Bool) {
        guard let start = tripStart else { return }
        tripStart = nil
        let end = arrived ? navigation?.arrivedAt ?? .now : .now
        trips.record(Trip(
            startedAt: start.date, endedAt: end, destination: start.destination, distance: start.distance,
            predicted: start.predicted, predictedWithTraffic: start.withTraffic, arrived: arrived
        ))
    }

    private func endNavigation() {
        recordTrip(arrived: false)
        guidanceActivity.end()
        simulator.stop()
        trafficWatch.reset()
        if simulatedPuck != nil {
            simulatedPuck = nil
            location.endSimulation()
        }
        navigation?.stop()
        guidedPuck = nil
        location.setNavigating(false)
        UIApplication.shared.isIdleTimerDisabled = false
        clearPlace()
        is3D = false
        camera = .trackUserLocation(zoom: 15.5, pitch: 0, pitchRange: .fixed(0))
    }

    /// "Otopark" on arrival: guidance ends and the car parks around the destination are listed.
    private func findParking() {
        let destination = selectedPlace
        endNavigation()
        guard let destination else { return }
        search.showNearby(.parking, around: destination)
        sheet = .search
    }

    /// Bundled OSM bumps, cameras and traffic lights drawn on the map, read once.
    private static let roadMarks: RoadMarks = {
        let hazards = HazardCatalog.bundled()?.hazards ?? []
        let points = { (kind: Hazard.Kind) in
            hazards.filter { $0.kind == kind }.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
        return RoadMarks(bumps: points(.bump), cameras: points(.camera), lights: TrafficSignals.bundled)
    }()

    private func clearPlace() {
        selectedPlace = nil
        departure = nil
        routes = []
        routeError = nil
        // Routes still coming would draw lines with no card under them.
        planGeneration += 1
        isPlanning = false
        prefetch?.task.cancel()
        prefetch = nil
        planner?.closedRoads = []
        // Done with this place: the next search opens on recents, shortcuts and "Yakında", not the old results.
        // Unless those are on the map: the chip opens their list again.
        if resultPins.isEmpty { search.query = "" }
    }

    /// "Haritada göster" in the search sheet: the results as pins, all of them in view.
    private func showOnMap(_ places: [Place]) {
        guard !places.isEmpty else { return }
        resultsTitle = search.nearbyCenter.map { "\(search.query) · \($0.name)" } ?? search.query
        resultPins = places
        // A place on screen before is put away, and with the pins on the map the query stays for the chip.
        clearPlace()
        sheet = nil
        let latitudes = places.map(\.point.latitude), longitudes = places.map(\.point.longitude)
        camera = .fitting(
            southWest: CLLocationCoordinate2D(latitude: latitudes.min()!, longitude: longitudes.min()!),
            northEast: CLLocationCoordinate2D(latitude: latitudes.max()!, longitude: longitudes.max()!),
            padding: isLandscape
                ? UIEdgeInsets(top: 40, left: 450, bottom: 40, right: 90)
                : UIEdgeInsets(top: 230, left: 50, bottom: 140, right: 90)
        )
    }

    private func clearResults() {
        resultPins = []
        resultsTitle = ""
        search.query = ""
    }

    private func planRoute(to place: Place) {
        guard let planner else {
            routeError = "Rota servisi başlatılamadı."
            return
        }
        guard let here = location.lastLocation else {
            routeError = "Konumunuz henüz bilinmiyor."
            return
        }
        isPlanning = true
        routeError = nil
        planGeneration += 1
        let generation = planGeneration
        planner.avoidsTolls = settings.avoidsTolls
        planner.avoidsFerries = settings.avoidsFerries
        let pending = prefetch.flatMap { $0.fits(place.point, from: here, preferences: [planner.avoidsTolls, planner.avoidsFerries]) ? $0 : nil }
        Task {
            do {
                // The routes asked for when the card opened; a fresh request only if that one failed.
                var ready: [RouteOption]?
                if let pending {
                    await pending.task.value
                    if prefetch?.id == pending.id { ready = prefetch?.routes }
                }
                guard generation == planGeneration else { return }
                let found: [RouteOption]
                if let ready {
                    found = ready
                } else {
                    found = try await planner.plan(from: here, to: place)
                }
                guard generation == planGeneration else { return }
                routeSelection = 0
                userPickedRoute = false
                routeLabelPoints = Self.labelPoints(found)
                routes = found
                scoreTraffic(found, from: here, to: place, generation: generation)
                // Every candidate in view: the alternatives are drawn too.
                if !found.isEmpty {
                    camera = .fitting(
                        southWest: CLLocationCoordinate2D(
                            latitude: found.map(\.southWest.latitude).min()!,
                            longitude: found.map(\.southWest.longitude).min()!
                        ),
                        northEast: CLLocationCoordinate2D(
                            latitude: found.map(\.northEast.latitude).max()!,
                            longitude: found.map(\.northEast.longitude).max()!
                        ),
                        padding: isLandscape
                            ? UIEdgeInsets(top: 30, left: 450, bottom: 30, right: 80)
                            : UIEdgeInsets(top: 150, left: 50, bottom: 380, right: 90)
                    )
                }
            } catch RoutePlanner.PlanningError.noRoute where planner.avoidsTolls || planner.avoidsFerries {
                // "No path" here usually means none without tolls or ferries, not a closed-off destination.
                if generation == planGeneration {
                    routeError = planner.avoidsTolls && planner.avoidsFerries
                        ? "Ücretli yol ve feribot kullanmadan bu hedefe rota bulunamadı. Harita ayarları → Rota'dan birini kapatmayı deneyin."
                        : planner.avoidsTolls
                        ? "Ücretli yollardan kaçınan bir rota bulunamadı. Harita ayarları → Rota'dan kapatmayı deneyin."
                        : "Feribot kullanmayan bir rota bulunamadı. Harita ayarları → Rota'dan kapatmayı deneyin."
                }
            } catch {
                if generation == planGeneration { routeError = error.localizedDescription }
            }
            if generation == planGeneration { isPlanning = false }
        }
    }

    /// Where each candidate's time bubble sits on the map: on its own line, away from the others'.
    private static func labelPoints(_ options: [RouteOption]) -> [Int: CLLocationCoordinate2D] {
        Dictionary(uniqueKeysWithValues: options.compactMap { option in
            RouteLabel.place(on: option.coordinates, awayFrom: options.filter { $0.index != option.index }.map(\.coordinates))
                .map { (option.index, $0) }
        })
    }

    /// Measures every candidate with the one traffic provider (ADR-5) and preselects the fastest. Shown only
    /// when all of them were measured: mixing traffic and free-flow times would compare different scales.
    /// Before that, a candidate that runs through a closed stretch is replaced by a way round it
    /// (`avoidingClosures`), so that each of the plan's imports, three at most, measures a route that can be driven.
    private func scoreTraffic(_ options: [RouteOption], from origin: CLLocation, to place: Place, generation: Int) {
        trafficEstimates = [:]
        previewTraffic = [:]
        previewAround = [:]
        previewClosed = [:]
        // A route computed on the device (no connection, or the server failing) is labelled "trafiksiz":
        // scoring it would put a live-traffic time next to that label and spend the budget for nothing.
        guard let traffic, options.first?.isOffline != true else {
            trafficStatus = .unavailable
            return
        }
        trafficStatus = .loading
        let departure = departure
        Task {
            // The roads closed now, and the colours of now, say nothing about a later start.
            var candidates = options
            if departure == nil {
                candidates = await avoidingClosures(in: options, from: origin, to: place, traffic: traffic, generation: generation)
            }
            guard generation == planGeneration else { return }
            let geometries = candidates.map { ($0.index, $0.coordinates) }
            let measured = await withTaskGroup(of: (Int, TrafficEstimate?).self) { group in
                for (index, coordinates) in geometries {
                    group.addTask { (index, try? await traffic.estimate(coordinates, departingAt: departure)) }
                }
                var found: [Int: TrafficEstimate] = [:]
                for await (index, estimate) in group {
                    if let estimate { found[index] = estimate }
                }
                return found
            }
            guard generation == planGeneration else { return }
            guard measured.count == geometries.count else {
                trafficStatus = .failed
                return
            }
            trafficEstimates = measured
            trafficStatus = .ready
            // Only while the driver has not chosen, and only for a minute or more: a card whose selection jumps
            // for a few seconds' difference moves under the finger reaching for "Başlat".
            if !userPickedRoute,
               let fastest = measured.min(by: { $0.value.duration < $1.value.duration }),
               let shown = measured[routeSelection],
               fastest.key != routeSelection, shown.duration - fastest.value.duration >= 60 {
                routeSelection = fastest.key // onChange loads its colours
            } else if departure == nil, let shown = candidates.first(where: { $0.index == routeSelection }) {
                loadFlow(for: shown, generation: generation)
            }
        }
    }

    /// The candidates, those that run through a closed stretch replaced by a way round it. One flow request,
    /// along the first candidate (the one on screen; its colours come from the same answer), shows the closed
    /// stretches on and near it. Every candidate whose line runs along one is then replaced from a single new
    /// answer of the router's, asked with those stretches excluded: in its place, so no tile appears or goes.
    /// What the flow does not cover (another candidate's road further off) shows when that candidate's own
    /// flow is loaded (`loadFlow`).
    private func avoidingClosures(
        in options: [RouteOption], from origin: CLLocation, to place: Place, traffic: any TrafficProvider, generation: Int
    ) async -> [RouteOption] {
        guard let planner, let first = options.first, let flow = try? await traffic.flow(along: first.coordinates),
              generation == planGeneration
        else { return options }
        let shapes: [[CLLocationCoordinate2D]] = options.map(\.coordinates)
        let line: [CLLocationCoordinate2D] = first.coordinates
        // Off the main actor: route edges × flow points grows with the route's length.
        let closed = await Task.detached { shapes.map { RouteTraffic.closedPoints(route: $0, flow: flow) } }.value
        let sections = await Task.detached { RouteTraffic.sections(route: line, flow: flow) }.value
        // The card may have been closed meanwhile (that does not end the plan): nothing is put back on it.
        guard generation == planGeneration, routes.count == options.count else { return options }
        var kept = options
        var replaced: Set<Int> = []
        let points: [CLLocationCoordinate2D] = closed.flatMap { $0 }
        // Not once guidance has begun on one of them: there the traffic rounds deal with a closed road.
        if !points.isEmpty, !isNavigating {
            let known = planner.closedRoads
            planner.markClosed(points)
            let fresh = try? await planner.routes(from: origin, to: place.point, areaSpan: place.areaSpan)
            guard generation == planGeneration, routes.count == options.count, !isNavigating else { return options }
            // Server routes only, like the card's own: one from the device's tiles would get no traffic time.
            if let fresh, fresh.first?.isOffline == false {
                let lines: [[CLLocationCoordinate2D]] = fresh.map(\.coordinates)
                var current = shapes
                for index in closed.indices where !closed[index].isEmpty {
                    let others: [[CLLocationCoordinate2D]] = current.indices.filter { $0 != index }.map { current[$0] }
                    let stretch = closed[index]
                    // Another road than the other tiles' when there is one; otherwise the same road as one of
                    // them rather than a route through the closed stretch.
                    let pick = await Task.detached {
                        RouteOverlap.replacement(among: lines, besides: others, avoiding: stretch)
                            ?? RouteOverlap.replacement(among: lines, besides: [], avoiding: stretch)
                    }.value
                    guard let pick else { continue }
                    kept[index] = fresh[pick].placed(at: options[index].index)
                    current[index] = lines[pick]
                    replaced.insert(index)
                }
                guard generation == planGeneration, routes.count == options.count, !isNavigating else { return options }
                routes = kept
                routeLabelPoints = Self.labelPoints(kept)
            } else if fresh == nil {
                // No answer: the roads stay unmarked, so the next plan or traffic round asks again.
                planner.closedRoads = known
            }
        }
        // A candidate still on a closed stretch (no answer, or no way round it yet): guidance, once started on
        // it, asks again from the car at once.
        for index in closed.indices where !closed[index].isEmpty && !replaced.contains(index) {
            previewClosed[options[index].index] = closed[index]
        }
        // The colours of the first candidate come from the same flow, unless another route took its place.
        if !replaced.contains(0) {
            previewTraffic[first.index] = sections
            previewAround[first.index] = AreaTraffic.sections(flow)
        }
        return kept
    }

    /// Slow stretches of one alternative, once per route request (one paid flow request each).
    private func loadFlow(for option: RouteOption, generation: Int) {
        guard let traffic, trafficStatus == .ready, departure == nil, previewTraffic[option.index] == nil else { return }
        let coordinates = option.coordinates
        Task {
            guard let flow = try? await traffic.flow(along: coordinates), generation == planGeneration else { return }
            previewTraffic[option.index] = RouteTraffic.sections(route: coordinates, flow: flow)
            previewAround[option.index] = AreaTraffic.sections(flow)
            // A closed stretch on an alternative whose time is already measured: no import is left for a way
            // round it on the card, so guidance takes that way when it starts on this one (startNavigation).
            previewClosed[option.index] = RouteTraffic.closedPoints(route: coordinates, flow: flow)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    @ViewBuilder private func sheetContent(_ sheet: Sheet) -> some View {
        NavigationStack {
            switch sheet {
            case .search:
                SearchSheet(
                    search: search,
                    onSelect: select,
                    onShortcut: { place in
                        select(place)
                        planRoute(to: place)
                    },
                    onShowOnMap: showOnMap
                )
            case .mapSettings: MapSettingsView(showDiagnostics: { self.sheet = .diagnostics })
            case .diagnostics: LocationDiagnosticsView()
            case .attribution: MapAttributionView()
            case .stops:
                if let navigation {
                    StopsSheet(navigation: navigation, onAdd: { routeVia($0) }, onRemove: { routeVia(nil) })
                }
            }
        }
        .presentationDetents(sheet == .search ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
        // Opaque at half height too: the system's sheet lets the map show through under the settings' text.
        .presentationBackground(Color(sheet == .search ? UIColor.systemBackground : UIColor.systemGroupedBackground))
    }
}

/// Appears only while the map is rotated; tapping it turns north up again.
struct CompassButton: View {
    let viewport: MapViewport
    let action: () -> Void

    var body: some View {
        let bearing = viewport.bearing
        let offNorth = min(bearing.truncatingRemainder(dividingBy: 360), 360 - bearing.truncatingRemainder(dividingBy: 360))
        ZStack {
            if offNorth > 1 {
                Button(action: action) {
                    VStack(spacing: 0) {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.atlasCritical)
                        Text("K")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .rotationEffect(.degrees(-bearing))
                    .frame(width: Metrics.tapTarget, height: Metrics.tapTarget)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .atlasFloatingSurface(in: Circle())
                .accessibilityLabel(Text("Kuzeyi yukarı al"))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: offNorth > 1)
    }
}

/// Loads the businesses to show as badges wherever the map comes to rest at street zoom. A view of its own for
/// the same reason as CityTrafficLoader: it reads the viewport, which changes with every frame.
private struct BusinessLoader: View {
    let viewport: MapViewport
    let index: OfflinePlaceIndex
    let onLoaded: @MainActor ([MapBusiness]) -> Void

    /// From this zoom on: the base map shows all of its own place badges from 16.5.
    private static let minimumZoom = 16.0

    /// The view to the nearest 200 m or so and half a zoom level: a new value means new businesses to load.
    private var key: String {
        guard viewport.zoom >= Self.minimumZoom else { return "far" }
        let step = 0.002
        return "\(Int(viewport.center.latitude / step)):\(Int(viewport.center.longitude / step)):\(Int(viewport.zoom * 2))"
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: key) {
                guard viewport.zoom >= Self.minimumZoom else {
                    onLoaded([])
                    return
                }
                // Still moving: the next change cancels this before it reads anything.
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let box = viewport.box else { return }
                let index = index
                let found = await Task.detached {
                    index.places(west: box.west, south: box.south, east: box.east, north: box.north)
                }.value
                guard !Task.isCancelled else { return }
                onLoaded(found.compactMap { place in
                    PlaceSymbol.badge(for: place.category).map {
                        MapBusiness(id: place.id, name: place.name, badge: $0, coordinate: place.point.coordinate)
                    }
                })
            }
    }
}

/// Measures the drive to Home and Work from here with live traffic, for their chips ("Ev · 24 dk"), as Yandex
/// shows them on its start screen: a route from the router and its time from the traffic provider, one request
/// each per place, again every ten minutes while the chips show and the app is in front, and whenever the
/// car has moved about a kilometre. A view of its own because it reads the position, which changes with
/// every fix; HomeScreen itself does not.
private struct ShortcutTimesLoader: View {
    let home: Place?
    let work: Place?
    let planner: RoutePlanner
    let traffic: any TrafficProvider
    let onTimes: @MainActor ([SearchController.Slot: TimeInterval]) -> Void
    @Environment(LocationProvider.self) private var location
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    /// The position to about a kilometre, and the places: a new value is a new measurement. Nothing in the
    /// background: the phone can keep the app running there, and a request there is one nobody sees.
    private var key: String {
        guard scenePhase == .active, let here = location.lastLocation?.coordinate else { return "idle" }
        let places = [home, work].map { $0.map { "\($0.point.latitude),\($0.point.longitude)" } ?? "-" }
        return "\(Int(here.latitude * 100)):\(Int(here.longitude * 100)):\(places.joined(separator: ":"))"
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: key) {
                guard key != "idle" else { return }
                while !Task.isCancelled {
                    await measure()
                    try? await Task.sleep(for: .seconds(600))
                }
            }
    }

    private func measure() async {
        guard let here = location.lastLocation else { return }
        var times: [SearchController.Slot: TimeInterval] = [:]
        let slots: [(SearchController.Slot, Place?)] = [(.home, home), (.work, work)]
        for (slot, place) in slots {
            // Next door there is nothing to drive.
            guard let place, here.distance(from: CLLocation(latitude: place.point.latitude, longitude: place.point.longitude)) > 1000
            else { continue }
            planner.avoidsTolls = settings.avoidsTolls
            planner.avoidsFerries = settings.avoidsFerries
            // A route from the device's tiles gets no traffic time, and a time without traffic is not what the
            // chip says: no time then.
            guard let route = try? await planner.routes(from: here, to: place.point, areaSpan: place.areaSpan).first,
                  !route.isOffline, !Task.isCancelled,
                  let estimate = try? await traffic.estimate(route.coordinates), !Task.isCancelled
            else { continue }
            times[slot] = estimate.duration
        }
        guard !Task.isCancelled else { return }
        onTimes(times)
    }
}

/// Loads the "Trafik" layer wherever the map comes to rest. A view of its own because it reads the viewport,
/// which changes on every frame while the map moves; HomeScreen itself does not.
private struct CityTrafficLoader: View {
    let viewport: MapViewport
    let cityTraffic: CityTraffic
    let provider: any TrafficProvider

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task(id: viewport.area) {
                // Still moving: the next area change cancels this before it fetches.
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let area = viewport.area else { return }
                while !Task.isCancelled {
                    await cityTraffic.refresh(area, using: provider)
                    try? await Task.sleep(for: CityTraffic.refreshInterval)
                }
            }
    }
}

// Values that change with every fix are read in small views of their own: read in HomeScreen's body they
// re-rendered the whole screen once a second, and the map with it (swiftui-dsl re-adds every layer per update).

/// The camera / bump chip; its distance counts down with each fix.
private struct HazardChipSlot: View {
    let navigation: NavigationSession

    var body: some View {
        if let alert = navigation.hazardAlert {
            HazardChip(alert: alert)
                .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }
}

/// "Varışımı paylaş" in the guidance controls. The message: "Varışım yaklaşık 12:34 · Kartal Adliyesi" and a
/// map link to the place, phrased without a case suffix after the name ("Adliyesi'ne"), which cannot be
/// derived reliably.
private struct ArrivalShareButton: View {
    let navigation: NavigationSession
    let place: Place?
    /// With live traffic when measured (TrafficWatch), otherwise the free-flow estimate.
    let trafficArrival: Date?

    var body: some View {
        if let place, let remaining = navigation.durationRemaining {
            MapControlDivider()
            ShareLink(item: Self.message(place: place, arrival: trafficArrival ?? Date.now.addingTimeInterval(remaining), withTraffic: trafficArrival != nil)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.primary)
                    .frame(width: Metrics.controlWidth, height: Metrics.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Varışımı paylaş"))
        }
    }

    static func message(place: Place, arrival: Date, withTraffic: Bool) -> String {
        var link = URLComponents(string: "https://maps.apple.com/")!
        link.queryItems = [
            URLQueryItem(name: "ll", value: "\(place.point.latitude),\(place.point.longitude)"),
            URLQueryItem(name: "q", value: place.name),
        ]
        let time = Formatting.clock(arrival)
        let traffic = withTraffic ? " (canlı trafikle)" : ""
        return "Varışım yaklaşık \(time)\(traffic) · \(place.name)\n\(link.url?.absoluteString ?? "")"
    }
}
