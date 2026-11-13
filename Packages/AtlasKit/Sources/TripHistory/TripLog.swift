import Foundation
import Observation

/// One guided drive: what the app predicted when it started and what actually happened. Kept on the
/// device only (ADR-7); it is how ETA accuracy gets measured instead of claimed (ADR-5, Phase 7).
public struct Trip: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let destination: String
    /// Route length when the drive started, metres.
    public let distance: Double
    /// The duration shown when the drive started.
    public let predicted: TimeInterval
    /// Whether that prediction included live traffic (HERE) or was free-flow (Valhalla).
    public let predictedWithTraffic: Bool
    /// Reached the destination, rather than ended on the way.
    public let arrived: Bool

    public init(
        id: UUID = UUID(), startedAt: Date, endedAt: Date, destination: String, distance: Double,
        predicted: TimeInterval, predictedWithTraffic: Bool, arrived: Bool
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.destination = destination
        self.distance = distance
        self.predicted = predicted
        self.predictedWithTraffic = predictedWithTraffic
        self.arrived = arrived
    }

    public var actual: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}

@MainActor
@Observable
public final class TripLog {
    /// Newest first.
    public private(set) var trips: [Trip]

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "atlas.trips"
    static let limit = 200

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        trips = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Trip].self, from: $0) } ?? []
    }

    /// Drives under a minute were started by mistake and say nothing about the estimate.
    public func record(_ trip: Trip) {
        guard trip.actual >= 60 else { return }
        trips.insert(trip, at: 0)
        if trips.count > Self.limit { trips.removeLast(trips.count - Self.limit) }
        save()
    }

    public func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where trips.indices.contains(index) {
            trips.remove(at: index)
        }
        save()
    }

    /// How actual time compares with the prediction, as the median ratio over completed drives of at least
    /// 5 minutes (shorter ones are dominated by parking and lights). nil until there are 3 such drives.
    /// Kept apart for traffic and free-flow predictions: they are different estimates.
    public func calibration(withTraffic: Bool) -> (ratio: Double, drives: Int)? {
        let ratios = trips
            .filter { $0.arrived && $0.predictedWithTraffic == withTraffic && $0.predicted >= 300 }
            .map { $0.actual / $0.predicted }
            .sorted()
        guard ratios.count >= 3 else { return nil }
        let middle = ratios.count / 2
        let median = ratios.count.isMultiple(of: 2) ? (ratios[middle - 1] + ratios[middle]) / 2 : ratios[middle]
        return (median, ratios.count)
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(trips), forKey: Self.key)
    }
}
