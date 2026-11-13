import AppCore
import LocationEngine
import RoutingEngine
import SwiftUI

@main
struct AtlasApp: App {
    @State private var settings: AppSettings
    @State private var location: LocationProvider
    @Environment(\.scenePhase) private var scenePhase
    private let startsTracking: Bool
    private let initiallyNight: Bool
    private let planner = try? RoutePlanner()

    init() {
        let settings = AppSettings()
        let location = LocationProvider()
        _settings = State(initialValue: settings)
        _location = State(initialValue: location)
        // Decided once at launch so the first frame already has the right camera and palette.
        startsTracking = location.lastLocation != nil
        let anchor = location.lastLocation?.coordinate ?? Defaults.istanbul
        initiallyNight = settings.appearanceMode.isNight(at: .now, latitude: anchor.latitude, longitude: anchor.longitude)
    }

    var body: some Scene {
        WindowGroup {
            HomeScreen(startsTracking: startsTracking, initiallyNight: initiallyNight, planner: planner)
                .environment(settings)
                .environment(location)
        }
        .onChange(of: scenePhase) { _, phase in
            // Phase 1 has no background mode: release GPS when the app leaves the screen.
            switch phase {
            case .active: location.start()
            case .background: location.stop()
            default: break
            }
        }
    }
}
