import AppCore
import DesignSystem
import NavigationEngine
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
    let onEnd: () -> Void
    @State private var isMuted = false

    var body: some View {
        HStack(spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                if let remaining = navigation.durationRemaining {
                    Text(Date.now.addingTimeInterval(remaining).formatted(date: .omitted, time: .shortened))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text("\(Formatting.duration(seconds: remaining)) · \(Formatting.distance(meters: navigation.distanceRemaining ?? 0)) · trafik hariç")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                } else {
                    Text(navigation.hasArrived ? "Vardın" : "Rota hazırlanıyor")
                        .font(.title3.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
            Button {
                isMuted.toggle()
                navigation.voice.isMuted = isMuted
            } label: {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text(isMuted ? "Sesli yönlendirmeyi aç" : "Sesli yönlendirmeyi kapat"))
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
}
