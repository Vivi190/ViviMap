import SwiftUI

/// Compact status pill shown over the map only while something needs the driver's attention.
public struct StatusChip: View {
    public enum Tone: Sendable {
        case neutral, warning, critical
    }

    private let systemImage: String
    private let title: String
    private let tone: Tone

    public init(systemImage: String, title: String, tone: Tone = .neutral) {
        self.systemImage = systemImage
        self.title = title
        self.tone = tone
    }

    public var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(color)
        .lineLimit(1)
        .padding(.horizontal, Spacing.m)
        .frame(minHeight: 34)
        .atlasFloatingSurface(in: Capsule())
    }

    private var color: Color {
        switch tone {
        case .neutral: .primary
        case .warning: .atlasWarning
        case .critical: .atlasCritical
        }
    }
}
