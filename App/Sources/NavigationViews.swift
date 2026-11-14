import AppCore
import DesignSystem
import NavigationEngine
import RoadHazards
import RoutingEngine
import SwiftUI

/// Turn banner: maneuver arrow, distance, Turkish action and the road to take. Solid and high-contrast so
/// one glance is enough; lanes appear only when the routing data has them.
struct NavigationBanner: View {
    let navigation: NavigationSession

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .center, spacing: Spacing.m) {
                Image(systemName: navigation.maneuverSymbol)
                    .font(.system(size: 42, weight: .bold))
                    .frame(width: 60)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    if let distance = navigation.distanceToManeuver {
                        Text(Formatting.distance(meters: distance))
                            .font(.system(size: 34, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Text(navigation.actionText ?? "Rotayı izle")
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    if let road = navigation.nextRoad, !road.isEmpty {
                        Text(road)
                            .font(.headline)
                            .opacity(0.85)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if let then = navigation.thenSymbol {
                // The next maneuver follows within 150 m: show it now, like the spoken "ardından".
                HStack(spacing: Spacing.xs) {
                    Text("Sonra")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: then)
                        .font(.subheadline.weight(.bold))
                }
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .background(.white.opacity(0.18), in: Capsule())
                .padding(.leading, 72)
            }
            if !navigation.lanes.isEmpty {
                HStack(spacing: Spacing.s) {
                    ForEach(Array(navigation.lanes.enumerated()), id: \.offset) { _, lane in
                        Image(systemName: lane.symbol)
                            .font(.system(size: 20, weight: .bold))
                            .opacity(lane.isActive ? 1 : 0.35)
                    }
                }
                .padding(.leading, 72)
                .accessibilityLabel(Text("Şerit bilgisi"))
            }
            if navigation.isRerouting {
                Label("Yeni rota hesaplanıyor…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .foregroundStyle(.white)
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.atlasNavBanner, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nav.banner")
    }
}

/// Arrival time first (what the driver plans around), then remaining time and distance; mute and end.
struct NavigationBottomBar: View {
    let navigation: NavigationSession
    /// From the last live-traffic round; nil = free-flow estimate, labelled as such.
    let trafficArrival: Date?
    let onEnd: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            if let remaining = navigation.durationRemaining {
                let arrival = trafficArrival ?? Date.now.addingTimeInterval(remaining)
                let left = trafficArrival.map { max(0, $0.timeIntervalSinceNow) } ?? remaining
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // Three columns, figure over label, as navigation apps show them.
                    HStack(alignment: .top, spacing: Spacing.l) {
                        metric(arrival.formatted(date: .omitted, time: .shortened), "varış")
                        metric(Formatting.duration(seconds: left), "kalan")
                        metric(Formatting.distance(meters: navigation.distanceRemaining ?? 0), "mesafe")
                    }
                    .accessibilityElement(children: .combine)
                    // Always says where the time comes from.
                    Text(trafficArrival == nil ? "Trafik hariç" : "Canlı trafikle · © HERE")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(navigation.hasArrived ? "Vardın" : "Rota hazırlanıyor")
                    .font(.title3.weight(.semibold))
            }
            Spacer(minLength: 0)
            Button(role: .destructive, action: onEnd) {
                Text("Bitir")
                    .font(.headline)
                    .padding(.horizontal, Spacing.s)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Color.atlasCritical)
            .accessibilityIdentifier("nav.end")
        }
        .padding(Spacing.l)
        .atlasFloatingSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// The road being driven, centred above the bottom bar, as Waze and Yandex show it.
struct CurrentRoadLabel: View {
    let road: String

    var body: some View {
        Text(road)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.xs)
            .atlasFloatingSurface(in: Capsule())
            .frame(maxWidth: 200)
            .accessibilityLabel(Text("Şu anki yol: \(road)"))
            .accessibilityIdentifier("nav.road")
    }
}

/// "Hız kamerası · 250 m · 50" / "Kasis · 80 m" while the next one is in warning range.
struct HazardChip: View {
    let alert: HazardAlert

    var body: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: alert.kind == .camera ? "camera.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(alert.kind == .camera ? Color.atlasCritical : Color.atlasWarning)
            Text(alert.kind == .camera ? "Hız kamerası" : "Kasis")
            Text(Formatting.distance(meters: alert.distance))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if let limit = alert.maxspeed {
                SpeedLimitSign(limit: limit)
            }
        }
        .font(.headline)
        .padding(.horizontal, Spacing.m)
        .padding(.vertical, Spacing.s)
        .atlasFloatingSurface(in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nav.hazard")
    }
}

/// "Daha hızlı rota · 5 dk kazanç": one tap to switch; left alone, the current route stays.
struct RouteSuggestionBanner: View {
    let suggestion: TrafficWatch.Suggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: "arrow.triangle.branch")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.atlasAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Daha hızlı rota")
                    .font(.headline)
                Text("\(Formatting.duration(seconds: suggestion.gain)) kazanç" + (suggestion.option.mainRoads.first.map { " · \($0)" } ?? ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Kalsın", action: onDismiss)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            Button("Geç", action: onAccept)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("nav.suggestion.accept")
        }
        .font(.headline)
        .padding(Spacing.m)
        .atlasFloatingSurface(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task {
            // Unanswered while driving means "keep my route"; a tap cancels this first.
            if (try? await Task.sleep(for: .seconds(20))) != nil { onDismiss() }
        }
    }
}
