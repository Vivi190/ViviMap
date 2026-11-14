import CoreLocation
import NavigationEngine
import Observation
import RoutingEngine
import SearchEngine
import TrafficEngine

/// Live traffic while guiding (docs/architecture.md, ADR-5). Each round re-measures what is left of the
/// route (time and slow stretches) and fresh alternatives with the same provider, then lets RerouteAdvisor
/// decide whether a switch is worth suggesting. Up to three imports and one flow request per round, one
/// round every few minutes.
@MainActor
@Observable
final class TrafficWatch {
    struct Suggestion {
        let option: RouteOption
        let gain: TimeInterval
    }

    static let interval: Duration = .seconds(180)

    /// Arrival with traffic as of the last round; nil means no traffic data, and the bar says so.
    private(set) var arrival: Date?
    private(set) var suggestion: Suggestion?
    /// Slow stretches of the rest of the route, as of the last round.
    private(set) var sections: [TrafficSection] = []

    @ObservationIgnored private var lastChange = Date.now
    @ObservationIgnored private let advisor = RerouteAdvisor()

    func reset() {
        arrival = nil
        suggestion = nil
        sections = []
        lastChange = .now
    }

    func check(
        navigation: NavigationSession,
        planner: RoutePlanner,
        traffic: any TrafficProvider,
        position: CLLocation,
        destination: Place
    ) async {
        let remaining = navigation.remainingRoute()
        guard remaining.count > 1, let current = try? await traffic.estimate(remaining), navigation.isActive else { return }
        arrival = Date.now.addingTimeInterval(current.duration)
        if let flow = try? await traffic.flow(along: remaining), navigation.isActive {
            sections = RouteTraffic.sections(route: remaining, flow: flow)
        }

        // Fresh candidates from here; one running along the current road (≥ 85 %) is the same route.
        guard let options = try? await planner.routes(from: position, to: destination.point, areaSpan: destination.areaSpan) else { return }
        let distinct = options.filter { RouteOverlap.share(of: $0.coordinates, along: remaining) < RouteOverlap.sameRoute }
        var candidates: [RerouteAdvisor.Candidate] = []
        for option in distinct.prefix(2) {
            if let estimate = try? await traffic.estimate(option.coordinates) {
                candidates.append(.init(index: option.index, duration: estimate.duration))
            }
        }
        guard navigation.isActive,
              let pick = advisor.suggestion(
                  current: current.duration,
                  alternatives: candidates,
                  distanceToManeuver: navigation.distanceToManeuver,
                  sinceLastChange: Date.now.timeIntervalSince(lastChange)
              ),
              let option = distinct.first(where: { $0.index == pick.index })
        else { return }
        let gain = current.duration - pick.duration
        suggestion = Suggestion(option: option, gain: gain)
        lastChange = .now
        navigation.voice.speak("Daha hızlı bir rota var, \(max(1, Int((gain / 60).rounded()))) dakika kazanç.")
    }

    /// The driver took the suggestion: guidance continues on the new route.
    func accept(navigation: NavigationSession, from position: CLLocation) -> RouteOption? {
        guard let option = suggestion?.option else { return nil }
        suggestion = nil
        lastChange = .now
        do {
            try navigation.switchRoute(to: option, from: position)
        } catch {
            return nil
        }
        // Re-measured on the next round; the old arrival and colours belonged to the old route.
        arrival = nil
        sections = []
        return option
    }

    func dismiss() {
        suggestion = nil
    }
}
