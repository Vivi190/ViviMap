import Foundation
import Valhalla

/// On-device routing over the Istanbul tiles shipped with the app (Rallista/valhalla-mobile, Valhalla 3.9.0,
/// MIT). It answers the very request body Ferrostar builds for the server, so its OSRM-format reply goes
/// through the same parser.
public final class OfflineRouter: @unchecked Sendable {
    private let tiles: URL
    private let lock = NSLock()
    private var engine: Valhalla?

    init(tiles: URL) {
        self.tiles = tiles
    }

    /// Present only in builds that carry the offline packages (the TestFlight workflow pulls them in).
    public static let bundled: OfflineRouter? = {
        guard let tiles = Bundle.main.url(forResource: "Offline", withExtension: nil)?.appendingPathComponent("valhalla_tiles.tar"),
              FileManager.default.fileExists(atPath: tiles.path)
        else { return nil }
        return OfflineRouter(tiles: tiles)
    }()

    /// The bundled router as RoutePlanner's offline hook (nil without the packages). Spelled out with its type:
    /// inferring it inline in a default argument crashed the type checker.
    public static var bundledRoute: (@Sendable (Data) async throws -> Data)? {
        guard let router = bundled else { return nil }
        return { body in try await router.route(body) }
    }

    /// Valhalla's OSRM-format answer for a /route request body. Runs off the main thread; the engine is built
    /// on first use (it maps the tile extract) and then reused.
    public func route(_ body: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) { [self] in try routeNow(body) }.value
    }

    private func routeNow(_ body: Data) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        let ready = try self.engine ?? Valhalla(ValhallaConfig(tileExtractTar: tiles))
        self.engine = ready
        return Data(try ready.route(rawRequest: String(decoding: body, as: UTF8.self)).utf8)
    }
}
