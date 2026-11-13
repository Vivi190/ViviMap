import Foundation

/// Low-precision solar position (NOAA / Astronomical Almanac approximation, ≈0.1° accuracy).
/// Plenty for switching the map between day and night at sunset.
public enum Solar {
    /// Sun elevation above the horizon in degrees at `date` for the given position.
    public static func elevation(at date: Date, latitude: Double, longitude: Double) -> Double {
        let n = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0 // days since J2000.0
        let meanLongitude = normalized(280.460 + 0.985_647_4 * n)
        let meanAnomaly = radians(normalized(357.528 + 0.985_600_3 * n))
        let eclipticLongitude = radians(meanLongitude + 1.915 * sin(meanAnomaly) + 0.020 * sin(2 * meanAnomaly))
        let obliquity = radians(23.439 - 0.000_000_4 * n)

        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let siderealDegrees = normalized((18.697_374_558 + 24.065_709_824_419_08 * n) * 15 + longitude)
        let hourAngle = radians(siderealDegrees) - rightAscension

        let phi = radians(latitude)
        let sinElevation = sin(phi) * sin(declination) + cos(phi) * cos(declination) * cos(hourAngle)
        return degrees(asin(min(max(sinElevation, -1), 1)))
    }

    /// True once the sun's upper limb is below the horizon (standard −0.833° incl. refraction).
    public static func isNight(at date: Date, latitude: Double, longitude: Double) -> Bool {
        elevation(at: date, latitude: latitude, longitude: longitude) < -0.833
    }

    private static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
