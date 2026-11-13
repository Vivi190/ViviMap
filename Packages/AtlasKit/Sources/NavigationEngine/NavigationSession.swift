import Combine
import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import Foundation
import Observation
import RoadHazards
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
    /// Symbol of the maneuver right after the next one when it follows within 150 m ("Sonra ↰").
    public private(set) var thenSymbol: String?
    public private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    /// The next camera or bump within warning range, for the banner chip.
    public private(set) var hazardAlert: HazardAlert?

    public let voice = VoiceGuide()
    /// Which hazards to warn about (settings); takes effect from the next fix.
    @ObservationIgnored public var hazardKinds = Set(Hazard.Kind.allCases) {
        didSet { hazardWatch.kinds = hazardKinds }
    }

    @ObservationIgnored private let core: FerrostarCore
    @ObservationIgnored private let bridge: FerrostarLocationBridge
    @ObservationIgnored private var subscription: AnyCancellable?
    @ObservationIgnored private var planner = AnnouncementPlanner()
    @ObservationIgnored private var lastSpeed: Double = 0
    /// Shipped OSM cameras and bumps (works offline).
    @ObservationIgnored private let hazards = HazardCatalog.bundled()?.hazards ?? []
    /// The driver's own marks; set before a route starts, used from the next route change.
    @ObservationIgnored public var userHazards: [Hazard] = []
    @ObservationIgnored private var hazardWatch = HazardWatch()
    /// Measured geometry of the current route; rebuilt when the route changes.
    @ObservationIgnored private var routePath: RoutePath?

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

    /// Moves guidance to another route (an accepted traffic suggestion) without ending the session.
    public func switchRoute(to option: RouteOption, from location: CLLocation) throws {
        planner = AnnouncementPlanner()
        try core.startNavigation(route: option.route, userLocation: UserLocation(clLocation: location))
        voice.speak("Daha hızlı rotaya geçildi.")
    }

    /// The rest of the route from the current position, for re-measuring traffic on what is left.
    public func remainingRoute() -> [CLLocationCoordinate2D] {
        guard let remaining = distanceRemaining, let path = routePath else { return [] }
        return path.remainder(after: max(0, path.length - remaining))
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
        thenSymbol = nil
        routeCoordinates = []
        routePath = nil
        hazardAlert = nil
        hazardWatch = HazardWatch()
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
            // New route (start, reroute or a taken suggestion): find the cameras and bumps it passes.
            let path = RoutePath(routeCoordinates)
            routePath = path
            hazardWatch = HazardWatch(hazards: RouteHazards.along(path, hazards: hazards + userHazards))
            hazardWatch.kinds = hazardKinds
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
            thenSymbol = nil
            hazardAlert = nil
            return
        }
        guard let progress = state.currentProgress else { return }
        distanceToManeuver = progress.distanceToNextManeuver
        distanceRemaining = progress.distanceRemaining
        durationRemaining = progress.durationRemaining

        if let path = routePath {
            let (alert, sentence) = hazardWatch.update(travelled: max(0, path.length - progress.distanceRemaining), speed: lastSpeed)
            if alert != hazardAlert { hazardAlert = alert }
            if let sentence { voice.speak(sentence) }
        }

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

        // remainingSteps[0] is the current step; the step after it ends at the follow-up maneuver.
        let following = state.remainingSteps.flatMap { $0.count > 1 ? $0[1] : nil }
        let followingContent = following?.visualInstructions.first?.primaryContent
        let followUp = following.flatMap { step in
            TurkishInstructions.followUp(
                type: followingContent?.maneuverType,
                modifier: followingContent?.maneuverModifier,
                roundaboutExitDegrees: followingContent?.roundaboutExitDegrees,
                after: step.distance
            )
        }
        let symbol = followUp.map { _ in
            ManeuverSymbols.symbol(type: followingContent?.maneuverType, modifier: followingContent?.maneuverModifier)
        }
        if symbol != thenSymbol { thenSymbol = symbol }

        announce(step: state.remainingSteps?.count ?? 0, distance: progress.distanceToNextManeuver, followUp: followUp)
    }

    private func announce(step: Int, distance: Double, followUp: String?) {
        guard let action = actionText,
              let stage = planner.stage(step: step, distance: distance, speed: lastSpeed)
        else { return }
        let sentence = TurkishInstructions.spoken(
            action: action,
            distance: stage == .now ? nil : distance,
            road: nextRoad,
            then: followUp
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
