import SwiftUI

public extension View {
    /// Chrome that floats over the map: Liquid Glass on iOS 26+, a thin material with a hairline before that.
    /// Use only for controls that sit directly on the map, never for full panels.
    func atlasFloatingSurface(in shape: some Shape) -> some View {
        modifier(FloatingSurface(shape: shape))
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
