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

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearanceMode = defaults.string(forKey: Keys.appearance).flatMap(AppearanceMode.init(rawValue:)) ?? .automatic
        showsDriveSimulation = defaults.bool(forKey: Keys.simulation)
    }

    private enum Keys {
        static let appearance = "atlas.appearance"
        static let simulation = "atlas.simulation"
    }
}
