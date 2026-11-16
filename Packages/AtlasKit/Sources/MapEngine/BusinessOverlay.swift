import CoreLocation
import MapLibre
import MapLibreSwiftDSL

/// A business of the search index to show on the map (MapEngine stays independent of the search engine).
public struct MapBusiness: Sendable {
    /// The id the index lists it with, handed back when its badge is tapped.
    public let id: String
    public let name: String
    /// The base map's poi class whose badge it wears ("restaurant", "grocery", "bank").
    public let badge: String
    public let coordinate: CLLocationCoordinate2D

    public init(id: String, name: String, badge: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.badge = badge
        self.coordinate = coordinate
    }
}

/// The businesses of the search index as badges at street zoom. The base map shows the places OpenStreetMap
/// has, about a tenth of a street's shops; these are the rest, drawn so that the two cannot be told apart: the
/// layer takes its look (badge by class, label colours and sizes) from the base map's own place layer.
/// Kept on the style itself like the traffic lines (TrafficOverlay): its data changes when the map comes to
/// rest, not with every SwiftUI update.
@MainActor
public final class BusinessOverlay {
    nonisolated static let layerID = "atlas-businesses"
    private static let sourceID = "atlas-businesses"
    /// The base map's layer of every place badge, whose look this one copies.
    private static let modelLayerID = "poi-all"

    private var places: [MapBusiness] = []
    private var signature = 0

    public init() {}

    /// Called on every map update with what should be on screen; touches the map only when that changed.
    func show(_ places: [MapBusiness], in style: MLNStyle?) {
        let signature = Self.signature(of: places)
        guard signature != self.signature else { return }
        self.places = places
        self.signature = signature
        if let style { fill(style) }
    }

    /// A style finished loading: its layer starts empty and gets the businesses the overlay already holds.
    func add(to style: MLNStyle) {
        guard style.source(withIdentifier: Self.sourceID) == nil,
              let model = style.layer(withIdentifier: Self.modelLayerID) as? MLNSymbolStyleLayer else { return }
        let source = MLNShapeSource(identifier: Self.sourceID, features: [MLNPointFeature](), options: nil)
        style.addSource(source)
        let layer = MLNSymbolStyleLayer(identifier: Self.layerID, source: source)
        layer.iconImageName = model.iconImageName
        layer.text = model.text
        layer.textFontNames = model.textFontNames
        layer.textFontSize = model.textFontSize
        layer.textAnchor = model.textAnchor
        layer.textOffset = model.textOffset
        layer.maximumTextWidth = model.maximumTextWidth
        layer.textColor = model.textColor
        layer.textHaloColor = model.textHaloColor
        layer.textHaloWidth = model.textHaloWidth
        layer.minimumZoomLevel = model.minimumZoomLevel
        // Under the base map's own badges: where the two overlap, the surveyed one is the one drawn.
        style.insertLayer(layer, below: model)
        fill(style)
    }

    private func fill(_ style: MLNStyle) {
        guard let source = style.source(withIdentifier: Self.sourceID) as? MLNShapeSource else { return }
        let features: [MLNPointFeature] = places.map { place in
            let feature = MLNPointFeature()
            feature.coordinate = place.coordinate
            // The attributes the base map's places carry, so the copied look and a tap read them the same way.
            feature.attributes = ["name": place.name, "class": place.badge, "id": place.id]
            return feature
        }
        source.shape = MLNShapeCollectionFeature(shapes: features)
    }

    /// Cheap identity of what is drawn: how many, and the first and last of them.
    nonisolated static func signature(of places: [MapBusiness]) -> Int {
        var hasher = Hasher()
        hasher.combine(places.count)
        hasher.combine(places.first?.id)
        hasher.combine(places.last?.id)
        return hasher.finalize()
    }
}
