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

    func update(from proxy: MapViewProxy) {
        if abs(proxy.direction - bearing) > 0.5 { bearing = proxy.direction }
        zoom = proxy.zoomLevel
        pitch = proxy.pitch
        center = proxy.centerCoordinate
    }
}

struct HomeScreen: View {
    enum Sheet: String, Identifiable {
        case search, mapSettings, diagnostics, attribution
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
    @State private var routes: [RouteOption] = []
    @State private var routeSelection = 0
    @State private var isPlanning = false
    @State private var routeError: String?
    @State private var simulator = DriveSimulator()
    /// Feeds the user puck during a simulated drive; nil = real GPS.
    @State private var simulatedPuck: StaticLocationManager?
    @State private var trafficEstimates: [Int: TrafficEstimate] = [:]
    @State private var trafficStatus = RouteCard.TrafficStatus.unavailable
    /// Slow stretches per route alternative, fetched for the one on screen.
    @State private var previewTraffic: [Int: [TrafficSection]] = [:]
    /// Bumped per route request so a late traffic answer never lands on newer routes.
    @State private var planGeneration = 0
    @State private var trafficWatch = TrafficWatch()
    @State private var connectivity = Connectivity()
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

    // Explicitly typed: a `cond ? nil : method` ternary inside the view builder broke the type checker
    // ("failed to produce diagnostic for expression").
    private var longPressHandler: ((CLLocationCoordinate2D) -> Void)? {
        if isNavigating { return nil }
        return { pick($0) }
    }

    private var startHandler: (() -> Void)? {
        if navigation == nil { return nil }
        return { startNavigation(simulated: false) }
    }

    private var simulateHandler: (() -> Void)? {
        if navigation == nil || !settings.showsDriveSimulation { return nil }
        return { startNavigation(simulated: true) }
    }

    /// During guidance the session's geometry wins: it changes after a reroute.
    private var displayedRoute: [CLLocationCoordinate2D] {
        if isNavigating, let coordinates = navigation?.routeCoordinates, coordinates.count > 1 { return coordinates }
        return activeRoute?.coordinates ?? []
    }

    private var hazardKinds: Set<Hazard.Kind> {
        var kinds: Set<Hazard.Kind> = []
        if settings.warnsCameras { kinds.insert(.camera) }
        if settings.warnsBumps { kinds.insert(.bump) }
        return kinds
    }

    private var displayedTraffic: [TrafficLine] {
        let sections = isNavigating ? trafficWatch.sections : activeRoute.flatMap { previewTraffic[$0.index] } ?? []
        return sections.map { section in
            let level: TrafficLine.Level = switch section.level {
            case .slow: .slow
            case .heavy: .heavy
            case .stopped: .stopped
            }
            return TrafficLine(level: level, coordinates: section.coordinates)
        }
    }

