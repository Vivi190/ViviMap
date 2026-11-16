import CoreLocation
import MapLibre
import MapLibreSwiftDSL
import UIKit

/// The city traffic lines, kept on the map outside swiftui-dsl, for two reasons. The DSL rebuilds every layer it
/// owns on each SwiftUI update, which for thousands of traffic stretches is wasted work on every camera change;
/// here the layers are added once per style load and only their data changes when new traffic arrives. And the
/// DSL has no line offset, which is what lets the two directions of a road run side by side at every zoom: each
/// stretch is drawn a few points to the right of its own direction (traffic keeps right), thin, with a rim in
/// the map's ground colour between them.
@MainActor
public final class TrafficOverlay {
    private var lines: [TrafficLine] = []
    private var signature = 0

    public init() {}

    /// Called on every map update with what should be on screen; touches the map only when that changed.
    func show(_ lines: [TrafficLine], in style: MLNStyle?) {
        let signature = Self.signature(of: lines)
        guard signature != self.signature else { return }
        self.lines = lines
        self.signature = signature
        if let style { fill(style) }
    }

    /// A style finished loading (first load, day/night, offline): its layers start empty and get the lines the
    /// overlay already holds. Under the route, the labels and the 3D buildings (drawn after them, a line would
    /// show through a building in front of its road): below the first layer that is ours, a label or extruded.
    func add(to style: MLNStyle, night: Bool) {
        let below = style.layers.first {
            $0 is MLNSymbolStyleLayer || $0 is MLNFillExtrusionStyleLayer || $0.identifier.hasPrefix("atlas-")
        }
        for group in Group.allCases {
            guard style.source(withIdentifier: group.source) == nil else { continue }
            let source = MLNShapeSource(identifier: group.source, features: [MLNPolylineFeature](), options: nil)
            style.addSource(source)
            let rim = makeLayer("\(group.source)-rim", source, color: night ? Self.rimNight : Self.rimDay, widths: group.widths.mapValues { $0 + 1.6 }, offsets: group.offsets)
            insert(rim, below: below, in: style)
            // Worst on top.
            for level in TrafficLine.Level.allCases {
                let layer = makeLayer("\(group.source)-\(level.rawValue)", source, color: Self.color(level, night: night), widths: group.widths, offsets: group.offsets)
                layer.predicate = NSPredicate(format: "level == %d", level.rawValue)
                insert(layer, below: below, in: style)
            }
        }
        fill(style)
    }

    private func fill(_ style: MLNStyle) {
        for group in Group.allCases {
            guard let source = style.source(withIdentifier: group.source) as? MLNShapeSource else { continue }
            var features: [MLNPolylineFeature] = []
            for line in lines where line.isMajor == (group == .major) && line.coordinates.count > 1 {
                let feature = MLNPolylineFeature(coordinates: line.coordinates)
                feature.attributes = ["level": line.level.rawValue]
                features.append(feature)
            }
            source.shape = MLNShapeCollectionFeature(shapes: features)
        }
    }

    private func makeLayer(
        _ identifier: String, _ source: MLNShapeSource, color: UIColor, widths: [Double: Double], offsets: [Double: Double]
    ) -> MLNLineStyleLayer {
        let layer = MLNLineStyleLayer(identifier: identifier, source: source)
        layer.lineCap = NSExpression(forConstantValue: MLNLineCap.round.rawValue)
        layer.lineJoin = NSExpression(forConstantValue: MLNLineJoin.round.rawValue)
        layer.lineColor = NSExpression(forConstantValue: color)
        layer.lineWidth = Self.byZoom(widths)
        layer.lineOffset = Self.byZoom(offsets)
        return layer
    }

    private func insert(_ layer: MLNStyleLayer, below: MLNStyleLayer?, in style: MLNStyle) {
        if let below { style.insertLayer(layer, below: below) } else { style.addLayer(layer) }
    }

    private static func byZoom(_ stops: [Double: Double]) -> NSExpression {
        NSExpression(
            forMLNInterpolating: .zoomLevelVariable, curveType: .linear, parameters: nil,
            stops: NSExpression(forConstantValue: stops)
        )
    }

    /// Cheap identity of what is drawn: the number of lines and each one's level and size. A refresh that only
    /// moved colours along the same roads changes it too.
    nonisolated static func signature(of lines: [TrafficLine]) -> Int {
        var hasher = Hasher()
        hasher.combine(lines.count)
        for line in lines {
            hasher.combine(line.level)
            hasher.combine(line.isMajor)
            hasher.combine(line.coordinates.count)
        }
        if let first = lines.first?.coordinates.first {
            hasher.combine(first.latitude)
            hasher.combine(first.longitude)
        }
        return hasher.finalize()
    }

    /// Main roads (HERE functional classes 1–2) and the rest get their own widths and offsets, measured per
    /// direction against how Yandex Maps draws the same Istanbul roads at each zoom.
    enum Group: CaseIterable {
        case minor, major

        var source: String { self == .major ? "atlas-area-major" : "atlas-area-minor" }

        var widths: [Double: Double] {
            self == .major
                ? [10: 2.4, 12: 2.8, 15: 2.6, 16.5: 3.4, 18: 4.5]
                : [10: 1.8, 15: 1.8, 16.5: 3.0, 18: 4.0]
        }

        var offsets: [Double: Double] {
            self == .major
                ? [10: 1.5, 13: 2.3, 14.5: 3.4, 16.5: 7.5, 18: 15]
                : [10: 1.3, 13: 1.6, 14.5: 2.6, 16.5: 5, 18: 10.5]
        }
    }

    nonisolated static func color(_ level: TrafficLine.Level, night: Bool) -> UIColor {
        switch level {
        case .free: night ? POIIcons.rgb(0x2F9A4B) : UIColor(red: 0.20, green: 0.76, blue: 0.30, alpha: 1)
        case .slow: night ? POIIcons.rgb(0xC79A0A) : UIColor(red: 1.00, green: 0.75, blue: 0.18, alpha: 1)
        case .heavy: night ? POIIcons.rgb(0xDD4A35) : UIColor(red: 0.96, green: 0.33, blue: 0.25, alpha: 1)
        case .stopped: night ? POIIcons.rgb(0xA02B08) : UIColor(red: 0.63, green: 0.17, blue: 0.11, alpha: 1)
        }
    }

    private static let rimDay = UIColor.white
    private static let rimNight = POIIcons.rgb(0x202838)
}
