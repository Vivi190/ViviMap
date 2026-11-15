import CoreLocation
import UIKit

/// A candidate route's time on the map, as Apple Maps and Yandex label them: a bubble on a stretch only that
/// route takes; the chosen route's bubble is blue, and tapping another one chooses that route.
public struct RouteLabel: Sendable {
    /// The route's index (RouteOption.index), handed back when its bubble is tapped.
    public let route: Int
    public let coordinate: CLLocationCoordinate2D
    public let text: String
    public let isSelected: Bool

    public init(route: Int, coordinate: CLLocationCoordinate2D, text: String, isSelected: Bool) {
        self.route = route
        self.coordinate = coordinate
        self.text = text
        self.isSelected = isSelected
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

    /// The bubble: the chosen route's in route blue with a white rim; the others white by day, graphite at
    /// night, so they read as "also possible" without competing.
    static func bubble(_ text: String, selected: Bool, night: Bool) -> UIImage {
        let font = UIFont.systemFont(ofSize: 15, weight: .bold)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let margin: CGFloat = 4 // room for the shadow
        let body = CGRect(x: margin, y: margin, width: ceil(textSize.width) + 20, height: 28)
        let fill = selected ? POIIcons.rgb(0x1F6FEB) : night ? POIIcons.rgb(0x2C2C2E) : .white
        let rim = selected ? UIColor.white : night ? POIIcons.rgb(0x48484A) : POIIcons.rgb(0xD1D1D6)
        let ink = selected ? UIColor.white : night ? POIIcons.rgb(0xF2F2F7) : POIIcons.rgb(0x1C1C1E)
        let size = CGSize(width: body.width + margin * 2, height: body.height + margin * 2)
        return UIGraphicsImageRenderer(size: size).image { context in
            let path = UIBezierPath(roundedRect: body, cornerRadius: 9)
            context.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.3).cgColor)
            fill.setFill()
            path.fill()
            context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            rim.setStroke()
            path.lineWidth = selected ? 2 : 1
            path.stroke()
            (text as NSString).draw(
                at: CGPoint(x: body.midX - textSize.width / 2, y: body.midY - textSize.height / 2),
                withAttributes: [.font: font, .foregroundColor: ink]
            )
        }
    }
}
