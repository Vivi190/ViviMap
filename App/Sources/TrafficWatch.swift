import CoreLocation
import NavigationEngine
import Observation
import RoutingEngine
import SearchEngine
import TrafficEngine

/// Live traffic while guiding (docs/architecture.md, ADR-5). Each round re-measures what is left of the
/// route (time and slow stretches); when the route is losing real time it also measures fresh alternatives
/// with the same provider and lets RerouteAdvisor decide whether a switch is worth suggesting. One import and
/// one flow request per round, up to two more imports when alternatives are measured. A stretch ahead that
/// the round finds closed is not a suggestion: guidance moves to a way round it at once.
@MainActor
@Observable
final class TrafficWatch {
    struct Suggestion {
        let option: RouteOption
        let gain: TimeInterval
        /// The candidate's time with traffic, shown as the arrival once it is taken.
        let duration: TimeInterval
        /// What the provider measured on the candidate: its speed limits go to guidance once it is taken.
        let estimate: TrafficEstimate
    }

    /// Which route the numbers belong to: a reroute or an accepted suggestion changes it.
    struct RouteKey: Equatable, Sendable {
        let count: Int
        let firstLatitude: Double
        let firstLongitude: Double
        let lastLatitude: Double
        let lastLongitude: Double

        init(_ coordinates: [CLLocationCoordinate2D]) {
            count = coordinates.count
            firstLatitude = coordinates.first?.latitude ?? 0
            firstLongitude = coordinates.first?.longitude ?? 0
            lastLatitude = coordinates.last?.latitude ?? 0
            lastLongitude = coordinates.last?.longitude ?? 0
        }
    }

    static let interval: Duration = .seconds(180)
    /// A measurement older than two rounds no longer counts as live.
    static let expiry: TimeInterval = 400
    /// Alternatives are only worth their requests when traffic costs at least this much on the current route.
    static let delayWorthAlternatives: TimeInterval = 180

    /// Arrival with traffic as of the last round; nil means no traffic data, and the bar says so.
    private(set) var arrival: Date?
    private(set) var suggestion: Suggestion?
    /// Slow stretches of the rest of the route, as of the last round.
    private(set) var sections: [TrafficSection] = []
    /// Traffic on the roads around the rest of the route, from the same answer as `sections` (the corridor asked
    /// for is wide enough): the map's traffic layer while guiding, at no extra request.
    private(set) var around: [TrafficSection] = []
    /// Closures, accidents and road works on the rest of the route, from the same answer as `arrival`: drawn on
    /// the map while guiding, and said once each by the session.
    private(set) var events: [TrafficIncident] = []

    @ObservationIgnored private var route: RouteKey?
    @ObservationIgnored private var measuredAt: Date?
    @ObservationIgnored private var round = 0
    @ObservationIgnored private var lastChange = Date.now
    @ObservationIgnored private let advisor = RerouteAdvisor()
    /// Points on a closed stretch of the route guidance started on, found on the route card too late to show
    /// a way round it there (`begin`); the first `check` takes that way.
    @ObservationIgnored private var knownClosed: [CLLocationCoordinate2D] = []
    /// Points on the closed stretches a way round has been asked for on this drive (`detour`).
    @ObservationIgnored private var asked: [CLLocationCoordinate2D] = []

    /// A closed stretch is known on the route and waits for `check`: it should come at once, not in a round's time.
    var hasKnownClosure: Bool { !knownClosed.isEmpty }

    func reset() {
        arrival = nil
        suggestion = nil
        sections = []
        around = []
        events = []
        route = nil
        measuredAt = nil
        round = 0
        lastChange = .now
        knownClosed = []
        asked = []
    }

    /// Guidance starts on a route the route card already measured: the bar opens with that time, those
    /// colours and those road events instead of the free-flow time and an empty road until the first round.
    /// - Parameter closed: points on a closed stretch the card found on this route after its time had been
    ///   measured (RouteTraffic.closedPoints); empty when it found none.
    func begin(
        on coordinates: [CLLocationCoordinate2D], duration: TimeInterval?, sections: [TrafficSection], around: [TrafficSection],
        events: [TrafficIncident], closed: [CLLocationCoordinate2D]
    ) {
        reset()
        route = RouteKey(coordinates)
        self.sections = sections
        self.around = around
        self.events = events
        knownClosed = closed
        if let duration {
            arrival = Date.now.addingTimeInterval(duration)
            measuredAt = .now
        }
    }

