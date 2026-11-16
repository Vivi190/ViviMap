import SwiftUI

/// A round speed-limit sign: white disc, red ring, the limit in black. Exceeded, it fills red with the limit in
/// white, so the breach reads at a glance without a second element.
public struct SpeedLimitSign: View {
    private let limit: Int
    private let diameter: CGFloat
    private let isExceeded: Bool

    public init(limit: Int, diameter: CGFloat = 30, isExceeded: Bool = false) {
        self.limit = limit
        self.diameter = diameter
        self.isExceeded = isExceeded
    }

    public var body: some View {
        Text("\(limit)")
            .font(.system(size: diameter * (limit >= 100 ? 0.36 : 0.43), weight: .heavy).monospacedDigit())
            .foregroundStyle(isExceeded ? Color.white : Color.black)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(isExceeded ? Color.atlasCritical : Color.white))
            // The ring is stroked inside the disc, so the sign keeps its diameter.
            .overlay(Circle().strokeBorder(Color.atlasCritical, lineWidth: diameter * 0.08))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Hız sınırı \(limit)"))
    }
}
