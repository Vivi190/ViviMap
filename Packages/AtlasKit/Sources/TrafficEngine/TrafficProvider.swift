import CoreLocation
import Foundation

/// Travel times for one route geometry under current traffic. Every candidate route is measured by the
/// same provider, so their times compare on one scale (docs/architecture.md, ADR-5).
public struct TrafficEstimate: Sendable, Equatable {
    /// With current traffic.
    public let duration: TimeInterval
    /// Free flow.
    public let baseDuration: TimeInterval
    /// Usual for this time of day; nil when the provider did not give it for the whole route.
    public let typicalDuration: TimeInterval?

    public init(duration: TimeInterval, baseDuration: TimeInterval, typicalDuration: TimeInterval?) {
        self.duration = duration
        self.baseDuration = baseDuration
        self.typicalDuration = typicalDuration
    }

    /// Extra time traffic adds right now.
    public var delay: TimeInterval { max(0, duration - baseDuration) }
}

public enum TrafficError: LocalizedError, Equatable {
    /// This device used up its monthly share of the free quota.
    case budgetExhausted
    /// The provider could not match the geometry to its road network.
    case notMatched
    case service(status: Int)

    public var errorDescription: String? {
        switch self {
        case .budgetExhausted: "Bu ayın trafik sorgu sınırı doldu."
        case .notMatched: "Rota trafik verisiyle eşleştirilemedi."
        case let .service(status): "Trafik servisi yanıt vermedi (\(status))."
        }
    }
}

public protocol TrafficProvider: Sendable {
    func estimate(_ route: [CLLocationCoordinate2D]) async throws -> TrafficEstimate
}
