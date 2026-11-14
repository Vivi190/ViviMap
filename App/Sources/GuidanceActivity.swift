import ActivityKit
import Foundation
import NavigationActivity

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

    func start(destination: String, state: NavigationActivityAttributes.ContentState) {
        end()
        // Off in Settings → Atlas → Live Activities: guidance simply runs without it.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activityID = try? Activity.request(
            attributes: NavigationActivityAttributes(destination: destination),
            content: ActivityContent(state: state, staleDate: nil)
        ).id
        shown = state
        lastUpdate = .now
    }

    func update(_ state: NavigationActivityAttributes.ContentState) {
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

    private nonisolated static func activity(_ id: String) -> Activity<NavigationActivityAttributes>? {
        Activity<NavigationActivityAttributes>.activities.first { $0.id == id }
    }
}
