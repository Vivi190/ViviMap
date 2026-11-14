import ActivityKit
import AppCore
import Foundation
import NavigationActivity
import NavigationEngine

/// Runs the Live Activity for a guided drive. Updates only when what it shows changes, at most every
/// 2 seconds (each update redraws the lock screen and Dynamic Island).
@MainActor
final class GuidanceActivity {
    /// Only the id is kept: `Activity` is not Sendable, so each call looks it up again off the main actor.
    private var activityID: String?
    private var shown: NavigationActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast
    /// The last call to ActivityKit; the next one waits for it so updates never arrive out of order.
    private var pending: Task<Void, Never>?

    /// Kept current by the session's own updates, not by SwiftUI: with the screen locked views may not
    /// refresh, and the lock screen is where this has to work.
    func start(destination: String, navigation: NavigationSession, traffic: TrafficWatch, arrival: Date) {
        end()
        // Off in Settings → Atlas → Live Activities: guidance simply runs without it.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = NavigationActivityAttributes.ContentState(
            symbol: "location.north.fill", distance: "", instruction: "Rota başladı", road: nil,
            arrival: arrival, arrivalWithTraffic: false
        )
        activityID = try? Activity.request(
            attributes: NavigationActivityAttributes(destination: destination),
            content: ActivityContent(state: state, staleDate: nil)
        ).id
        shown = state
        lastUpdate = .now
        navigation.onUpdate = { [weak self, weak traffic] session in
            guard let self else { return }
            if session.hasArrived {
                end()
            } else if let state = Self.state(session, trafficArrival: traffic?.arrival) {
                update(state)
            }
        }
    }

    func end() {
        guard let activityID else { return }
        self.activityID = nil
        shown = nil
        let previous = pending
        pending = Task.detached {
            await previous?.value
            await Self.activity(activityID)?.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Arrival rounded to the minute so the state only changes when the display would.
    static func state(_ navigation: NavigationSession, trafficArrival: Date?) -> NavigationActivityAttributes.ContentState? {
        guard navigation.isActive, let remaining = navigation.durationRemaining else { return nil }
        let arrival = trafficArrival ?? Date.now.addingTimeInterval(remaining)
        return NavigationActivityAttributes.ContentState(
            symbol: navigation.maneuverSymbol,
            distance: navigation.distanceToManeuver.map { Formatting.distance(meters: $0) } ?? "",
            instruction: navigation.actionText ?? "Rotayı izle",
            road: navigation.nextRoad,
            arrival: Date(timeIntervalSinceReferenceDate: (arrival.timeIntervalSinceReferenceDate / 60).rounded() * 60),
            arrivalWithTraffic: trafficArrival != nil
        )
    }

    private func update(_ state: NavigationActivityAttributes.ContentState) {
        guard let activityID, state != shown else { return }
        // A new maneuver goes out at once; distance countdowns at most every 2 s.
        let newManeuver = state.instruction != shown?.instruction || state.symbol != shown?.symbol
        guard newManeuver || Date.now.timeIntervalSince(lastUpdate) >= 2 else { return }
        shown = state
        lastUpdate = .now
        let previous = pending
        pending = Task.detached {
            await previous?.value
            await Self.activity(activityID)?.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private nonisolated static func activity(_ id: String) -> Activity<NavigationActivityAttributes>? {
        Activity<NavigationActivityAttributes>.activities.first { $0.id == id }
    }
}
