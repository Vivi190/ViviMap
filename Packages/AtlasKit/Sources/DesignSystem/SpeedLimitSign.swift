import SwiftUI

/// A round speed-limit sign: white disc, red ring, the limit in black.
public struct SpeedLimitSign: View {
    private let limit: Int
    private let diameter: CGFloat

    public init(limit: Int, diameter: CGFloat = 30) {
        self.limit = limit
        self.diameter = diameter
    }

    public var body: some View {
        Text("\(limit)")
            .font(.system(size: diameter * (limit >= 100 ? 0.36 : 0.43), weight: .heavy).monospacedDigit())
            .foregroundStyle(.black)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(.white))
            .overlay(Circle().stroke(Color.atlasCritical, lineWidth: diameter * 0.11))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Hız sınırı \(limit)"))
    }
}
