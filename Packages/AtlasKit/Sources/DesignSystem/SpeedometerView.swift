import SwiftUI

/// Speed in a circle with the road's limit sign beside it, overlapping its edge, as navigation apps pair them.
/// Over the limit the number turns red and the sign fills red. Shows an en dash when there is no usable measurement and dims the
/// number when the receiver reports poor speed accuracy, so an unreliable value never looks authoritative.
public struct SpeedometerView: View {
    private let kmh: Int?
    private let isReliable: Bool
    private let limit: Int?
    @ScaledMetric(relativeTo: .title) private var scaledSize: CGFloat = 62

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
        let size = min(scaledSize, 80)
        HStack(spacing: -size * 0.12) {
            Text(kmh.map { "\($0)" } ?? "–")
                .font(.system(size: size * 0.42, weight: .bold).monospacedDigit())
                .foregroundStyle(isSpeeding ? Color.atlasCritical : isReliable ? Color.primary : Color.secondary)
                .contentTransition(.numericText(value: Double(kmh ?? 0)))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: size, height: size)
                .background(Color.atlasCard, in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 2)
            if let limit {
                SpeedLimitSign(limit: limit, diameter: size, isExceeded: isSpeeding)
                    .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 2)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: kmh)
        .animation(.snappy(duration: 0.25), value: limit)
        .animation(.snappy(duration: 0.25), value: isSpeeding)
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
