import Foundation
import Observation

/// Cameras and bumps the driver marked; OSM barely maps cameras around Pendik, Kartal and Tuzla (2 in the
/// shipped data), so these are what make camera warnings useful there. Kept on the device only (ADR-7).
@MainActor
@Observable
public final class UserHazardStore {
    public private(set) var hazards: [Hazard]

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "atlas.hazards.user"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hazards = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Hazard].self, from: $0) } ?? []
    }

    /// Marking the same spot twice (within ~10 m) replaces the old mark instead of doubling the warning.
    public func mark(_ kind: Hazard.Kind, latitude: Double, longitude: Double) {
        hazards.removeAll { abs($0.latitude - latitude) < 0.0001 && abs($0.longitude - longitude) < 0.0001 }
        hazards.append(Hazard(kind: kind, latitude: latitude, longitude: longitude))
        save()
    }

    public func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where hazards.indices.contains(index) {
            hazards.remove(at: index)
        }
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(hazards), forKey: Self.key)
    }
}
