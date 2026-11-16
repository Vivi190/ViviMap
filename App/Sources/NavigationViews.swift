import AppCore
import DesignSystem
import NavigationEngine
import RoadHazards
import RoutingEngine
import SwiftUI
import TrafficEngine

/// Turn panel, placed and sized as drivers know it from Yandex Navigator: a compact blue panel in the top-left
/// corner with the maneuver arrow, the distance and the road to take, so most of the width stays map. The
/// maneuver right after it shows as a smaller arrow; lanes only when the data has them.
struct NavigationBanner: View {
    let navigation: NavigationSession

    var body: some View {
        let road = navigation.nextRoad.flatMap { $0.isEmpty ? nil : $0 }
        let action = navigation.actionText ?? "Rotayı izleyin"
        let distance = navigation.distanceToManeuver.map { Formatting.distance(meters: $0) }
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .center, spacing: Spacing.s) {
                Image(systemName: navigation.maneuverSymbol)
                    .font(.system(size: 36, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                if let then = navigation.thenSymbol {
                    // The next maneuver follows within 150 m: shown now, like the spoken "ardından".
                    Image(systemName: then)
                        .font(.system(size: 22, weight: .bold))
                        .opacity(0.7)
                }
            }
            if let distance {
                Text(distance)
                    .font(.system(size: 32, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // The road to take; the action in words only when there is no road name to show.
            Text(road ?? action)
                .font(.system(size: 17, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !navigation.lanes.isEmpty {
                HStack(spacing: Spacing.xs) {
                    ForEach(Array(navigation.lanes.enumerated()), id: \.offset) { _, lane in
                        Image(systemName: lane.symbol)
                            .font(.system(size: 20, weight: .bold))
                            .opacity(lane.isActive ? 1 : 0.4)
                    }
                }
                .padding(.top, Spacing.xs)
            }
            if navigation.isRerouting {
                Label("Yeni rota…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote.weight(.semibold))
                    .padding(.top, Spacing.xs)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 118, maxWidth: 220, alignment: .leading)
        .background(Color.atlasGuidance, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([distance, action, road].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityIdentifier("nav.banner")
    }
}

/// One slim row, as Yandex shows the trip: distance left, arrival time, time left and the end button, with the
/// traffic strip under them.
struct NavigationBottomBar: View {
    let navigation: NavigationSession
    /// From the last live-traffic round; nil = free-flow estimate, labelled as such.
    let trafficArrival: Date?
    /// On arrival: car parks around the destination (the first need on arriving in Istanbul); nil hides it.
    var onParking: (() -> Void)? = nil
    /// Slow stretches on the rest of the route (TrafficWatch), for the strip under the times.
    var trafficSections: [TrafficSection] = []
    /// The whole route on screen; highlighted while it is.
    var isOverview = false
    var onOverview: (() -> Void)? = nil
    let onEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(alignment: .center, spacing: Spacing.m) {
                if let onOverview, !navigation.hasArrived {
                    barButton("point.topleft.down.to.point.bottomright.curvepath", label: "Rotanın tamamı", isActive: isOverview, action: onOverview)
                }
                if let remaining = navigation.durationRemaining {
                    let arrival = trafficArrival ?? Date.now.addingTimeInterval(remaining)
                    let left = trafficArrival.map { max(0, $0.timeIntervalSinceNow) } ?? remaining
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        figure(Formatting.distance(meters: navigation.distanceRemaining ?? 0))
                        Spacer(minLength: Spacing.s)
                        figure(Formatting.clock(arrival))
                        Spacer(minLength: Spacing.s)
                        figure(Formatting.duration(seconds: left))
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text(navigation.hasArrived ? "Vardınız" : "Rota hazırlanıyor")
                        .font(.title3.weight(.semibold))
                    Spacer(minLength: 0)
                }
                if navigation.hasArrived, let onParking {
                    Button(action: onParking) {
                        Label("Otopark", systemImage: "parkingsign")
                            .font(.headline)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(Color.atlasAccent)
                    .accessibilityLabel(Text("Hedefin yakınındaki otoparklar"))
                }
                barButton("xmark", label: "Navigasyonu bitir", isActive: false, action: onEnd)
                    .accessibilityIdentifier("nav.end")
            }
            if navigation.durationRemaining != nil {
                if trafficArrival != nil {
                    let stretches = navigation.remainingFractions(of: trafficSections.map(\.coordinates))
                    RouteTrafficStrip(stretches: zip(stretches, trafficSections).compactMap { range, section in
                        range.map { (range: $0, level: section.level) }
                    })
                }
                // Always says where the time comes from; HERE's terms ask for the attribution where its data shows.
                Text(trafficArrival == nil ? "Trafik hariç" : "Canlı trafik · © HERE")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.s)
        .atlasCardSurface(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// The three trip figures share one size and weight: none shouts over the turn panel.
    private func figure(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 20, weight: .medium))
            .monospacedDigit()
            .contentTransition(.numericText())
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    /// A square button at an end of the strip (overview, end).
    private func barButton(_ systemImage: String, label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isActive ? Color.atlasAccent : Color.primary.opacity(0.75))
                .frame(width: 40, height: 40)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// Speed and the road's limit, top right. Its own view: the limit changes every few hundred metres, and read
/// here it redraws these circles instead of the whole screen (whose map rebuilds its layers on every update).
struct GuidanceSpeed: View {
    let navigation: NavigationSession

    var body: some View {
        SpeedOverlay(limit: navigation.speedLimit, staysVisible: true)
    }
}

/// Above the bottom bar: the road being driven, or the way back to the car while the map is not following it.
/// Its own view for the same reason as GuidanceSpeed (the road name changes often).
struct GuidanceRoadRow: View {
    let navigation: NavigationSession
    /// The driver moved the map or opened the route overview.
    let isDetached: Bool
    let onRecenter: () -> Void

    var body: some View {
        ZStack {
            if isDetached {
                // One clear way back (the map also returns by itself after a few seconds).
                Button(action: onRecenter) {
                    Label("Rotaya devam et", systemImage: "location.north.line.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Spacing.s)
                        .frame(minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("nav.recenter")
            } else if let road = navigation.currentRoad {
                CurrentRoadLabel(road: road)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The road being driven, centred above the bottom bar, as Waze and Yandex show it.
struct CurrentRoadLabel: View {
    let road: String

    var body: some View {
        Text(road)
            .font(.system(size: 16))
            .foregroundStyle(Color.primary.opacity(0.8))
            .lineLimit(1)
            .padding(.horizontal, Spacing.m)
            .frame(height: 32)
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
