import MapLibre
import UIKit

/// Apple Maps-style place badges: a white SF Symbol on a circle in the category's colour, one image per
/// OpenMapTiles poi class, registered on the style as "poi-<class>". The style's POI layers ask for them and
/// colour the labels to match (Tools/mapstyle/build_styles.py, POI_GROUPS: keep the two lists in step).
/// "charging" and "place" are classes of the app's own: a charger, and a business without a kind.
enum POIIcons {
    private static let groups: [(color: Int, symbols: [String: String])] = [
        (0xFF9500, ["restaurant": "fork.knife", "fast_food": "takeoutbag.and.cup.and.straw.fill",
                    "cafe": "cup.and.saucer.fill", "bar": "wineglass.fill", "beer": "mug.fill", "ice_cream": "fork.knife"]),
        (0xF2B705, ["shop": "bag.fill", "grocery": "cart.fill", "clothing_store": "tshirt.fill", "bakery": "cart.fill",
                    "butcher": "cart.fill", "alcohol_shop": "wineglass.fill"]),
        (0xFF2D55, ["hairdresser": "scissors", "laundry": "washer.fill"]),
        (0xFF3B30, ["hospital": "cross.fill", "pharmacy": "pills.fill", "doctors": "stethoscope", "dentist": "stethoscope",
                    "veterinary": "pawprint.fill"]),
        (0xA2845E, ["school": "graduationcap.fill", "college": "graduationcap.fill", "library": "books.vertical.fill"]),
        (0x007AFF, ["railway": "tram.fill", "harbor": "ferry.fill", "ferry_terminal": "ferry.fill",
                    "fuel": "fuelpump.fill", "charging": "bolt.car.fill", "parking": "parkingsign",
                    "aerialway": "cablecar.fill", "car": "car.fill"]),
        (0x34C759, ["park": "leaf.fill", "zoo": "pawprint.fill", "campsite": "tent.fill", "golf": "figure.golf",
                    "playground": "figure.and.child.holdinghands"]),
        (0x8E8E93, ["place_of_worship": "building.columns.fill"]),
        (0xAF52DE, ["attraction": "star.fill", "art_gallery": "photo.artframe", "castle": "building.columns.fill",
                    "museum": "building.columns.fill", "theatre": "theatermasks.fill", "cinema": "film.fill"]),
        (0x5856D6, ["lodging": "bed.double.fill"]),
        (0x6E7B91, ["town_hall": "building.2.fill", "post": "envelope.fill", "police": "shield.fill",
                    "fire_station": "flame.fill", "bank": "banknote.fill", "atm": "creditcard.fill",
                    "office": "briefcase.fill"]),
        (0x30B0C7, ["stadium": "sportscourt.fill", "swimming": "figure.pool.swim", "sports_centre": "figure.run"]),
        (0x8A93A3, [plainClass: "circle.fill"]),
    ]
    /// The class of a business without a kind: a small dot, so that it does not weigh as much on the map as
    /// the places a driver looks for.
    private static let plainClass = "place"

    /// The poi classes that have a badge.
    static var classes: Set<String> { Set(groups.flatMap { $0.symbols.keys }) }

    /// Every badge on `style`; again after each style load (a day/night switch reloads it).
    static func register(in style: MLNStyle) {
        for group in groups {
            let color = rgb(group.color)
            for (poiClass, symbol) in group.symbols {
                style.setImage(badge(symbol, color: color, diameter: poiClass == plainClass ? 14 : 22), forName: "poi-\(poiClass)")
            }
        }
    }

    /// The circle with a thin white ring, so badges stay apart from each other and from the map; a symbol this
    /// iOS lacks leaves a plain circle.
    static func badge(_ symbol: String, color: UIColor, diameter: CGFloat = 22) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter)).image { _ in
            let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect).fill()
            color.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
            let config = UIImage.SymbolConfiguration(pointSize: diameter * 0.46, weight: .semibold)
            guard let glyph = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            let size = glyph.size
            glyph.draw(in: CGRect(x: (diameter - size.width) / 2, y: (diameter - size.height) / 2,
                                  width: size.width, height: size.height))
        }
    }

    static func rgb(_ hex: Int) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
