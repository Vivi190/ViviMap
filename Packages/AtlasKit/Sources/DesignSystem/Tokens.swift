import SwiftUI
import UIKit

/// 4-pt spacing scale. Use these instead of literals so the rhythm stays consistent across screens.
public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
}

public enum Radius {
    public static let control: CGFloat = 14
}

public enum Metrics {
    /// Minimum hit target from the Human Interface Guidelines.
    public static let tapTarget: CGFloat = 44
    public static let controlWidth: CGFloat = 46
}

public extension Color {
    /// Route and brand accent. Calibrated against both map palettes and never used as a gradient.
    static let atlasAccent = Color(light: 0x1F6FEB, dark: 0x4C8DFF)
    static let atlasWarning = Color(light: 0xC2410C, dark: 0xFB923C)
    static let atlasCritical = Color(light: 0xD7263D, dark: 0xFF5A6A)
    /// Ground of the reading panels (atlasCardSurface).
    static let atlasCard = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
