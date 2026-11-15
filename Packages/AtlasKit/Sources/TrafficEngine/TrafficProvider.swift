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
    /// Live flow on the roads along the route (it also returns cross streets; see RouteTraffic.sections).
    func flow(along route: [CLLocationCoordinate2D]) async throws -> [FlowSegment]
    /// Every road in a map area, for the city traffic layer (AreaTraffic.sections).
    func flow(in area: TrafficArea) async throws -> [FlowSegment]
    /// Closures, accidents and road works in a map area, for the city traffic layer.
    func incidents(in area: TrafficArea) async throws -> [TrafficIncident]
}

public extension TrafficProvider {
    /// Providers without road events have none.
    func incidents(in area: TrafficArea) async throws -> [TrafficIncident] { [] }
}

/// A map area in degrees, for the city traffic layer.
public struct TrafficArea: Sendable, Equatable {
    public let west: Double
    public let south: Double
    public let east: Double
    public let north: Double

    public init(west: Double, south: Double, east: Double, north: Double) {
        self.west = west
        self.south = south
        self.east = east
        self.north = north
    }

    /// HERE answers areas of at most 1° × 1°.
    public var fitsHERE: Bool { east - west <= 1 && north - south <= 1 }

    /// The larger side in degrees.
    public var span: Double { max(east - west, north - south) }

    public func contains(_ other: TrafficArea) -> Bool {
        west <= other.west && south <= other.south && east >= other.east && north >= other.north
    }

    /// Grown by `fraction` of its size on every side, so small pans stay inside what was fetched; kept under
    /// HERE's 1° limit (0.99, so rounding cannot tip it over).
    public func expanded(by fraction: Double) -> TrafficArea {
        let dx = min((east - west) * fraction, max(0, (0.99 - (east - west)) / 2))
        let dy = min((north - south) * fraction, max(0, (0.99 - (north - south)) / 2))
        return TrafficArea(west: west - dx, south: south - dy, east: east + dx, north: north + dy)
    }
}
