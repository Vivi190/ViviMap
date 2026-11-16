import AppCore
import LocationEngine
import NavigationEngine
import RoadHazards
import RoutingEngine
import SwiftUI
import TrafficEngine
import TripHistory

@main
struct AtlasApp: App {
    @State private var settings: AppSettings
    @State private var location: LocationProvider
    @State private var userHazards = UserHazardStore()
    @State private var trips = TripLog()
    @Environment(\.scenePhase) private var scenePhase
    private let startsTracking: Bool
    private let initiallyNight: Bool
    private let planner: RoutePlanner?
    /// Shares the planner, so reroutes fall back to the device's Istanbul tiles without a connection too.
    private let navigation: NavigationSession?
    /// nil without a HERE key in the build: routes then stay labelled "Trafiksiz tahmini süre".
    private let traffic = HERETrafficProvider()

    init() {
        let planner = try? RoutePlanner()
        self.planner = planner
        navigation = planner.map { NavigationSession(routes: $0) }
        let settings = AppSettings()
        let location = LocationProvider()
        _settings = State(initialValue: settings)
        _location = State(initialValue: location)
        // Decided once at launch so the first frame already has the right camera and palette.
        startsTracking = location.lastLocation != nil
        let anchor = location.lastLocation?.coordinate ?? Defaults.istanbul
        initiallyNight = settings.appearanceMode.isNight(at: .now, latitude: anchor.latitude, longitude: anchor.longitude)
        // One GPS stream: guidance receives the same fixes as the map and speedometer.
        location.onFix = { [navigation] fix in navigation?.ingest(fix) }
    }

    var body: some Scene {
        WindowGroup {
            HomeScreen(
                startsTracking: startsTracking,
                initiallyNight: initiallyNight,
                planner: planner,
                navigation: navigation,
                traffic: traffic
            )
                .environment(settings)
                .environment(location)
                .environment(userHazards)
                .environment(trips)
        }
        // initial: true — without it a launch that is already `.active` never started our location
        // manager (seen in CI: MapLibre's puck had a fix, the speedometer/navigation stream had none).
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: location.start()
            // Keep guiding with the screen locked; otherwise release GPS to save battery.
            case .background where !location.isNavigating: location.stop()
            default: break
            }
        }
    }
}