    var body: some View {
        ZStack {
            AtlasMapView(
                camera: $camera,
                appearance: isNight ? .night : .day,
                showsBuildings3D: is3D,
                destination: selectedPlace?.point.coordinate,
                route: displayedRoute,
                traffic: displayedTraffic,
                marks: userHazards.hazards.map { MapMark(isCamera: $0.kind == .camera, coordinate: $0.coordinate) },
                puckSource: simulatedPuck,
                isGuiding: isNavigating,
                isOffline: !connectivity.isOnline,
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
        .task(id: isNavigating) { await watchTraffic() }
        .onChange(of: hazardKinds) { _, kinds in navigation?.hazardKinds = kinds }
        .onChange(of: navigation?.hasArrived) { _, arrived in
            if arrived == true { recordTrip(arrived: true) }
        }
        .onChange(of: navigation?.guidanceZoom) { _, zoom in
            // Only while the camera follows the car; a driver who panned the map keeps their view.
            if let zoom, isNavigating, camera.trackingMode == .followDirection { followCourse(zoom: zoom) }
        }
        .onChange(of: routeSelection) { _, index in
            if let option = routes.first(where: { $0.index == index }) { loadFlow(for: option, generation: planGeneration) }
        }
        .onChange(of: location.hasFix) { _, hasFix in
            // First fix after a cold start: jump to the user unless they already moved the map.
            guard hasFix, awaitingFirstFix else { return }
            awaitingFirstFix = false
            if camera.trackingMode == .none, !userMovedMap {
                camera = .trackUserLocation(zoom: 15.5)
            }
        }
    }

    // MARK: Overlay

    private var overlay: some View {
        VStack(spacing: Spacing.s) {
            HStack(alignment: .top, spacing: Spacing.m) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    SearchBarButton { sheet = .search }
                        .frame(maxWidth: isLandscape ? 420 : .infinity)
                    GPSStatusChip(openSettings: openSettings, showDiagnostics: { sheet = .diagnostics })
                    if !connectivity.isOnline { offlineChip }
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
                        Text("© OpenStreetMap")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.s)
                            .padding(.vertical, Spacing.xs)
                            .atlasFloatingSurface(in: Capsule())
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
    }

    private var controls: some View {
        MapControlGroup {
            MapControlButton(systemImage: "map", label: "Harita ayarları") { sheet = .mapSettings }
            MapControlDivider()
            MapControlTextButton(title: is3D ? "2D" : "3D", label: "Üç boyutlu görünüm", isActive: is3D, action: toggle3D)
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
        search.remember(place)
        show(place)
        camera = .center(place.point.coordinate, zoom: max(viewport.zoom, 16), pitch: is3D ? Self.pitch3D : 0)
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

    private func show(_ place: Place) {
        routes = []
        routeError = nil
        selectedPlace = place
        sheet = nil
    }

    private func placeCard(_ place: Place) -> some View {
        PlaceCard(
            place: place,
            isPlanning: isPlanning,
            error: routeError,
            onRoute: { planRoute(to: place) },
            onSave: { search.save(place, as: $0) },
            onMark: { userHazards.mark($0, latitude: place.point.latitude, longitude: place.point.longitude) },
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
            selection: $routeSelection,
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
            title: OfflineMap.packages == nil ? "İnternet yok" : "İnternet yok · İstanbul çevrimdışı",
            tone: .warning
        )
        .accessibilityIdentifier("offline.chip")
    }

    /// iPhone on its side (car mounts): panels move into a left column and the map gets the rest.
    private var isLandscape: Bool { verticalSizeClass == .compact }

    private func navigationControls(_ navigation: NavigationSession) -> some View {
        MapControlGroup {
            MapControlButton(
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                label: "Rotanın tamamı",
                isActive: camera.trackingMode == .none
            ) { showRouteOverview(navigation) }
            MapControlDivider()
            MapControlButton(
                systemImage: "location.north.line.fill",
                label: "Konumumu göster",
                isActive: camera.trackingMode == .followDirection
            ) { followCourse(zoom: navigation.guidanceZoom) }
        }
    }

    private func navigationOverlay(_ navigation: NavigationSession) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            navigationColumn(navigation)
                .frame(maxWidth: isLandscape ? 380 : .infinity)
            if isLandscape {
                Spacer(minLength: 0)
                navigationControls(navigation)
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
        .animation(.snappy(duration: 0.3), value: trafficWatch.suggestion?.option.id)
    }

    private func navigationColumn(_ navigation: NavigationSession) -> some View {
        VStack(spacing: Spacing.s) {
            NavigationBanner(navigation: navigation)
            if let suggestion = trafficWatch.suggestion {
                RouteSuggestionBanner(suggestion: suggestion, onAccept: acceptSuggestion) { trafficWatch.dismiss() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    if let alert = navigation.hazardAlert {
                        HazardChip(alert: alert)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    if !connectivity.isOnline { offlineChip }
                }
                Spacer(minLength: 0)
                if !isLandscape { navigationControls(navigation) }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                SpeedOverlay(limit: navigation.speedLimit)
                Spacer(minLength: 0)
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
            NavigationBottomBar(navigation: navigation, trafficArrival: trafficWatch.arrival, onEnd: { endNavigation() })
        }
    }

    /// Traffic rounds while guiding; the task is cancelled when navigation ends (its id changes).
    private func watchTraffic() async {
        guard isNavigating, let traffic, let planner, let navigation, let destination = selectedPlace?.point else { return }
        trafficWatch.reset()
        var wait: Duration = .seconds(20) // first look soon after the start, then every few minutes
        while !Task.isCancelled {
            try? await Task.sleep(for: wait)
            wait = TrafficWatch.interval
            guard !Task.isCancelled, let position = location.lastLocation else { continue }
            await trafficWatch.check(navigation: navigation, planner: planner, traffic: traffic, position: position, destination: destination)
        }
    }

    private func acceptSuggestion() {
        guard let navigation, let position = location.lastLocation,
              let option = trafficWatch.accept(navigation: navigation, from: position) else { return }
        // A simulated drive continues along the new route from here.
        if simulatedPuck != nil { simulate(option, from: position) }
    }

    private func startNavigation(simulated: Bool) {
        guard let navigation, let route = activeRoute else { return }
        // A simulated drive starts on the route itself; real guidance starts from the GPS fix.
        let start = simulated
            ? route.coordinates.first.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
            : location.lastLocation
        guard let start else {
            routeError = "Konumun henüz bilinmiyor."
            return
        }
        do {
            navigation.hazardKinds = hazardKinds
            navigation.userHazards = userHazards.hazards
            try navigation.start(route, from: start)
            location.setNavigating(true)
            // The screen stays on while guiding (it can still be locked by hand; guidance continues).
            UIApplication.shared.isIdleTimerDisabled = true
            if simulated {
                simulate(route, from: start)
            } else if let place = selectedPlace {
                let estimate = trafficStatus == .ready ? trafficEstimates[route.index] : nil
                tripStart = TripStart(
                    date: .now, destination: place.name, distance: route.distance,
                    predicted: estimate?.duration ?? route.duration, withTraffic: estimate != nil
                )
            }
            is3D = true
            followCourse(zoom: navigation.guidanceZoom)
        } catch {
            routeError = "Navigasyon başlatılamadı."
        }
    }

    private func followCourse(zoom: Double) {
        camera = .trackUserLocationWithCourse(zoom: zoom, pitch: Self.pitch3D, pitchRange: .fixed(Self.pitch3D))
    }

    /// The whole rest of the route, framed between the banner and the bottom bar; "Konumumu göster" returns.
    private func showRouteOverview(_ navigation: NavigationSession) {
        let rest = navigation.remainingRoute()
        guard rest.count > 1 else { return }
        let lats = rest.map(\.latitude), lons = rest.map(\.longitude)
        camera = .fitting(
            southWest: CLLocationCoordinate2D(latitude: lats.min()!, longitude: lons.min()!),
            northEast: CLLocationCoordinate2D(latitude: lats.max()!, longitude: lons.max()!),
            padding: UIEdgeInsets(top: 230, left: 50, bottom: 230, right: 80)
        )
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
    private func recordTrip(arrived: Bool) {
        guard let start = tripStart else { return }
        tripStart = nil
        trips.record(Trip(
            startedAt: start.date, endedAt: .now, destination: start.destination, distance: start.distance,
            predicted: start.predicted, predictedWithTraffic: start.withTraffic, arrived: arrived
        ))
    }

    private func endNavigation() {
        recordTrip(arrived: false)
        simulator.stop()
        trafficWatch.reset()
        if simulatedPuck != nil {
            simulatedPuck = nil
            location.endSimulation()
        }
        navigation?.stop()
        location.setNavigating(false)
        UIApplication.shared.isIdleTimerDisabled = false
        clearPlace()
        is3D = false
        camera = .trackUserLocation(zoom: 15.5, pitch: 0, pitchRange: .fixed(0))
    }

    private func clearPlace() {
        selectedPlace = nil
        routes = []
        routeError = nil
    }

    private func planRoute(to place: Place) {
        guard let planner else {
            routeError = "Rota servisi başlatılamadı."
            return
        }
        guard let here = location.lastLocation else {
            routeError = "Konumun henüz bilinmiyor."
            return
        }
        isPlanning = true
        routeError = nil
        planGeneration += 1
        let generation = planGeneration
        Task {
            do {
                let found = try await planner.routes(from: here, to: place.point)
                guard generation == planGeneration else { return }
                routeSelection = 0
                routes = found
                scoreTraffic(found, generation: generation)
                if let first = found.first {
                    camera = .fitting(
                        southWest: first.southWest,
                        northEast: first.northEast,
                        padding: UIEdgeInsets(top: 150, left: 50, bottom: 320, right: 90)
                    )
                }
            } catch {
                routeError = error.localizedDescription
            }
            isPlanning = false
        }
    }

    /// Measures every candidate with the one traffic provider (ADR-5) and preselects the fastest. Shown only
    /// when all of them were measured: mixing traffic and free-flow times would compare different scales.
    private func scoreTraffic(_ options: [RouteOption], generation: Int) {
        trafficEstimates = [:]
        previewTraffic = [:]
        guard let traffic else {
            trafficStatus = .unavailable
            return
        }
        trafficStatus = .loading
        let geometries = options.map { ($0.index, $0.coordinates) }
        Task {
            let measured = await withTaskGroup(of: (Int, TrafficEstimate?).self) { group in
                for (index, coordinates) in geometries {
                    group.addTask { (index, try? await traffic.estimate(coordinates)) }
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
            if routeSelection == 0, let fastest = measured.min(by: { $0.value.duration < $1.value.duration })?.key, fastest != 0 {
                routeSelection = fastest // onChange loads its colours
            } else if let shown = options.first(where: { $0.index == routeSelection }) {
                loadFlow(for: shown, generation: generation)
            }
        }
    }

    /// Slow stretches of one alternative, once per route request (one paid flow request each).
    private func loadFlow(for option: RouteOption, generation: Int) {
        guard let traffic, trafficStatus == .ready, previewTraffic[option.index] == nil else { return }
        let coordinates = option.coordinates
        Task {
            guard let flow = try? await traffic.flow(along: coordinates), generation == planGeneration else { return }
            previewTraffic[option.index] = RouteTraffic.sections(route: coordinates, flow: flow)
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    @ViewBuilder private func sheetContent(_ sheet: Sheet) -> some View {
        NavigationStack {
            switch sheet {
            case .search:
                SearchSheet(search: search, onSelect: select) { place in
                    select(place)
                    planRoute(to: place)
                }
            case .mapSettings: MapSettingsView(showDiagnostics: { self.sheet = .diagnostics })
            case .diagnostics: LocationDiagnosticsView()
            case .attribution: MapAttributionView()
            }
        }
        .presentationDetents(sheet == .search ? [.large] : [.medium, .large])
        .presentationDragIndicator(.visible)
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
