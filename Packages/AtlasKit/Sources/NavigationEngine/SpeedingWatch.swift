import Foundation

/// "Hız sınırı 50." when the driver stays clearly over the posted limit (OSM maxspeed via Valhalla).
/// Clearly over: more than 10 % and at least 6 km/h above, so GPS speed jitter and the speedometer's own offset
/// stay quiet; held for 3 s, so a moment of overtaking is not worth a word. Again at most once a minute.
struct SpeedingWatch {
    var isEnabled = true
    private var overSince: Date?
    private var lastWarning: Date?

    /// - Parameters:
    ///   - speedKmh: GPS speed.
    ///   - limit: posted limit in km/h; nil where OSM has none (no warning without a sign).
    ///   - time: the fix's timestamp, so the rhythm follows the drive rather than the wall clock.
    mutating func update(speedKmh: Double, limit: Int?, at time: Date) -> String? {
        guard isEnabled, let limit, speedKmh > Double(limit) + max(6, Double(limit) * 0.1) else {
            overSince = nil
            return nil
        }
        let since = overSince ?? time
        overSince = since
        guard time.timeIntervalSince(since) >= 3 else { return nil }
        if let lastWarning, time.timeIntervalSince(lastWarning) < 60 { return nil }
        lastWarning = time
        return "Hız sınırı \(limit)."
    }
}