    /// Guidance is on `coordinates` now. False when nothing is known about that route (a reroute): what was
    /// shown belonged to another one and is dropped, and the next round should come soon.
    func follows(_ coordinates: [CLLocationCoordinate2D]) -> Bool {
        let key = RouteKey(coordinates)
        if key == route { return arrival != nil }
        route = key
        arrival = nil
        sections = []
        events = []
        measuredAt = nil
        suggestion = nil
        return false
    }

    /// One traffic round.
    /// - Returns: the route guidance was moved to because the road ahead is closed, nil when it stayed on its
    ///   route (a simulated drive has to follow the change).
    @discardableResult
    func check(
        navigation: NavigationSession,
        planner: RoutePlanner,
        traffic: any TrafficProvider,
        position: CLLocation,
        destination: Place
    ) async -> RouteOption? {
        // A closed stretch the route card already found on this route: no measuring first, the way round it.
        if hasKnownClosure {
            let closed = knownClosed
            knownClosed = []
            return await detour(around: closed, navigation: navigation, planner: planner, position: position, destination: destination)
        }
        let remaining = navigation.remainingRoute()
        guard remaining.count > 1 else { return nil }
        let measured = try? await traffic.estimate(remaining)
        guard navigation.isActive, !Task.isCancelled else { return nil }
        guard let current = measured else {
            // No answer for two rounds (no connection, the provider failing, the monthly budget spent): the
            // time on the bar would keep counting down as if it were live.
            if let measuredAt, Date.now.timeIntervalSince(measuredAt) > Self.expiry {
                arrival = nil
                sections = []
                events = []
            }
            return nil
        }
        arrival = Date.now.addingTimeInterval(current.duration)
        measuredAt = .now
        round += 1
        // The same answer has the speed limits and the road events on the rest of the route.
        navigation.setSpeedLimits(current.limits.map { RouteSpeedLimit($0) })
        events = current.events
        navigation.setRoadEvents(current.events.compactMap { RoadEvent($0) })
        if let flow = try? await traffic.flow(along: remaining), navigation.isActive, !Task.isCancelled {
            // Off the main actor: route edges × flow points grows with the route's length.
            sections = await Task.detached { RouteTraffic.sections(route: remaining, flow: flow) }.value
            around = AreaTraffic.sections(flow)
            // A closed stretch ahead comes before any faster route: another way from here, without asking.
            let closed = await Task.detached { RouteTraffic.closedPoints(route: remaining, flow: flow) }.value
            if navigation.isActive, !Task.isCancelled,
               let option = await detour(around: closed, navigation: navigation, planner: planner, position: position, destination: destination) {
                return option
            }
        }

        // Alternatives cost up to two more imports: only when traffic is costing real time, every second round.
        // Through the stop still ahead, if there is one: the router then answers with a single route.
        guard current.delay >= Self.delayWorthAlternatives, round.isMultiple(of: 2), navigation.isActive, !Task.isCancelled,
              let options = try? await planner.routes(
                  from: position, via: navigation.stops, to: destination.point, areaSpan: destination.areaSpan
              )
        else { return nil }
        // One running along the current road (≥ 85 %) is the same route.
        let shapes = options.map(\.coordinates)
        let shares = await Task.detached { shapes.map { RouteOverlap.share(of: $0, along: remaining) } }.value
        let distinct = zip(options, shares).filter { $0.1 < RouteOverlap.sameRoute }.map { $0.0 }
        var candidates: [RerouteAdvisor.Candidate] = []
        var estimates: [Int: TrafficEstimate] = [:]
        for option in distinct.prefix(2) {
            if let estimate = try? await traffic.estimate(option.coordinates) {
                candidates.append(.init(index: option.index, duration: estimate.duration))
                estimates[option.index] = estimate
            }
        }
        guard navigation.isActive, !Task.isCancelled,
              let pick = advisor.suggestion(
                  current: current.duration,
                  alternatives: candidates,
                  distanceToManeuver: navigation.distanceToManeuver,
                  sinceLastChange: Date.now.timeIntervalSince(lastChange)
              ),
              let option = distinct.first(where: { $0.index == pick.index }),
              let estimate = estimates[pick.index]
        else { return nil }
        let gain = current.duration - pick.duration
        suggestion = Suggestion(option: option, gain: gain, duration: pick.duration, estimate: estimate)
        lastChange = .now
        navigation.voice.speak("Daha hızlı bir rota var, \(max(1, Int((gain / 60).rounded()))) dakika kazanç.")
        return nil
    }

