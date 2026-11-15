import Foundation
import Testing
import UIKit
@testable import MapEngine

struct POIIconsTests {
    /// The style's POI layers (Tools/mapstyle) and the app's badges name the same classes: a class without a badge
    /// would show a bare label, a badge without a class would never show.
    @Test @MainActor func everyPlaceClassInTheStyleHasABadge() throws {
        for appearance in [MapAppearance.day, .night] {
            let style = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: appearance.styleURL)) as? [String: Any])
            let layers = try #require(style["layers"] as? [[String: Any]])
            let places = try #require(layers.first { $0["id"] as? String == "poi-all" })
            // filter: ["all", ["match", ["get", "class"], [classes…], true, false], ["has", "name"]]
            let filter = try #require(places["filter"] as? [Any])
            let match = try #require(filter[1] as? [Any])
            let classes = try #require(match[2] as? [String])
            #expect(Set(classes) == POIIcons.classes)
        }
    }

    @Test func aBadgeIsARoundImageOfTheAskedSize() {
        let badge = POIIcons.badge("fork.knife", color: .orange)
        #expect(badge.size == CGSize(width: 22, height: 22))
    }
}
