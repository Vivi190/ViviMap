import CoreLocation
import MapLibre
import UIKit

/// Bumps, cameras and traffic lights on the map as small signs, as Yandex draws them (bundled OSM data,
/// RoadHazards). Thousands of fixed points, so they go straight into the style once per style load: as a
/// swiftui-dsl source they would be rebuilt on every map update.
public struct RoadMarks: Sendable {
    public let bumps: [CLLocationCoordinate2D]
    public let cameras: [CLLocationCoordinate2D]
    public let lights: [CLLocationCoordinate2D]

    public init(bumps: [CLLocationCoordinate2D], cameras: [CLLocationCoordinate2D], lights: [CLLocationCoordinate2D]) {
        self.bumps = bumps
        self.cameras = cameras
        self.lights = lights
    }

    public static let none = RoadMarks(bumps: [], cameras: [], lights: [])

    /// Under the labels and over the roads; the route, which swiftui-dsl puts under the first label layer,
    /// ends up under these too, so a light on the route stays visible.
    func add(to style: MLNStyle) {
        let below = style.layers.first { $0 is MLNSymbolStyleLayer }
        let kinds: [(name: String, points: [CLLocationCoordinate2D], from: Float, image: UIImage)] = [
            ("light", lights, 16, Self.trafficLight()),
            ("bump", bumps, 15, Self.bumpSign()),
            ("camera", cameras, 13, POIIcons.badge("camera.fill", color: POIIcons.rgb(0xE53935), diameter: 16)),
        ]
        for kind in kinds where !kind.points.isEmpty {
            let id = "atlas-road-\(kind.name)"
            guard style.source(withIdentifier: id) == nil else { continue }
            style.setImage(kind.image, forName: id)
            let features = kind.points.map { point -> MLNPointFeature in
                let feature = MLNPointFeature()
                feature.coordinate = point
                return feature
            }
            let source = MLNShapeSource(identifier: id, features: features, options: nil)
            style.addSource(source)
            let layer = MLNSymbolStyleLayer(identifier: id, source: source)
            layer.iconImageName = NSExpression(forConstantValue: id)
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true) // labels are not pushed away
            layer.minimumZoomLevel = kind.from
            if let below { style.insertLayer(layer, below: below) } else { style.addLayer(layer) }
        }
    }

    /// A small upright signal head: red, amber, green.
    static func trafficLight() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 10, height: 20)).image { _ in
            let body = UIBezierPath(roundedRect: CGRect(x: 0.75, y: 0.75, width: 8.5, height: 18.5), cornerRadius: 3)
            POIIcons.rgb(0x2B2B2E).setFill()
            body.fill()
            UIColor.white.setStroke()
            body.lineWidth = 1.5
            body.stroke()
            for (index, hex) in [0xFF3B30, 0xFFCC00, 0x34C759].enumerated() {
                POIIcons.rgb(hex).setFill()
                UIBezierPath(ovalIn: CGRect(x: 2.8, y: 3 + CGFloat(index) * 4.9, width: 4.4, height: 4.4)).fill()
            }
        }
    }

    /// The Turkish "kasis" warning sign: a hump in a red-bordered triangle.
    static func bumpSign() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 18, height: 16)).image { _ in
            let triangle = UIBezierPath()
            triangle.move(to: CGPoint(x: 9, y: 1.5))
            triangle.addLine(to: CGPoint(x: 16.8, y: 14.8))
            triangle.addLine(to: CGPoint(x: 1.2, y: 14.8))
            triangle.close()
            triangle.lineJoinStyle = .round
            UIColor.white.setFill()
            triangle.fill()
            POIIcons.rgb(0xE53935).setStroke()
            triangle.lineWidth = 2
            triangle.stroke()
            let hump = UIBezierPath()
            hump.move(to: CGPoint(x: 5, y: 12.5))
            hump.addQuadCurve(to: CGPoint(x: 13, y: 12.5), controlPoint: CGPoint(x: 9, y: 6.5))
            hump.close()
            POIIcons.rgb(0x1C1C1E).setFill()
            hump.fill()
        }
    }
}
