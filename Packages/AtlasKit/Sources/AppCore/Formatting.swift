import Foundation

public enum Formatting {
    /// Driving time in Turkish: "1 dk" minimum, "27 dk", "1 sa 12 dk", "2 sa".
    public static func duration(seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        if hours == 0 { return "\(rest) dk" }
        return rest == 0 ? "\(hours) sa" : "\(hours) sa \(rest) dk"
    }

    /// Road-style distance in Turkish: "350 m", "1,2 km", "18 km".
    public static func distance(meters: Double) -> String {
        if meters < 950 {
            return "\(max(10, Int((meters / 10).rounded()) * 10)) m"
        }
        let km = meters / 1000
        let number = km < 10
            ? km.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "tr_TR")))
            : km.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "tr_TR")))
        return "\(number) km"
    }
}
