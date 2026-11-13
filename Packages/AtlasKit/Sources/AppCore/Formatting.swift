import Foundation

public enum Formatting {
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
