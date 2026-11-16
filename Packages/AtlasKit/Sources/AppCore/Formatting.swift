import Foundation

public enum Formatting {
    /// Driving time in Turkish: "1 dk" minimum, "27 dk", "1 sa 12 dk", "2 sa".
    public static func duration(seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        if hours == 0 { return "\(rest) dk" }
        return rest == 0 ? "\(hours) sa" : "\(hours) sa \(rest) dk"
    }

    /// Clock time the Turkish way, 24-hour ("19:30"), whatever region the device is set to.
    public static func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(identifier: "tr_TR")))
    }

    /// Road-style distance in Turkish: "80 m", "350 m", "1,2 km", "18 km". The step grows with the distance
    /// (10 m up to 250 m, then 50 m), so a figure far ahead does not change with every fix; whole kilometres
    /// drop the ",0".
    public static func distance(meters: Double) -> String {
        if meters < 975 {
            let step: Double = meters < 250 ? 10 : 50
            return "\(max(10, Int((meters / step).rounded() * step))) m"
        }
        let km = meters / 1000
        if km >= 10 { return "\(Int(km.rounded())) km" }
        let tenths = (km * 10).rounded() / 10
        if tenths == tenths.rounded() { return "\(Int(tenths)) km" }
        let number = tenths.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "tr_TR")))
        return "\(number) km"
    }
}