    /// The road ahead is closed: asks the router for the way from the car with the closed stretch excluded
    /// (the device's tiles first, as for any reroute) and moves guidance onto it with one sentence.
    /// - Parameter closed: points on the closed stretch (RouteTraffic.closedPoints).
    /// - Returns: the new route; nil, and guidance stays where it is, when the stretch was asked about before,
    ///   the router does not answer, or its answer is no way round.
    private func detour(
        around closed: [CLLocationCoordinate2D], navigation: NavigationSession, planner: RoutePlanner, position: CLLocation,
        destination: Place
    ) async -> RouteOption? {
        // Only for a stretch not asked about on this drive: one that no route can avoid is not asked about at
        // every round.
        let fresh = closed.filter { point in
            let here = CLLocation(latitude: point.latitude, longitude: point.longitude)
            return !asked.contains { here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) < 25 }
        }
        guard !fresh.isEmpty else { return nil }
        // With the earlier ones, which the router may have let go of since (RoutePlanner.fetch).
        planner.markClosed(asked + fresh)
        let excluded = planner.closedRoads
        // No answer: not remembered as asked, so the next round asks once more. Through the stop still ahead.
        guard let option = try? await planner.routes(
            from: position, via: navigation.stops, to: destination.point, areaSpan: destination.areaSpan, deviceFirst: true
        ).first, navigation.isActive, !Task.isCancelled else { return nil }
        asked += fresh
        // Only onto a route that keeps off every stretch known closed, the earlier ones too. When no such way
        // exists the router lets go of them all, and its answer may run through a stretch an earlier change of
        // route avoided: taking it would send the car back and forth between two closed roads, with a
        // sentence each time.
        guard RouteOverlap.share(of: excluded, along: option.coordinates, tolerance: 5) == 0 else { return nil }
        planner.closedRoads = excluded
        do {
            try navigation.switchRoute(to: option, from: position, announcing: "Yol kapalı. Rota değiştirildi.")
        } catch {
            return nil
        }
        // A suggestion measured against the route just left no longer applies.
        suggestion = nil
        lastChange = .now
        return option
    }

    /// The driver took the suggestion: guidance continues on the new route, with the time it was measured at.
    func accept(navigation: NavigationSession, from position: CLLocation) -> RouteOption? {
        guard let taken = suggestion else { return nil }
        suggestion = nil
        lastChange = .now
        do {
            try navigation.switchRoute(to: taken.option, from: position)
        } catch {
            return nil
        }
        route = RouteKey(taken.option.coordinates)
        arrival = Date.now.addingTimeInterval(taken.duration)
        measuredAt = .now
        // The colours belonged to the old route; the next round draws the new one's.
        sections = []
        navigation.setSpeedLimits(taken.estimate.limits.map { RouteSpeedLimit($0) })
        events = taken.estimate.events
        navigation.setRoadEvents(events.compactMap { RoadEvent($0) })
        return taken.option
    }

    func dismiss() {
        suggestion = nil
    }
}

extension RoutePlanner {
    /// A plan as the route card asks for it: the router's routes and, asked at the same moment, one that
    /// prefers local streets, of which at most three are offered (RouteOverlap.choice: the router's first, then
    /// the most different). The alternatives measured during guidance stay the router's own.
    func plan(from location: CLLocation, to place: Place) async throws -> [RouteOption] {
        try await routes(from: location, to: place.point, areaSpan: place.areaSpan, choosing: { shapes, own in
            RouteOverlap.choice(of: shapes, own: own)
        })
    }
}

extension RouteSpeedLimit {
    init(_ stretch: SpeedLimitStretch) {
        self.init(start: stretch.start, length: stretch.length, kmh: stretch.kmh)
    }
}

extension RoadEvent {
    /// nil for an event without a place on the line.
    init?(_ incident: TrafficIncident) {
        guard let start = incident.points.first else { return nil }
        let kind: RoadEvent.Kind = switch incident.kind {
        case .closure: .closure
        case .accident: .accident
        case .roadworks: .roadworks
        }
        self.init(kind: kind, coordinate: start)
    }
}
