import Combine
import CoreLocation
@preconcurrency import FerrostarCore
@preconcurrency import FerrostarCoreFFI
import Foundation
import Observation
import RoadHazards
import RoutingEngine
import SearchEngine

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
    /// Set by the guidance update itself: with the screen locked the UI may notice the arrival only on
    /// unlock, which would lengthen the logged drive.
    public private(set) var arrivedAt: Date?
    public private(set) var isRerouting = false
    /// Called after every guidance update, also with the screen locked when SwiftUI views may not refresh;
    /// the Live Activity on the lock screen runs on it. Cleared by `stop()`.
    @ObservationIgnored public var onUpdate: (@MainActor (NavigationSession) -> Void)?
    /// Where to draw the user: the fix snapped to the route while on it, the raw fix once off it (Ferrostar's
    /// `preferredUserLocation`), so the arrow keeps to the road instead of wandering with GPS noise between
    /// buildings. Cleared by `stop()`.
    @ObservationIgnored public var onPuck: (@MainActor (CLLocation) -> Void)?
    /// Metres / seconds to the next maneuver and to the destination.
    public private(set) var distanceToManeuver: Double?
    public private(set) var distanceRemaining: Double?
    public private(set) var durationRemaining: Double?
    /// SF Symbol for the next maneuver.
    public private(set) var maneuverSymbol = "arrow.up"
    public private(set) var actionText: String?
    public private(set) var nextRoad: String?
    /// The road being driven, in its Turkish spelling; nil on unnamed roads.
    public private(set) var currentRoad: String?
    /// Empty when the data has no lanes — never invented (OSM barely tags them in Istanbul, research §8).
    public private(set) var lanes: [Lane] = []
    /// Symbol of the maneuver right after the next one when it follows within 150 m ("Sonra ↰").
    public private(set) var thenSymbol: String?
    public private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    /// What is left of the route from the car, so the line starts under it and the driven part goes, as Apple Maps
    /// and Yandex draw it. Not observed: it changes on every fix, and the map takes it through `onRouteAhead`
    /// rather than a SwiftUI update (swiftui-dsl rebuilds every layer on each one).
    @ObservationIgnored public private(set) var routeAhead: [CLLocationCoordinate2D] = []
    @ObservationIgnored public var onRouteAhead: (@MainActor ([CLLocationCoordinate2D]) -> Void)?
    /// Where routeAhead starts, in the path's metres.
    @ObservationIgnored private var aheadOffset: CLLocationDistance?
    /// The white arrow on the route at the next turn (shaft, head); empty when it goes straight on or arrives.
    /// Set once per maneuver, not per fix.
    public private(set) var maneuverArrow: [[CLLocationCoordinate2D]] = []
    @ObservationIgnored private var arrowSteps: Int?
    /// Whether the next maneuver is at a traffic light ("Işıklarda sağa dön"), worked out once per maneuver.
    @ObservationIgnored private var maneuverAtLight = false
    @ObservationIgnored private var lightSteps: Int?
    /// The next camera or bump within warning range, for the banner chip.
    public private(set) var hazardAlert: HazardAlert?
    /// Speed limit of the road being driven, km/h, only when the map data has one (OSM `maxspeed` via
    /// Valhalla); nil means unknown, and no sign is shown rather than a guessed one.
    public private(set) var speedLimit: Int?
    /// Camera zoom for the speed and the next turn (GuidanceZoom); changes only in steps.
    public private(set) var guidanceZoom = GuidanceZoom.levels[2]

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
    @ObservationIgnored private var lastFixTime = Date.distantPast
    /// Spoken warning when clearly over the posted limit (map settings → Uyarılar); set before a route starts.
    @ObservationIgnored public var warnsSpeeding = true
    @ObservationIgnored private var speedingWatch = SpeedingWatch()
    /// Shipped OSM cameras and bumps (works offline).
    @ObservationIgnored private let hazards = HazardCatalog.bundled()?.hazards ?? []
    /// The driver's own marks; set before a route starts, used from the next route change.
    @ObservationIgnored public var userHazards: [Hazard] = []
    @ObservationIgnored private var hazardWatch = HazardWatch()
    /// Measured geometry of the current route; rebuilt when the route changes.
    @ObservationIgnored private var routePath: RoutePath?
    /// Road names of the current route by folded name, in their Turkish spelling (TurkishFold.preferredSpellings).
    @ObservationIgnored private var spellings: [String: String] = [:]

    /// - Parameter routes: also answers reroutes, so they fall back to the device without a connection.
    public init(routes: RoutePlanner) {
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
        core = FerrostarCore(
            customRouteProvider: routes,
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
        lastFixTime = location.timestamp
        bridge.forward(location)
    }

    public func start(_ option: RouteOption, from location: CLLocation) throws {
        planner = AnnouncementPlanner()
        speedingWatch = SpeedingWatch()
        speedingWatch.isEnabled = warnsSpeeding
        hasArrived = false
        arrivedAt = nil
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

    /// Where stretches of the route lie on what is left of it, from here (0) to the destination (1); nil for a
    /// stretch off the route or already behind. For the traffic strip under the arrival time, as Yandex shows it.
    public func remainingFractions(of stretches: [[CLLocationCoordinate2D]]) -> [ClosedRange<Double>?] {
        guard let path = routePath, let remaining = distanceRemaining, remaining > 0 else { return stretches.map { _ in nil } }
        return Self.fractions(of: stretches, on: path, travelled: max(0, path.length - remaining), remaining: remaining)
    }

    nonisolated static func fractions(
        of stretches: [[CLLocationCoordinate2D]], on path: RoutePath, travelled: Double, remaining: Double
    ) -> [ClosedRange<Double>?] {
        stretches.map { stretch in
            guard let first = stretch.first, let last = stretch.last,
                  let a = path.project(first, tolerance: 30)?.offset, let b = path.project(last, tolerance: 30)?.offset
            else { return nil }
            let from = (min(a, b) - travelled) / remaining, to = (max(a, b) - travelled) / remaining
            guard to > 0, from < 1 else { return nil }
            return max(0, from) ... min(1, to)
        }
    }

    /// Where the car is on the route, in the path's metres: the snapped position projected near Ferrostar's own
    /// progress (its metres differ slightly from the path's, so the progress alone would start the line off the
    /// car, and a road taken twice could match the wrong pass); nil when the car is off the route.
    nonisolated static func offset(
        of car: CLLocationCoordinate2D, on path: RoutePath, travelled: CLLocationDistance
    ) -> CLLocationDistance? {
        path.project(car, tolerance: 40, within: (travelled - 150)...(travelled + 150))?.offset
    }

    /// The parts of `stretches` (slow traffic on the route) still ahead of the car, drawn along the route line so
    /// they sit exactly on it; nil for one already passed or off the route. Without this, a stretch behind the car
    /// would float there with the route line under it gone (routeAhead).
    public func stretchesAhead(_ stretches: [[CLLocationCoordinate2D]]) -> [[CLLocationCoordinate2D]?] {
        guard let path = routePath else { return stretches.map { _ in nil } }
        return Self.clip(stretches, on: path, from: aheadOffset ?? 0)
    }

    nonisolated static func clip(
        _ stretches: [[CLLocationCoordinate2D]], on path: RoutePath, from car: CLLocationDistance
    ) -> [[CLLocationCoordinate2D]?] {
        stretches.map { stretch in
            guard let first = stretch.first, let last = stretch.last,
                  let a = path.project(first, tolerance: 30)?.offset, let b = path.project(last, tolerance: 30)?.offset
            else { return nil }
            let line = path.slice(from: max(min(a, b), car), to: max(a, b))
            return line.count > 1 ? line : nil
        }
    }

    /// The rest of the route from the current position, for re-measuring traffic on what is left.
    public func remainingRoute() -> [CLLocationCoordinate2D] {
        guard let remaining = distanceRemaining, let path = routePath else { return [] }
        return path.remainder(after: max(0, path.length - remaining))
    }

    public func stop() {
        core.stopNavigation()
        subscription = nil
        onUpdate = nil
        onPuck = nil
        onRouteAhead = nil
        voice.stop()
        isActive = false
        isRerouting = false
        distanceToManeuver = nil
        distanceRemaining = nil
        durationRemaining = nil
        maneuverSymbol = "arrow.up"
        actionText = nil
        nextRoad = nil
        currentRoad = nil
        lanes = []
        thenSymbol = nil
        routeCoordinates = []
        routeAhead = []
        aheadOffset = nil
        routePath = nil
        maneuverArrow = []
        arrowSteps = nil
        lightSteps = nil
        maneuverAtLight = false
        hazardAlert = nil
        speedLimit = nil
        hazardWatch = HazardWatch()
    }

    /// A traffic light within 35 m of the maneuver: OSM puts the node at the stop line or on the junction.
    nonisolated static func nearLight(_ point: CLLocationCoordinate2D, lights: [CLLocationCoordinate2D] = TrafficSignals.bundled) -> Bool {
        let metresPerDegreeLon = 111_320 * cos(point.latitude * .pi / 180)
        return lights.contains { light in
            let dx = (light.longitude - point.longitude) * metresPerDegreeLon
            let dy = (light.latitude - point.latitude) * 110_540
            return dx * dx + dy * dy < 35 * 35
        }
    }

    /// Plain turns at a junction; roundabouts, ramps and forks are not "at the lights".
    nonisolated static func turnsAtJunction(_ type: ManeuverType?) -> Bool {
        switch type {
        case .turn?, .endOfRoad?: true
        default: false
        }
    }

    /// Ferrostar hands over the current segment's Valhalla annotation as JSON; its `maxspeed` is
    /// `{"speed":50,"unit":"km/h"}`, `{"unknown":true}` or `{"none":true}` (no limit, not a sign either).
    static func speedLimit(fromAnnotation json: String?) -> Int? {
        guard let data = json?.data(using: .utf8),
              let annotation = try? JSONDecoder().decode(ValhallaExtendedOSRMAnnotation.self, from: data),
              case let .speed(value, unit: unit)? = annotation.speedLimit
        else { return nil }
        let kmh = switch unit {
        case .kilometersPerHour: value
        case .milesPerHour: value * 1.609344
        case .knots: value * 1.852
        }
        return Int(kmh.rounded())
    }

    private func apply(_ state: NavigationState?) {
        guard isActive, let state else { return }
        defer { onUpdate?(self) }
        if let puck = state.preferredUserLocation?.clLocation { onPuck?(puck) }
        if state.isCalculatingNewRoute, !isRerouting { voice.speak("Yeni rota hesaplanıyor.") }
        isRerouting = state.isCalculatingNewRoute
        // Assign only when the geometry changed (reroute): observers re-render on every set.
        if state.routeGeometry.count != routeCoordinates.count
            || state.routeGeometry.last?.lat != routeCoordinates.last?.latitude
            || state.routeGeometry.first?.lat != routeCoordinates.first?.latitude {
            routeCoordinates = state.routeGeometry.map(\.clLocationCoordinate2D)
            routeAhead = routeCoordinates
            aheadOffset = nil
            // New route (start, reroute or a taken suggestion): find the cameras and bumps it passes.
            let path = RoutePath(routeCoordinates)
            routePath = path
            arrowSteps = nil // the arrow is rebuilt on the new geometry
            lightSteps = nil
            hazardWatch = HazardWatch(hazards: RouteHazards.along(path, hazards: hazards + userHazards))
            hazardWatch.kinds = hazardKinds
            spellings = TurkishFold.preferredSpellings((state.remainingSteps ?? []).flatMap { step in
                [step.roadName].compactMap { $0 } + step.visualInstructions.map(\.primaryContent.text)
            })
        }

        if case .complete = state.tripState {
            guard !hasArrived else { return }
            voice.speak("Hedefe ulaştın.")
            hasArrived = true
            arrivedAt = .now
            // Cleared so the bottom bar says "Vardın" instead of a stale arrival time.
            distanceToManeuver = nil
            distanceRemaining = nil
            durationRemaining = nil
            maneuverSymbol = ManeuverSymbols.symbol(type: .arrive, modifier: nil)
            actionText = "Hedefe ulaştın"
            nextRoad = nil
            currentRoad = nil
            lanes = []
            thenSymbol = nil
            maneuverArrow = []
            hazardAlert = nil
            speedLimit = nil
            return
        }
        guard let progress = state.currentProgress else { return }
        distanceToManeuver = progress.distanceToNextManeuver
        distanceRemaining = progress.distanceRemaining
        durationRemaining = progress.durationRemaining
        if let path = routePath, let puck = state.preferredUserLocation?.clLocation,
           let at = Self.offset(of: puck.coordinate, on: path, travelled: path.length - progress.distanceRemaining) {
            aheadOffset = at
            routeAhead = path.remainder(after: at)
            onRouteAhead?(routeAhead)
        }
        let limit = Self.speedLimit(fromAnnotation: state.currentAnnotationJSON)
        if limit != speedLimit { speedLimit = limit }
        if let warning = speedingWatch.update(speedKmh: lastSpeed * 3.6, limit: limit, at: lastFixTime) { voice.speak(warning) }
        let zoom = GuidanceZoom.level(speed: lastSpeed, distanceToManeuver: progress.distanceToNextManeuver, current: guidanceZoom)
        if zoom != guidanceZoom { guidanceZoom = zoom }

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
        let maneuverIndex = state.remainingSteps?.count ?? 0
        if maneuverIndex != lightSteps, let path = routePath {
            lightSteps = maneuverIndex
            let at = path.length - progress.distanceRemaining + progress.distanceToNextManeuver
            maneuverAtLight = Self.nearLight(path.point(at: at).coordinate)
        }
        let action = TurkishInstructions.action(
            type: content?.maneuverType,
            modifier: content?.maneuverModifier,
            roundaboutExitDegrees: content?.roundaboutExitDegrees
        )
        actionText = (maneuverAtLight && Self.turnsAtJunction(content?.maneuverType) ? action.map(TurkishInstructions.atLights) : action)
            ?? content?.text
        // The banner text from Valhalla is the next road's name for most maneuvers.
        nextRoad = content.flatMap { $0.maneuverType == .arrive ? nil : $0.text }
            .map { spellings[TurkishFold.fold($0)] ?? $0 }
        let road = state.currentRoadName.flatMap { $0.isEmpty ? nil : spellings[TurkishFold.fold($0)] ?? $0 }
        if road != currentRoad { currentRoad = road }

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

        // Once per maneuver: through a roundabout the arrow runs on to the exit (the step after it).
        let steps = state.remainingSteps?.count ?? 0
        if steps != arrowSteps, let path = routePath {
            // Until the step's banner is there, try again on the next fix.
            arrowSteps = content == nil ? nil : steps
            let type = content?.maneuverType
            let at = path.length - progress.distanceRemaining + progress.distanceToNextManeuver
            let arrow = ManeuverArrow.wanted(type: type, modifier: content?.maneuverModifier)
                ? ManeuverArrow.lines(along: path, maneuverAt: at, after: ManeuverArrow.reach(type: type, nextStep: following?.distance))
                : []
            if !(arrow.isEmpty && maneuverArrow.isEmpty) { maneuverArrow = arrow }
        }

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
