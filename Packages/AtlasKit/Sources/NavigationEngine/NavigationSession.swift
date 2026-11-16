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
    /// Whether the next maneuver is at a traffic light ("Işıklarda sağa dönün"), worked out once per maneuver.
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
    /// Whether the last update had the car off every remaining step; "Rotadan çıktınız." is said on the way in.
    @ObservationIgnored private var isOffRoute = false
    /// A failed reroute has been announced; Ferrostar keeps retrying, and nothing more is said until the car
    /// is back on a route.
    @ObservationIgnored private var rerouteFailed = false
    @ObservationIgnored private var statusThrottle = StatusThrottle()

    /// - Parameter routes: also answers reroutes: from the tiles on the device when the build has them, else
    ///   from the server.
    public init(routes: RoutePlanner) {
        let bridge = FerrostarLocationBridge()
        self.bridge = bridge
        let config = SwiftNavigationControllerConfig(
            waypointAdvance: .waypointWithinRange(100.0),
            // A step ends in one of two ways, whichever comes first.
            // 1. A fix within 30 m of its end, then the position snapped to the route 5 m past it. Measured on
            //    the raw fix alone, 5 m of GPS error beside the line (the outer lane) counted as past the end:
            //    below 50 km/h the card, the arrow and the zoom moved on up to 25 m before the turn.
            // 2. A fix within 30 m of its end, then the raw fix more than 20 m from the step. Ferrostar 0.59's
            //    snapped condition forgets its entry whenever an exit check fails, so its two checks alternate
            //    from fix to fix. Between 90 and 125 km/h a fix can pass both by; the step then never ends and
            //    Ferrostar reroutes a car that is on its route (1 step end in 6 at 108 km/h with fixes on the
            //    line once a second). This condition keeps its entry and ends the step on the next fix.
            stepAdvanceCondition: stepAdvanceOr(conditions: [
                stepAdvanceDistanceEntryAndSnappedExit(
                    distanceToEndOfStep: 30, distanceAfterEndOfStep: 5, minimumHorizontalAccuracy: 32
                ),
                stepAdvanceDistanceEntryAndExit(
                    distanceToEndOfStep: 30, distanceAfterEndOfStep: 20, minimumHorizontalAccuracy: 32
                ),
            ]),
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
        // A fix CoreLocation marks as invalid (negative accuracy) would pass every accuracy gate in Ferrostar,
        // which only rejects accuracies above its thresholds.
        guard isActive, location.horizontalAccuracy >= 0, CLLocationCoordinate2DIsValid(location.coordinate) else { return }
        lastSpeed = max(location.speed, 0)
        lastFixTime = location.timestamp
        bridge.forward(location)
    }

    /// - Parameter expectedDuration: the time to say at the start when it is known better than the route's own
    ///   (measured with traffic); nil says the route's.
    public func start(_ option: RouteOption, from location: CLLocation, expectedDuration: TimeInterval? = nil) throws {
        planner = AnnouncementPlanner()
        speedingWatch = SpeedingWatch()
        speedingWatch.isEnabled = warnsSpeeding
        statusThrottle = StatusThrottle()
        isOffRoute = false
        rerouteFailed = false
        if isRerouting { isRerouting = false }
        // Not the last fix of the drive before: its speed would set this one's first lead distances and zoom.
        lastSpeed = max(location.speed, 0)
        lastFixTime = location.timestamp
        hasArrived = false
        arrivedAt = nil
        subscription = core.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                MainActor.assumeIsolated { self?.apply(state) }
            }
        try core.startNavigation(route: option.route, userLocation: UserLocation(clLocation: location))
        isActive = true
        voice.speak("Rota oluşturuldu. \(Formatted.duration(expectedDuration ?? option.duration)) sürecek.")
    }

    /// Moves guidance to another route (an accepted traffic suggestion) without ending the session.
    public func switchRoute(to option: RouteOption, from location: CLLocation) throws {
        planner = AnnouncementPlanner()
        try core.startNavigation(route: option.route, userLocation: UserLocation(clLocation: location))
        // Ferrostar drops a reroute still in flight; the route about to arrive is this one, with its own sentence.
        if isRerouting { isRerouting = false }
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

    /// Which of `points` lie on the route (within 30 m), for road events to show while guiding. Reads no observed
    /// state, so a view asking once per update is not redrawn on every fix.
    public func onRoute(_ points: [CLLocationCoordinate2D]) -> [Bool] {
        guard let path = routePath else { return points.map { _ in false } }
        return points.map { path.project($0, tolerance: 30) != nil }
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
        isOffRoute = false
        rerouteFailed = false
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

    /// The road a banner names, nil when it names none. For a road with no name, sign or number Valhalla fills
    /// the banner with the maneuver's own sentence ("sağa dönün."), the very text the step after it carries as
    /// its instruction; that is not a name to show as the headline or to read out after the comma.
    nonisolated static func roadName(banner text: String, nextInstruction: String?) -> String? {
        text.isEmpty || text == nextInstruction ? nil : text
    }

    /// Off every remaining step, not just the current one (which Ferrostar also reports while the car is on
    /// the route but ahead of the step it is tracking, and where its distances still mean something).
    nonisolated static func isCompletelyOffRoute(_ deviation: RouteDeviation?) -> Bool {
        guard let deviation else { return false }
        switch deviation {
        case .noDeviation:
            return false
        case let .deviation(kind: kind):
            switch kind {
            case .completelyOffRoute: return true
            case .offStepOnRoute: return false
            }
        }
    }

    /// Whether the car is on a ferry, from the maneuver each remaining step ends with (the current step first).
    /// Valhalla marks every change of travel mode with a `notification` and a car route ends on a road, so an
    /// odd number of them ahead means the current leg is a crossing and the next `notification` ends it.
    nonisolated static func isOnFerry(_ maneuversAhead: [ManeuverType?]) -> Bool {
        !maneuversAhead.filter { $0 == .notification }.count.isMultiple(of: 2)
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
        let wasRerouting = isRerouting
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
            // The same watch with what it has announced: a camera in range is not warned of a second time.
            hazardWatch.hazards = RouteHazards.along(path, hazards: hazards + userHazards)
            hazardWatch.kinds = hazardKinds
            spellings = TurkishFold.preferredSpellings((state.remainingSteps ?? []).flatMap { step in
                [step.roadName].compactMap { $0 } + step.visualInstructions.map(\.primaryContent.text)
            })
            // The planner knows a maneuver by the number of steps left, and a new route can have as many left
            // as the old one: its first maneuver would inherit the stages already spoken.
            planner = AnnouncementPlanner()
            isOffRoute = false
            rerouteFailed = false
            // Ferrostar's own reroute; `start` and `switchRoute` say their own sentence.
            if wasRerouting { status("Rota yeniden oluşturuldu.") }
        } else if wasRerouting, !state.isCalculatingNewRoute, !rerouteFailed {
            // The request ended with no new route. Ferrostar drops the error and tries again after 5 s and
            // 50 m, so this is said once, not at every attempt.
            rerouteFailed = true
            status("Yeni rota oluşturulamadı.")
        }

        if case .complete = state.tripState {
            guard !hasArrived else { return }
            voice.speak("Hedefinize ulaştınız.")
            hasArrived = true
            arrivedAt = .now
            // Cleared so the bottom bar says "Vardınız" instead of a stale arrival time.
            distanceToManeuver = nil
            distanceRemaining = nil
            durationRemaining = nil
            maneuverSymbol = ManeuverSymbols.symbol(type: .arrive, modifier: nil)
            actionText = "Hedefinize ulaştınız"
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
        // Off the route altogether, Ferrostar's distance belongs to a point the car is not at, and it sends
        // no banner; the card says so instead of counting down to a turn that cannot be made from here.
        let offRoute = Self.isCompletelyOffRoute(state.currentDeviation)
        if offRoute, !isOffRoute { status("Rotadan çıktınız.") }
        isOffRoute = offRoute
        if case .noDeviation? = state.currentDeviation { rerouteFailed = false }
        distanceToManeuver = offRoute ? nil : progress.distanceToNextManeuver
        distanceRemaining = progress.distanceRemaining
        durationRemaining = progress.durationRemaining
        // Metres driven along the path: the snapped position's own offset when it projects onto the path.
        // Ferrostar's remaining distance is the fallback only: it adds up Valhalla's step lengths, whose metres
        // drift from the path's by tens of metres on a long route.
        var travelled: CLLocationDistance = 0
        if let path = routePath {
            travelled = max(0, path.length - progress.distanceRemaining)
            if let puck = state.preferredUserLocation?.clLocation,
               let at = Self.offset(of: puck.coordinate, on: path, travelled: path.length - progress.distanceRemaining) {
                aheadOffset = at
                routeAhead = path.remainder(after: at)
                onRouteAhead?(routeAhead)
                travelled = at
            }
        }
        let limit = Self.speedLimit(fromAnnotation: state.currentAnnotationJSON)
        if limit != speedLimit { speedLimit = limit }
        if let warning = speedingWatch.update(speedKmh: lastSpeed * 3.6, limit: limit, at: lastFixTime) { voice.speak(warning) }
        let zoom = GuidanceZoom.level(speed: lastSpeed, distanceToManeuver: progress.distanceToNextManeuver, current: guidanceZoom)
        if zoom != guidanceZoom { guidanceZoom = zoom }

        if routePath != nil {
            let (alert, sentence) = hazardWatch.update(travelled: travelled, speed: lastSpeed)
            if alert != hazardAlert { hazardAlert = alert }
            if let sentence { voice.speak(sentence) }
        }

        // remaining[0] is the current step. The step after it begins with the maneuver the banner shows, and
        // the one after that with the follow-up maneuver; a roundabout's exit number is on the step it begins.
        let remaining: [RouteStep] = state.remainingSteps ?? []
        let following: RouteStep? = remaining.count > 1 ? remaining[1] : nil
        let afterFollowing: RouteStep? = remaining.count > 2 ? remaining[2] : nil
        let content = state.currentVisualInstruction?.primaryContent
        maneuverSymbol = ManeuverSymbols.symbol(
            type: content?.maneuverType, modifier: content?.maneuverModifier, roundaboutExitDegrees: content?.roundaboutExitDegrees
        )
        let laneInfo = state.currentVisualInstruction?.subContent?.laneInfo ?? content?.laneInfo ?? []
        lanes = laneInfo.map { lane in
            Lane(symbol: ManeuverSymbols.lane(lane.activeDirection ?? lane.directions.first), isActive: lane.active)
        }
        let maneuverIndex = remaining.count
        if maneuverIndex != lightSteps, let path = routePath {
            lightSteps = maneuverIndex
            maneuverAtLight = Self.nearLight(path.point(at: travelled + progress.distanceToNextManeuver).coordinate)
        }
        let onFerry = Self.isOnFerry(remaining.map { $0.visualInstructions.first?.primaryContent.maneuverType })
        let action = TurkishInstructions.action(
            type: content?.maneuverType,
            modifier: content?.maneuverModifier,
            roundaboutExitDegrees: content?.roundaboutExitDegrees,
            roundaboutExitNumber: following?.roundaboutExitNumber,
            leavingFerry: onFerry
        )
        let atLight = maneuverAtLight && TurkishInstructions.isTurn(type: content?.maneuverType, modifier: content?.maneuverModifier)
        let shown: String? = (atLight ? action.map(TurkishInstructions.atLights) : action) ?? content?.text
        actionText = offRoute ? "Rotadan çıktınız" : shown
        // The banner text from Valhalla is the next road's name for most maneuvers.
        var named: String?
        if let content, content.maneuverType != .arrive {
            named = Self.roadName(banner: content.text, nextInstruction: following?.instruction)
        }
        nextRoad = named.map { spellings[TurkishFold.fold($0)] ?? $0 }
        let road = state.currentRoadName.flatMap { $0.isEmpty ? nil : spellings[TurkishFold.fold($0)] ?? $0 }
        if road != currentRoad { currentRoad = road }

        let followingContent = following?.visualInstructions.first?.primaryContent
        let followUp: String? = following.flatMap { step in
            TurkishInstructions.followUp(
                type: followingContent?.maneuverType,
                modifier: followingContent?.maneuverModifier,
                roundaboutExitDegrees: followingContent?.roundaboutExitDegrees,
                roundaboutExitNumber: afterFollowing?.roundaboutExitNumber,
                after: step.distance
            )
        }
        var symbol: String?
        if !offRoute, followUp != nil {
            symbol = ManeuverSymbols.symbol(
                type: followingContent?.maneuverType, modifier: followingContent?.maneuverModifier,
                roundaboutExitDegrees: followingContent?.roundaboutExitDegrees
            )
        }
        if symbol != thenSymbol { thenSymbol = symbol }

        // Once per maneuver: through a roundabout the arrow runs on to the exit (the step after it).
        let steps = remaining.count
        if steps != arrowSteps, let path = routePath {
            // Until the step's banner is there, try again on the next fix.
            arrowSteps = content == nil ? nil : steps
            let type = content?.maneuverType
            let at = travelled + progress.distanceToNextManeuver
            let arrow = ManeuverArrow.wanted(type: type, modifier: content?.maneuverModifier)
                ? ManeuverArrow.lines(along: path, maneuverAt: at, after: ManeuverArrow.reach(type: type, nextStep: following?.distance))
                : []
            if !(arrow.isEmpty && maneuverArrow.isEmpty) { maneuverArrow = arrow }
        }

        // Nothing is said on a ferry: the only maneuver ahead is driving off it.
        guard !offRoute, !onFerry, let banner = content, let phrase = actionText else { return }
        // In a jam the car's own speed would pull every prompt in to its 30 km/h distance, on a motorway too;
        // the speed the route expects on this step keeps the road's scale.
        var expected: Double = 0
        if let current = remaining.first, current.duration > 0 { expected = current.distance / current.duration }
        announce(
            banner, phrase: phrase, step: remaining.count, distance: progress.distanceToNextManeuver,
            speed: max(lastSpeed, expected), followUp: followUp
        )
    }

    /// Speaks for the maneuver ahead when the planner says it is time.
    private func announce(
        _ content: VisualInstructionContent, phrase: String, step: Int, distance: Double, speed: Double, followUp: String?
    ) {
        let type = content.maneuverType
        let modifier = content.maneuverModifier
        guard !TurkishInstructions.isSilent(type: type, modifier: modifier) else { return }
        let arriving = type == .arrive
        // At the destination itself only its side is worth a sentence; "Hedefinize ulaştınız." follows on arrival.
        let hasNow = !arriving || TurkishInstructions.side(modifier) != nil
        guard let stage = planner.stage(
            step: step, distance: distance, speed: speed, hasNow: hasNow, holdsDistance: voice.isSpeaking
        ) else { return }
        let ahead: Double? = stage == .now ? nil : distance
        let sentence = arriving
            ? TurkishInstructions.arrival(distance: ahead, modifier: modifier)
            : TurkishInstructions.spoken(action: phrase, distance: ahead, road: nextRoad, then: followUp)
        if stage == .now {
            // Never queued behind a hazard, speed or status sentence: three seconds late is past the turn.
            voice.speakNow(sentence)
        } else {
            voice.speak(sentence)
        }
    }

    /// Sentences about the route itself (left it, rebuilt, could not be rebuilt), each at most once in 30 s.
    private func status(_ sentence: String) {
        if statusThrottle.allows(sentence, at: lastFixTime) { voice.speak(sentence) }
    }
}

/// Keeps a sentence about the route from repeating within 30 s of driving: a fix wavering around the
/// deviation threshold, or a new route the car leaves again at once, would otherwise say it every few seconds.
struct StatusThrottle {
    private var last: [String: Date] = [:]

    /// - Parameter time: the fix's timestamp, so the rhythm follows the drive rather than the wall clock.
    mutating func allows(_ sentence: String, at time: Date) -> Bool {
        if let previous = last[sentence], time.timeIntervalSince(previous) < 30 { return false }
        last[sentence] = time
        return true
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
