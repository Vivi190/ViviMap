import Foundation
import Testing
@testable import MapEngine

struct OfflineMapTests {
    @Test @MainActor func styleReadsTheShippedTilesAndFonts() throws {
        let packages = URL(fileURLWithPath: "/var/containers/Bundle/Application/X/Atlas.app/Offline", isDirectory: true)
        let original = try Data(contentsOf: MapAppearance.night.styleURL)
        let rewritten = try OfflineMap.rewrite(original, packages: packages)
        let style = try #require(try JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        let source = try #require((style["sources"] as? [String: Any])?["openmaptiles"] as? [String: Any])
        #expect(source["url"] as? String == "pmtiles://file:///var/containers/Bundle/Application/X/Atlas.app/Offline/istanbul.pmtiles")
        #expect(source["type"] as? String == "vector")
        #expect(style["glyphs"] as? String == "file:///var/containers/Bundle/Application/X/Atlas.app/Offline/fonts/{fontstack}/{range}.pbf")
        // Layers untouched: same count as the online style.
        let before = try #require(try JSONSerialization.jsonObject(with: original) as? [String: Any])
        #expect((style["layers"] as? [Any])?.count == (before["layers"] as? [Any])?.count)
    }
}
