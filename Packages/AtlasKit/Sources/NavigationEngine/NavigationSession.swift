import Combine
import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import Foundation
import Observation
import RoutingEngine

/// Turn-by-turn guidance: Ferrostar follows the route (snapping, step advance, deviation and automatic
/// reroute through the same Valhalla); this class turns its state into UI values and Turkish prompts.
@MainActor
@Observable
public final class NavigationSession {
    /// One lane of the upcoming maneuver, as given by the routing data.
    public struct Lane: Hashable, Sendable {
        public let symbol: String
        public let isActive: Bool
    }

    public private(set) var isActive = false
    public private(set) var hasArrived = false
    public private(set) var isRerouting = false
    /// Metres / seconds to the next maneuver and to the destination.
    public private(set) var distanceToManeuver: Double?
    public private(set) var distanceRemaining: Double?
    public private(set) var durationRemaining: Double?
    /// SF Symbol for the next maneuver.
    public private(set) var maneuverSymbol = "arrow.up"
    public private(set) var actionText: String?
    public private(set) var nextRoad: String?
    /// Empty when the data has no lanes — never invented (OSM barely tags them in Istanbul, research §8).
    public private(set) var lanes: [Lane] = []
    public private(set) var routeCoordinates: [CLLocationCoordinate2D] = []

    public let voice = VoiceGuide()

    @ObservationIgnored private let core: FerrostarCore
    @ObservationIgnored private let bridge: FerrostarLocationBridge
    @ObservationIgnored private var subscription: AnyCancellable?
    @ObservationIgnored private var planner = AnnouncementPlanner()
    @ObservationIgnored private var lastSpeed: Double = 0

    public init() throws {
        let bridge = FerrostarLocationBridge()
        self.bridge = bridge
        let config = SwiftNavigationControllerConfig(
            waypointAdvance: .waypointWithinRange(100.0),
            stepAdvanceCondition: stepAdvanceDistanceEntryAndExit(
                distanceToEndOfStep: 30, distanceAfterEndOfStep: 5, minimumHorizontalAccuracy: 32
            ),
            arrivalStepAdvanceCondition: stepAdvanceDistanceToEndOfStep(distance: 20, minimumHorizontalAccuracy: 32),
            routeDeviationTracking: .staticThreshold(minimumHorizontalAccuracy: 25, maxAcceptableDeviation: 50),
            snappedLocationCourseFiltering: .snapToRoute
        )
        core = try FerrostarCore(
            wellKnownRouteProvider: RoutePlanner.valhallaProvider(),
            locationProvider: bridge,
            navigationControllerConfig: config,
            networkSession: IdentifiedLoader(),
            // Ferrostar would read Valhalla's broken tr-TR text; Turkish prompts come from VoiceGuide instead.
            spokenInstructionObserver: .initAVSpeechSynthesizer(isMuted: true)
        )
    }

    /// Every GPS fix goes through here while navigating.
    public func ingest(_ location: CLLocation) {
        guard isActive else { return }
        lastSpeed = max(location.speed, 0)
        bridge.forward(location)
    }

    public func start(_ option: RouteOption, from location: CLLocation) throws {
        planner = AnnouncementPlanner()
        hasArrived = false
        subscription = core.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                MainActor.assumeIsolated { self?.apply(state) }
            }
        try core.startNavigation(route: option.route, userLocation: UserLocation(clLocation: location))
        isActive = true
        voice.speak("Rota başladı. \(Formatted.duration(option.duration)) sürecek.")
    }

    public func stop() {
        core.stopNavigation()
        subscription = nil
        voice.stop()
        isActive = false
        isRerouting = false
        distanceToManeuver = nil
        distanceRemaining = nil
        durationRemaining = nil
        maneuverSymbol = "arrow.up"
        actionText = nil
        nextRoad = nil
        lanes = []
        routeCoordinates = []
    }

    private func apply(_ state: NavigationState?) {
        guard isActive, let state else { return }
        if state.isCalculatingNewRoute, !isRerouting { voice.speak("Yeni rota hesaplanıyor.") }
        isRerouting = state.isCalculatingNewRoute
        // Assign only when the geometry changed (reroute): observers re-render on every set.
        if state.routeGeometry.count != routeCoordinates.count
            || state.routeGeometry.last?.lat != routeCoordinates.last?.latitude
            || state.routeGeometry.first?.lat != routeCoordinates.first?.latitude {
            routeCoordinates = state.routeGeometry.map(\.clLocationCoordinate2D)
        }

        if case .complete = state.tripState {
            guard !hasArrived else { return }
            voice.speak("Hedefe ulaştın.")
            hasArrived = true
            // Cleared so the bottom bar says "Vardın" instead of a stale arrival time.
            distanceToManeuver = nil
            distanceRemaining = nil
            durationRemaining = nil
            maneuverSymbol = ManeuverSymbols.symbol(type: .arrive, modifier: nil)
            actionText = "Hedefe ulaştın"
            nextRoad = nil
            lanes = []
            return
        }
        guard let progress = state.currentProgress else { return }
        distanceToManeuver = progress.distanceToNextManeuver
        distanceRemaining = progress.distanceRemaining
        durationRemaining = progress.durationRemaining

        let content = state.currentVisualInstruction?.primaryContent
        maneuverSymbol = ManeuverSymbols.symbol(type: content?.maneuverType, modifier: content?.maneuverModifier)
        let laneInfo = state.currentVisualInstruction?.subContent?.laneInfo ?? content?.laneInfo ?? []
        lanes = laneInfo.map { lane in
            Lane(symbol: ManeuverSymbols.lane(lane.activeDirection ?? lane.directions.first), isActive: lane.active)
        }
        actionText = TurkishInstructions.action(
            type: content?.maneuverType,
            modifier: content?.maneuverModifier,
            roundaboutExitDegrees: content?.roundaboutExitDegrees
        ) ?? content?.text
        // The banner text from Valhalla is the next road's name for most maneuvers.
        nextRoad = content.flatMap { $0.maneuverType == .arrive ? nil : $0.text }

        announce(step: state.remainingSteps?.count ?? 0, distance: progress.distanceToNextManeuver)
    }

    private func announce(step: Int, distance: Double) {
        guard let action = actionText,
              let stage = planner.stage(step: step, distance: distance, speed: lastSpeed)
        else { return }
        let sentence = TurkishInstructions.spoken(
            action: action,
            distance: stage == .now ? nil : distance,
            road: nextRoad
        )
        voice.speak(sentence)
    }
}

/// Spoken duration ("27 dakika", "1 saat 12 dakika") — the visual form lives in AppCore.Formatting.
enum Formatted {
    static func duration(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        if hours == 0 { return "\(rest) dakika" }
        return rest == 0 ? "\(hours) saat" : "\(hours) saat \(rest) dakika"
    }
}
