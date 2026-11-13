import Foundation

/// Camera zoom while guiding: further out at speed (more road ahead on D-100 / TEM), closer in town and
/// right before a turn. A few fixed steps with a margin between them, so the camera does not breathe
/// with every small change of speed.
enum GuidanceZoom {
    static let levels: [Double] = [15.5, 16.3, 17.0, 17.6]

    /// - Parameters:
    ///   - speed: m/s.
    ///   - distanceToManeuver: metres; a turn within 150 m pulls the camera in whatever the speed.
    ///   - current: the level in use, to keep it until speed clearly leaves its band.
    static func level(speed: Double, distanceToManeuver: Double?, current: Double?) -> Double {
        if let distance = distanceToManeuver, distance < 150 { return levels[3] }
        let kmh = speed * 3.6
        // Bands (km/h): ≥ 85 → 15.5, 55–85 → 16.3, 25–55 → 17.0, below → 17.6; ±5 km/h hysteresis.
        let bands: [(level: Double, from: Double)] = [(levels[0], 85), (levels[1], 55), (levels[2], 25), (levels[3], 0)]
        if let current, let band = bands.first(where: { $0.level == current }),
           let index = bands.firstIndex(where: { $0.level == current }) {
            let upper = index == 0 ? Double.infinity : bands[index - 1].from
            if kmh >= band.from - 5, kmh < upper + 5 { return current }
        }
        return bands.first { kmh >= $0.from }?.level ?? levels[3]
    }
}
