import ActivityKit
import NavigationActivity
import SwiftUI
import WidgetKit

@main
struct AtlasWidgets: WidgetBundle {
    var body: some Widget {
        NavigationLiveActivity()
    }
}

/// Next maneuver and arrival where a glance is enough: lock screen, Dynamic Island, CarPlay Dashboard (iOS 26).
struct NavigationLiveActivity: Widget {
    /// Same blue as the in-app navigation banner.
    static let banner = Color(red: 0.07, green: 0.29, blue: 0.64)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NavigationActivityAttributes.self) { context in
            LockScreenView(state: context.state, destination: context.attributes.destination)
                .activityBackgroundTint(Self.banner)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.symbol)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.distance)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.instruction)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.road ?? context.attributes.destination)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("Varış \(context.state.arrival.formatted(date: .omitted, time: .shortened))")
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: context.state.symbol)
                    .font(.headline.weight(.bold))
            } compactTrailing: {
                Text(context.state.distance)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.symbol)
            }
            .keylineTint(Self.banner)
        }
    }
}

struct LockScreenView: View {
    let state: NavigationActivityAttributes.ContentState
    let destination: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: state.symbol)
                .font(.system(size: 36, weight: .bold))
                .frame(width: 48)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(state.distance)
                        .font(.title.weight(.bold))
                        .monospacedDigit()
                    Text(state.instruction)
                        .font(.headline)
                        .lineLimit(1)
                }
                Text(state.road ?? destination)
                    .font(.subheadline)
                    .opacity(0.85)
                    .lineLimit(1)
                Text("Varış \(state.arrival.formatted(date: .omitted, time: .shortened))\(state.arrivalWithTraffic ? " · trafikle" : "")")
                    .font(.caption.weight(.medium))
                    .opacity(0.8)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}
