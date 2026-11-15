import SwiftUI

public extension View {
    /// Chrome that floats over the map: Liquid Glass on iOS 26+, a thin material with a hairline before that.
    /// Use only for controls that sit directly on the map, never for full panels.
    func atlasFloatingSurface(in shape: some Shape) -> some View {
        modifier(FloatingSurface(shape: shape))
    }

    /// Panels people read at a glance (place, route, guidance): opaque, white by day and graphite at night, as
    /// Yandex draws them. Glass let the map through and tinted the text's ground (CI 3b-route: the sea turned the
    /// route card cyan).
    func atlasCardSurface(in shape: some Shape) -> some View {
        background(Color.atlasCard, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
    }
}

private struct FloatingSurface<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 4)
        }
    }
}
