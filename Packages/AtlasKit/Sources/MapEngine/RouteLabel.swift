import CoreLocation
import UIKit

/// A candidate route on the map, labelled as Yandex and Apple Maps label them: a callout on a stretch only that
/// route takes. The chosen route's says its time and distance on blue; the others say how much slower (red) or
/// faster (green) they are, and tapping one chooses that route.
public struct RouteLabel: Sendable {
    public enum Tone: Sendable {
        case selected, slower, faster
    }

    /// The route's index (RouteOption.index), handed back when its callout is tapped.
    public let route: Int
    public let coordinate: CLLocationCoordinate2D
    public let text: String
    /// A second line (the chosen route's distance); nil for a one-line callout.
    public let detail: String?
    public let tone: Tone

    public var isSelected: Bool { tone == .selected }

    public init(route: Int, coordinate: CLLocationCoordinate2D, text: String, detail: String? = nil, tone: Tone) {
        self.route = route
        self.coordinate = coordinate
        self.text = text
        self.detail = detail
        self.tone = tone
    }

    /// Where to put a route's time: its point farthest from the other candidates, so bubbles do not pile up on
    /// shared roads; its middle when it is the only one. Sampled, so long routes stay cheap.
    public static func place(on route: [CLLocationCoordinate2D], awayFrom others: [[CLLocationCoordinate2D]]) -> CLLocationCoordinate2D? {
        guard !route.isEmpty else { return nil }
        let lines = others.filter { $0.count > 1 }.map { sample($0, to: 150) }
        guard !lines.isEmpty else { return route[route.count / 2] }
        return sample(route, to: 80).map { ($0, distance($0, lines)) }.max { $0.1 < $1.1 }?.0
    }

    /// At most `count` + 1 points of `line`, its ends kept.
    static func sample(_ line: [CLLocationCoordinate2D], to count: Int) -> [CLLocationCoordinate2D] {
        let step = max(1, (line.count + count - 1) / count)
        let indices = Array(stride(from: 0, to: line.count, by: step))
        return (indices.last == line.count - 1 ? indices : indices + [line.count - 1]).map { line[$0] }
    }

    private static func distance(_ p: CLLocationCoordinate2D, _ lines: [[CLLocationCoordinate2D]]) -> Double {
        lines.map { line in zip(line, line.dropFirst()).map { segment(p, $0.0, $0.1) }.min() ?? .infinity }.min() ?? .infinity
    }

    /// Metres from `p` to the segment a–b, flat-earth (fine at city scale).
    private static func segment(_ p: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let metresPerLon = 111_320 * cos(p.latitude * .pi / 180), metresPerLat = 110_540.0
        let ax = (a.longitude - p.longitude) * metresPerLon, ay = (a.latitude - p.latitude) * metresPerLat
        let dx = (b.longitude - a.longitude) * metresPerLon, dy = (b.latitude - a.latitude) * metresPerLat
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared == 0 ? 0 : max(0, min(1, -(ax * dx + ay * dy) / lengthSquared))
        return hypot(ax + t * dx, ay + t * dy)
    }

    /// The callout: a rounded box with a small tail under its middle (the image is anchored at its bottom, so the
    /// tail points at the route). Blue with white text for the chosen route; white by day and graphite at night
    /// for the others, their difference in red or green.
    static func bubble(_ label: RouteLabel, night: Bool) -> UIImage {
        let titleFont = UIFont.systemFont(ofSize: 16, weight: .bold)
        let detailFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let fill: UIColor
        let ink: UIColor
        switch label.tone {
        case .selected:
            fill = POIIcons.rgb(0x1F6FEB)
            ink = .white
        case .slower:
            fill = night ? POIIcons.rgb(0x2C2C2E) : .white
            ink = POIIcons.rgb(night ? 0xFF6B6B : 0xD7263D)
        case .faster:
            fill = night ? POIIcons.rgb(0x2C2C2E) : .white
            ink = POIIcons.rgb(night ? 0x4CD964 : 0x1E9E4A)
        }
        let title = label.text as NSString
        let titleSize = title.size(withAttributes: [.font: titleFont])
        let detailSize = label.detail.map { ($0 as NSString).size(withAttributes: [.font: detailFont]) } ?? .zero
        let margin: CGFloat = 4 // room for the shadow
        let tail: CGFloat = 7
        let body = CGRect(
            x: margin, y: margin,
            width: ceil(max(titleSize.width, detailSize.width)) + 22,
            height: ceil(titleSize.height + detailSize.height) + 10
        )
        let size = CGSize(width: body.width + margin * 2, height: body.height + tail + margin * 2)
        return UIGraphicsImageRenderer(size: size).image { context in
            let pointer = UIBezierPath()
            pointer.move(to: CGPoint(x: body.midX - 7, y: body.maxY - 2))
            pointer.addLine(to: CGPoint(x: body.midX, y: body.maxY + tail))
            pointer.addLine(to: CGPoint(x: body.midX + 7, y: body.maxY - 2))
            pointer.close()
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            fill.setFill()
            pointer.fill()
            UIBezierPath(roundedRect: body, cornerRadius: 10).fill()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            title.draw(at: CGPoint(x: body.minX + 11, y: body.minY + 5), withAttributes: [.font: titleFont, .foregroundColor: ink])
            if let detail = label.detail {
                (detail as NSString).draw(
                    at: CGPoint(x: body.minX + 11, y: body.minY + 5 + titleSize.height),
                    withAttributes: [.font: detailFont, .foregroundColor: ink.withAlphaComponent(0.85)]
                )
            }
        }
    }
}
