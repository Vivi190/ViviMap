import AppCore
import DesignSystem
import NavigationEngine
import RoadHazards
import RoutingEngine
import SwiftUI
import TrafficEngine

/// Turn card: the maneuver on a blue tile, the distance large, the road to take in bold and the Turkish action
/// under it. An opaque card like the other reading panels (dark at night); lanes only when the data has them.
struct NavigationBanner: View {
    let navigation: NavigationSession

    /// The rows under the headline start where the text does, past the tile.
    private static let indent: CGFloat = 64 + Spacing.m

    var body: some View {
        // The road leads when there is one ("Hürriyet Caddesi"); the action ("Göbekten sağa çık") follows it.
        let road = navigation.nextRoad.flatMap { $0.isEmpty ? nil : $0 }
        let action = navigation.actionText ?? "Rotayı izle"
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .center, spacing: Spacing.m) {
                Image(systemName: navigation.maneuverSymbol)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 64, height: 64)
                    .background(Color.atlasAccent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    if let distance = navigation.distanceToManeuver {
                        Text(Formatting.distance(meters: distance))
                            .font(.system(size: 32, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Text(road ?? action)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                    if road != nil {
                        Text(action)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
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
                .foregroundStyle(Color.atlasAccent)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .background(Color.atlasAccent.opacity(0.12), in: Capsule())
                .padding(.leading, Self.indent)
            }
            if !navigation.lanes.isEmpty {
                HStack(spacing: Spacing.s) {
                    ForEach(Array(navigation.lanes.enumerated()), id: \.offset) { _, lane in
                        Image(systemName: lane.symbol)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(lane.isActive ? Color.atlasAccent : Color.secondary.opacity(0.45))
                    }
                }
                .padding(.leading, Self.indent)
                .accessibilityLabel(Text("Şerit bilgisi"))
            }
            if navigation.isRerouting {
                Label("Yeni rota hesaplanıyor…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.atlasAccent)
            }
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atlasCardSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("nav.banner")
    }
}

/// The time left large, as Yandex shows it, with the arrival time and distance beside it and the traffic strip
/// under; a small end button instead of the big red one.
struct NavigationBottomBar: View {
    let navigation: NavigationSession
    /// From the last live-traffic round; nil = free-flow estimate, labelled as such.
    let trafficArrival: Date?
    /// On arrival: car parks around the destination (the first need on arriving in Istanbul); nil hides it.
    var onParking: (() -> Void)? = nil
    /// Slow stretches on the rest of the route (TrafficWatch), for the strip under the times.
    var trafficSections: [TrafficSection] = []
    let onEnd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            if let remaining = navigation.durationRemaining {
                let arrival = trafficArrival ?? Date.now.addingTimeInterval(remaining)
                let left = trafficArrival.map { max(0, $0.timeIntervalSinceNow) } ?? remaining
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text(Formatting.duration(seconds: left))
                            .font(.system(size: 28, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("\(arrival.formatted(date: .omitted, time: .shortened)) · \(Formatting.distance(meters: navigation.distanceRemaining ?? 0))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .accessibilityElement(children: .combine)
                    if trafficArrival != nil {
                        let stretches = navigation.remainingFractions(of: trafficSections.map(\.coordinates))
                        RouteTrafficStrip(stretches: zip(stretches, trafficSections).compactMap { range, section in
                            range.map { (range: $0, level: section.level) }
                        })
                    }
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
            if navigation.hasArrived, let onParking {
                Button(action: onParking) {
                    Label("Otopark", systemImage: "parkingsign")
                        .font(.headline)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Color.atlasAccent)
                .accessibilityLabel(Text("Hedefin yakınındaki otoparklar"))
            }
            Button(role: .destructive, action: onEnd) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(Color.atlasCritical)
            .accessibilityLabel(Text("Navigasyonu bitir"))
            .accessibilityIdentifier("nav.end")
        }
        .padding(Spacing.l)
        .atlasCardSurface(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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

/// The rest of the route as a strip, as Yandex shows it: from here (left) to the destination (right), flowing
/// in light route blue, slow stretches coloured where they lie.
struct RouteTrafficStrip: View {
    let stretches: [(range: ClosedRange<Double>, level: TrafficSection.Level)]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Color.atlasAccent.opacity(0.3)
                ForEach(stretches.indices, id: \.self) { index in
                    let stretch = stretches[index]
                    Self.color(stretch.level)
                        .frame(width: max(3, geometry.size.width * (stretch.range.upperBound - stretch.range.lowerBound)))
                        .offset(x: geometry.size.width * stretch.range.lowerBound)
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true) // the arrival time already carries the traffic
    }

    private static func color(_ level: TrafficSection.Level) -> Color {
        switch level {
        case .free: Color.atlasAccent.opacity(0.3)
        case .slow: Color(red: 0.96, green: 0.62, blue: 0.04)
        case .heavy: Color(red: 0.86, green: 0.15, blue: 0.15)
        case .stopped: Color(red: 0.50, green: 0.11, blue: 0.11)
        }
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
        .atlasCardSurface(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .task {
            // Unanswered while driving means "keep my route"; a tap cancels this first.
            if (try? await Task.sleep(for: .seconds(20))) != nil { onDismiss() }
        }
    }
}
