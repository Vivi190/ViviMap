import SwiftUI

/// Vertical cluster of map buttons sharing one floating surface, separated by hairlines.
public struct MapControlGroup<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) { content }
            .frame(width: Metrics.controlWidth)
            .atlasFloatingSurface(in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

public struct MapControlButton: View {
    private let systemImage: String
    private let label: String
    private let isActive: Bool
    private let action: () -> Void

    public init(systemImage: String, label: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isActive ? Color.atlasAccent : Color.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Metrics.controlWidth, height: Metrics.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityShowsLargeContentViewer {
            Label(label, systemImage: systemImage)
        }
    }
}

/// Text-labelled variant (e.g. "3D") that matches the icon buttons' metrics.
public struct MapControlTextButton: View {
    private let title: String
    private let label: String
    private let isActive: Bool
    private let action: () -> Void

    public init(title: String, label: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.label = label
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isActive ? Color.atlasAccent : Color.primary)
                .frame(width: Metrics.controlWidth, height: Metrics.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(isActive ? "Açık" : "Kapalı"))
    }
}

public struct MapControlDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 0.5)
            .padding(.horizontal, Spacing.s)
    }
}
