import Foundation

/// Monthly cap on paid-API requests, kept below HERE's free tier so a bug or a busy month cannot run up
/// a bill. Free tier (research §6, Nov 2026): Route Import 2 500/month, Traffic flow 5 000/month.
///
/// shortcut: counted on the device, for the one phone that uses the key (the owner's decision, 2026-11-16):
/// the caps are nine tenths of the free tier. A second phone on the key would double the use, and deleting
/// the app starts the count anew within the month. Move the count to a small proxy (ADR-7) before anyone
/// else tests.
public final class RequestBudget: @unchecked Sendable {
    public enum Kind: String, Sendable {
        case routeImport
        /// Traffic along a route (route card, guidance).
        case flow
        /// The city traffic layer. Both flow kinds and incidents are HERE Traffic requests: 1 900 + 1 900 + 700
        /// stay under the 5 000 free ones, and the layer cannot eat into guidance.
        case areaFlow
        /// Road events on the city layer.
        case incidents
    }

    public static let shared = RequestBudget()

    private let defaults: UserDefaults
    private let limits: [Kind: Int]
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(
        defaults: UserDefaults = .standard,
        // Nine tenths of the free tier: 2 250 of 2 500 imports, and 4 500 of 5 000 traffic calls split between
        // the route, the city layer and its road events. At half of it the layer ran out after 33 hours of an
        // open map, and guidance after about 50 hours of driving.
        limits: [Kind: Int] = [.routeImport: 2_250, .flow: 1_900, .areaFlow: 1_900, .incidents: 700],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.limits = limits
        self.now = now
    }

    /// Counts one request; false, and nothing counted, once this month's cap is reached.
    public func spend(_ kind: Kind) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = Self.key(kind, now())
        let used = defaults.integer(forKey: key)
        guard used < limits[kind, default: 0] else { return false }
        defaults.set(used + 1, forKey: key)
        return true
    }

    public func used(_ kind: Kind) -> Int {
        defaults.integer(forKey: Self.key(kind, now()))
    }

    /// One counter per calendar month (UTC), so the count starts over with each billing month.
    static func key(_ kind: Kind, _ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "atlas.here.%@.%04ld-%02ld", kind.rawValue, parts.year ?? 0, parts.month ?? 0)
    }
}
