import Foundation

/// The map without a connection: the same style, reading the Istanbul tiles (PMTiles) and label fonts shipped
/// in the app instead of OpenFreeMap. Only builds made by the TestFlight workflow carry these packages.
@MainActor
public enum OfflineMap {
    /// Folder with istanbul.pmtiles and fonts/<stack>/<range>.pbf; nil in builds without the packages.
    public static let packages: URL? = {
        guard let folder = Bundle.main.url(forResource: "Offline", withExtension: nil),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("istanbul.pmtiles").path)
        else { return nil }
        return folder
    }()

    /// When the shipped Istanbul data was built ("13.11.2026"), from the release tag the TestFlight workflow
    /// writes next to it; nil in builds without the packages.
    public static let dataDate: String? = {
        guard let packages,
              let tag = try? String(contentsOf: packages.appendingPathComponent("version.txt"), encoding: .utf8)
        else { return nil }
        return date(fromTag: tag)
    }()

    /// "offline-data-20261113-3" → "13.11.2026".
    nonisolated static func date(fromTag tag: String) -> String? {
        let parts = tag.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-")
        guard parts.count >= 3, parts[2].count == 8, parts[2].allSatisfy(\.isNumber) else { return nil }
        let day = parts[2]
        return "\(day.suffix(2)).\(day.dropFirst(4).prefix(2)).\(day.prefix(4))"
    }

    private static var written: [MapAppearance: URL] = [:]

    /// The offline copy of `appearance`'s style, written to Caches once per launch (cheap, and never stale
    /// after an app update).
    public static func styleURL(_ appearance: MapAppearance) -> URL? {
        if let url = written[appearance] { return url }
        guard let packages, let data = try? Data(contentsOf: appearance.styleURL),
              let style = try? rewrite(data, packages: packages)
        else { return nil }
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("atlas-\(appearance.rawValue)-offline.json")
        guard (try? style.write(to: url, options: .atomic)) != nil else { return nil }
        written[appearance] = url
        return url
    }

    /// Points the OpenMapTiles source and the glyphs at the local files; layers stay untouched.
    nonisolated static func rewrite(_ data: Data, packages: URL) throws -> Data {
        guard var style = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var sources = style["sources"] as? [String: Any],
              var tiles = sources["openmaptiles"] as? [String: Any]
        else { throw CocoaError(.fileReadCorruptFile) }
        tiles["url"] = "pmtiles://" + packages.appendingPathComponent("istanbul.pmtiles").absoluteString
        sources["openmaptiles"] = tiles
        style["sources"] = sources
        style["glyphs"] = packages.appendingPathComponent("fonts").absoluteString + "/{fontstack}/{range}.pbf"
        return try JSONSerialization.data(withJSONObject: style)
    }
}
