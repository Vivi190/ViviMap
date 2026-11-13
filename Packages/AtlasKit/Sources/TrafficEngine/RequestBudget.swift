import Foundation

/// Monthly cap on paid-API requests, kept below HERE's free tier so a bug or a busy month cannot run up
/// a bill. Free tier (research §6, Nov 2026): Route Import 2 500/month, Traffic flow 5 000/month.
///
/// shortcut: counted per device; the default caps are under half the free tier so two phones on one key
/// still fit. Move the count to a small proxy (ADR-7) if more people test.
public final class RequestBudget: @unchecked Sendable {
    public enum Kind: String, Sendable {
        case routeImport
        case flow
    }

    public static let shared = RequestBudget()

    private let defaults: UserDefaults
    private let limits: [Kind: Int]
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(
        defaults: UserDefaults = .standard,
        limits: [Kind: Int] = [.routeImport: 1_200, .flow: 2_400],
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
