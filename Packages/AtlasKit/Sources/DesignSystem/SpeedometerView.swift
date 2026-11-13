import SwiftUI

/// Round speed badge. Shows an en dash when there is no usable measurement and dims the number when the
/// receiver reports poor speed accuracy, so an unreliable value never looks authoritative.
public struct SpeedometerView: View {
    private let kmh: Int?
    private let isReliable: Bool
    private let limit: Int?
    @ScaledMetric(relativeTo: .title) private var scaledDiameter: CGFloat = 68

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
        let diameter = min(scaledDiameter, 96)
        VStack(spacing: 0) {
            Text(kmh.map(String.init) ?? "–")
                .font(.system(size: diameter * 0.4, weight: .bold).monospacedDigit())
                .foregroundStyle(isSpeeding ? Color.atlasCritical : isReliable ? Color.primary : Color.secondary)
                .contentTransition(.numericText(value: Double(kmh ?? 0)))
            Text("km/sa")
                .font(.system(size: diameter * 0.15, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: diameter, height: diameter)
        .atlasFloatingSurface(in: Circle())
        .overlay(alignment: .topTrailing) {
            if let limit {
                SpeedLimitSign(limit: limit, diameter: diameter * 0.48)
                    .offset(x: diameter * 0.18, y: -diameter * 0.12)
                    .transition(.scale.combined(with: .opacity))
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
