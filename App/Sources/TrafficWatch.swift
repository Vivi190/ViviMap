import CoreLocation
import NavigationEngine
import Observation
import RoutingEngine
import SearchEngine
import TrafficEngine

/// Live traffic while guiding (docs/architecture.md, ADR-5). Each round re-measures what is left of the
/// route (time and slow stretches); when the route is losing real time it also measures fresh alternatives
/// with the same provider and lets RerouteAdvisor decide whether a switch is worth suggesting. One import and
/// one flow request per round, up to two more imports when alternatives are measured.
@MainActor
@Observable
final class TrafficWatch {
    struct Suggestion {
        let option: RouteOption
        let gain: TimeInterval
        /// The candidate's time with traffic, shown as the arrival once it is taken.
        let duration: TimeInterval
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

    @ObservationIgnored private var route: RouteKey?
    @ObservationIgnored private var measuredAt: Date?
    @ObservationIgnored private var round = 0
    @ObservationIgnored private var lastChange = Date.now
    @ObservationIgnored private let advisor = RerouteAdvisor()

    func reset() {
        arrival = nil
        suggestion = nil
        sections = []
        around = []
        route = nil
        measuredAt = nil
        round = 0
        lastChange = .now
    }

    /// Guidance starts on a route the route card already measured: the bar opens with that time and those
    /// colours instead of the free-flow time until the first round.
    func begin(
        on coordinates: [CLLocationCoordinate2D], duration: TimeInterval?, sections: [TrafficSection], around: [TrafficSection]
    ) {
        reset()
        route = RouteKey(coordinates)
        self.sections = sections
        self.around = around
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
        measuredAt = nil
        suggestion = nil
        return false
    }

    func check(
        navigation: NavigationSession,
        planner: RoutePlanner,
        traffic: any TrafficProvider,
        position: CLLocation,
        destination: Place
    ) async {
        let remaining = navigation.remainingRoute()
        guard remaining.count > 1 else { return }
        let measured = try? await traffic.estimate(remaining)
        guard navigation.isActive, !Task.isCancelled else { return }
        guard let current = measured else {
            // No answer for two rounds (no connection, the provider failing, the monthly budget spent): the
            // time on the bar would keep counting down as if it were live.
            if let measuredAt, Date.now.timeIntervalSince(measuredAt) > Self.expiry {
                arrival = nil
                sections = []
            }
            return
        }
        arrival = Date.now.addingTimeInterval(current.duration)
        measuredAt = .now
        round += 1
        if let flow = try? await traffic.flow(along: remaining), navigation.isActive, !Task.isCancelled {
            // Off the main actor: route edges × flow points grows with the route's length.
            sections = await Task.detached { RouteTraffic.sections(route: remaining, flow: flow) }.value
            around = AreaTraffic.sections(flow)
        }

        // Alternatives cost up to two more imports: only when traffic is costing real time, every second round.
        guard current.delay >= Self.delayWorthAlternatives, round.isMultiple(of: 2), navigation.isActive, !Task.isCancelled,
              let options = try? await planner.routes(from: position, to: destination.point, areaSpan: destination.areaSpan)
        else { return }
        // One running along the current road (≥ 85 %) is the same route.
        let shapes = options.map(\.coordinates)
        let shares = await Task.detached { shapes.map { RouteOverlap.share(of: $0, along: remaining) } }.value
        let distinct = zip(options, shares).filter { $0.1 < RouteOverlap.sameRoute }.map { $0.0 }
        var candidates: [RerouteAdvisor.Candidate] = []
        for option in distinct.prefix(2) {
            if let estimate = try? await traffic.estimate(option.coordinates) {
                candidates.append(.init(index: option.index, duration: estimate.duration))
            }
        }
        guard navigation.isActive, !Task.isCancelled,
              let pick = advisor.suggestion(
                  current: current.duration,
                  alternatives: candidates,
                  distanceToManeuver: navigation.distanceToManeuver,
                  sinceLastChange: Date.now.timeIntervalSince(lastChange)
              ),
              let option = distinct.first(where: { $0.index == pick.index })
        else { return }
        let gain = current.duration - pick.duration
        suggestion = Suggestion(option: option, gain: gain, duration: pick.duration)
        lastChange = .now
        navigation.voice.speak("Daha hızlı bir rota var, \(max(1, Int((gain / 60).rounded()))) dakika kazanç.")
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
        return taken.option
    }

    func dismiss() {
        suggestion = nil
    }
}
