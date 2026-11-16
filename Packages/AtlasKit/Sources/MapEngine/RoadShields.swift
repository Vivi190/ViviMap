import MapLibre
import UIKit

/// Sign-like shields for road numbers (the style's label-road-ref layer): green for motorways (O-4), blue for
/// the rest (D-100), as on Turkish signs. Stretchable, so the style's icon-text-fit sizes them to the number.
/// And the arrow of one-way streets (the style's road-oneway layers).
enum RoadShields {
    static func register(in style: MLNStyle) {
        style.setImage(shield(POIIcons.rgb(0x1E7F4F)), forName: "shield-motorway")
        style.setImage(shield(POIIcons.rgb(0x2463B8)), forName: "shield-road")
        style.setImage(onewayArrow(), forName: "oneway")
    }

    /// A thin arrow pointing right: the style lays icons along a line in its direction and turns this one
    /// round for streets mapped against theirs. One grey for both palettes, readable on the day's white
    /// streets and on the night's dark ones.
    static func onewayArrow() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 14, height: 8)).image { _ in
            let arrow = UIBezierPath()
            arrow.move(to: CGPoint(x: 1, y: 4))
            arrow.addLine(to: CGPoint(x: 13, y: 4))
            arrow.move(to: CGPoint(x: 9.5, y: 1))
            arrow.addLine(to: CGPoint(x: 13, y: 4))
            arrow.addLine(to: CGPoint(x: 9.5, y: 7))
            arrow.lineWidth = 1.4
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            POIIcons.rgb(0x8C96A8).setStroke()
            arrow.stroke()
        }
    }

    /// A rounded sign with a thin white rim; the corners keep their shape and the middle stretches around the
    /// text (MapLibre reads the cap insets as the stretchable part).
    static func shield(_ color: UIColor) -> UIImage {
        let size = CGSize(width: 18, height: 16)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size)
            UIColor.white.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 4).fill()
            color.setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 1.25, dy: 1.25), cornerRadius: 3).fill()
        }
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5), resizingMode: .stretch)
    }
}
