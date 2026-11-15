import SwiftUI

/// Speed tile, as Yandex shows it: the number large on a rounded square, the road's limit sign above it, a red rim
/// when over the limit. Shows an en dash when there is no usable measurement and dims the number when the
/// receiver reports poor speed accuracy, so an unreliable value never looks authoritative.
public struct SpeedometerView: View {
    private let kmh: Int?
    private let isReliable: Bool
    private let limit: Int?
    @ScaledMetric(relativeTo: .title) private var scaledSize: CGFloat = 64

    /// - Parameter limit: the road's speed limit when the map data has one; shown as a sign, and the speed
    ///   turns red more than 5 km/h above it (GPS speed noise would make it flicker right at the limit).
    public init(kmh: Int?, isReliable: Bool, limit: Int? = nil) {
        self.kmh = kmh
        self.isReliable = isReliable
        self.limit = limit
    }

    private var isSpeeding: Bool {
        guard let kmh, let limit, isReliable else { return false }
        return kmh > limit + 5
    }

    public var body: some View {
        let size = min(scaledSize, 88)
        let tile = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        // Above, not on a corner: the tile keeps its width, so the road name beside it stays clear.
        VStack(spacing: Spacing.s) {
            if let limit {
                SpeedLimitSign(limit: limit, diameter: size * 0.66)
                    .shadow(color: .black.opacity(0.16), radius: 6, x: 0, y: 2)
                    .transition(.scale.combined(with: .opacity))
            }
            VStack(spacing: -2) {
                Text(kmh.map(String.init) ?? "–")
                    .font(.system(size: size * 0.44, weight: .bold).monospacedDigit())
                    .foregroundStyle(isSpeeding ? Color.atlasCritical : isReliable ? Color.primary : Color.secondary)
                    .contentTransition(.numericText(value: Double(kmh ?? 0)))
                Text("km/sa")
                    .font(.system(size: size * 0.16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
            .atlasFloatingSurface(in: tile)
            .overlay {
                if isSpeeding { tile.strokeBorder(Color.atlasCritical, lineWidth: 2.5) }
            }
        }
        .animation(.snappy(duration: 0.25), value: kmh)
        .animation(.snappy(duration: 0.25), value: limit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Hız"))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var accessibilityValue: String {
        guard let kmh else { return "Bilinmiyor" }
        let speed = isReliable ? "Saatte \(kmh) kilometre" : "Yaklaşık saatte \(kmh) kilometre, düşük doğruluk"
        guard let limit else { return speed }
        return speed + ", sınır \(limit)" + (isSpeeding ? ", sınırın üstünde" : "")
    }
}
