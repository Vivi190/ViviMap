import Foundation
import Observation

public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    /// Night map between sunset and sunrise at the current position.
    case automatic
    case day
    case night

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: "Otomatik"
        case .day: "Gündüz"
        case .night: "Gece"
        }
    }

    public func isNight(at date: Date, latitude: Double, longitude: Double) -> Bool {
        switch self {
        case .day: false
        case .night: true
        case .automatic: Solar.isNight(at: date, latitude: latitude, longitude: longitude)
        }
    }
}

/// User preferences persisted in UserDefaults. Keys can be overridden with launch arguments
/// (e.g. `-atlas.appearance night`), which the UI tests use.
@MainActor
@Observable
public final class AppSettings {
    public var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Keys.appearance) }
    }

    /// Adds "Simüle et" to the route card: a test drive along the route without moving.
    public var showsDriveSimulation: Bool {
        didSet { defaults.set(showsDriveSimulation, forKey: Keys.simulation) }
    }

    /// Spoken and on-screen warnings for speed cameras / speed bumps on the route (on by default).
    public var warnsCameras: Bool {
        didSet { defaults.set(warnsCameras, forKey: Keys.cameras) }
    }

    public var warnsBumps: Bool {
        didSet { defaults.set(warnsBumps, forKey: Keys.bumps) }
    }

    /// Spoken "Hız sınırı 50." when clearly over the posted limit (on by default).
    public var warnsSpeeding: Bool {
        didSet { defaults.set(warnsSpeeding, forKey: Keys.speeding) }
    }

    /// Routes without toll bridges, tunnels and motorways (Valhalla exclude_tolls); may cross by car ferry.
    public var avoidsTolls: Bool {
        didSet { defaults.set(avoidsTolls, forKey: Keys.avoidsTolls) }
    }

    /// City traffic layer on the map (the "Trafik" button); remembered between launches.
    public var showsTrafficLayer: Bool {
        didSet { defaults.set(showsTrafficLayer, forKey: Keys.trafficLayer) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearanceMode = defaults.string(forKey: Keys.appearance).flatMap(AppearanceMode.init(rawValue:)) ?? .automatic
        showsDriveSimulation = defaults.bool(forKey: Keys.simulation)
        warnsCameras = defaults.object(forKey: Keys.cameras) as? Bool ?? true
        warnsBumps = defaults.object(forKey: Keys.bumps) as? Bool ?? true
        warnsSpeeding = defaults.object(forKey: Keys.speeding) as? Bool ?? true
        // On unless the driver switched it off: green-to-red roads are what a traffic app is opened for.
        showsTrafficLayer = defaults.object(forKey: Keys.trafficLayer) as? Bool ?? true
        avoidsTolls = defaults.bool(forKey: Keys.avoidsTolls)
    }

    private enum Keys {
        static let appearance = "atlas.appearance"
        static let simulation = "atlas.simulation"
        static let cameras = "atlas.warn.cameras"
        static let bumps = "atlas.warn.bumps"
        static let speeding = "atlas.warn.speeding"
        static let trafficLayer = "atlas.trafficLayer"
        static let avoidsTolls = "atlas.route.avoidsTolls"
    }
}
