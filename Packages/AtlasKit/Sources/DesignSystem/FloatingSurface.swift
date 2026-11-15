import SwiftUI

public extension View {
    /// Small chrome over the map (search pill, buttons, chips, speed): opaque like the reading panels, with a
    /// lighter shadow. Glass took on the map's colours underneath and looked unfinished next to opaque cards.
    func atlasFloatingSurface(in shape: some Shape) -> some View {
        background(Color.atlasCard, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 2)
    }

    /// Panels people read at a glance (place, route, guidance): opaque, white by day and graphite at night. Glass
    /// lets the map's colours through behind the text; over the sea a route card turned cyan.
    func atlasCardSurface(in shape: some Shape) -> some View {
        background(Color.atlasCard, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
    }
}
