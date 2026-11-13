import SwiftUI

/// Round speed badge. Shows an en dash when there is no usable measurement and dims the number when the
/// receiver reports poor speed accuracy, so an unreliable value never looks authoritative.
public struct SpeedometerView: View {
    private let kmh: Int?
    private let isReliable: Bool
    @ScaledMetric(relativeTo: .title) private var scaledDiameter: CGFloat = 68

    public init(kmh: Int?, isReliable: Bool) {
        self.kmh = kmh
        self.isReliable = isReliable
    }

    public var body: some View {
        let diameter = min(scaledDiameter, 96)
        VStack(spacing: 0) {
            Text(kmh.map(String.init) ?? "–")
                .font(.system(size: diameter * 0.4, weight: .bold).monospacedDigit())
                .foregroundStyle(isReliable ? Color.primary : Color.secondary)
                .contentTransition(.numericText(value: Double(kmh ?? 0)))
            Text("km/sa")
                .font(.system(size: diameter * 0.15, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: diameter, height: diameter)
        .atlasFloatingSurface(in: Circle())
        .animation(.snappy(duration: 0.25), value: kmh)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Hız"))
        .accessibilityValue(Text(accessibilityValue))
    }

    private var accessibilityValue: String {
        guard let kmh else { return "Bilinmiyor" }
        return isReliable ? "Saatte \(kmh) kilometre" : "Yaklaşık saatte \(kmh) kilometre, düşük doğruluk"
    }
}
