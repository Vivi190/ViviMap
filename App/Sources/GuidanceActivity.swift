import ActivityKit
import Foundation
import NavigationActivity

/// Runs the Live Activity for a guided drive. Updates only when what it shows changes, at most every
/// 2 seconds (each update redraws the lock screen and Dynamic Island).
@MainActor
final class GuidanceActivity {
    private var activity: Activity<NavigationActivityAttributes>?
    private var shown: NavigationActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast

    func start(destination: String, state: NavigationActivityAttributes.ContentState) {
        end()
        // Off in Settings → Atlas → Live Activities: guidance simply runs without it.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(
            attributes: NavigationActivityAttributes(destination: destination),
            content: ActivityContent(state: state, staleDate: nil)
        )
        shown = state
        lastUpdate = .now
    }

    func update(_ state: NavigationActivityAttributes.ContentState) {
        guard let activity, state != shown else { return }
        // A new maneuver goes out at once; distance countdowns at most every 2 s.
        let newManeuver = state.instruction != shown?.instruction || state.symbol != shown?.symbol
        guard newManeuver || Date.now.timeIntervalSince(lastUpdate) >= 2 else { return }
        shown = state
        lastUpdate = .now
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        shown = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
