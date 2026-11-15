import CoreLocation
import Foundation

/// A point on the road worth a warning: a fixed speed camera or a speed bump ("kasis").
public struct Hazard: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case camera
        case bump
    }

    public let kind: Kind
    public let latitude: Double
    public let longitude: Double
    /// Limit a camera enforces, when mapped.
    public let maxspeed: Int?
    /// Direction of travel a camera watches, in degrees, when mapped; nil = both ways.
    public let direction: Double?

    public init(kind: Kind, latitude: Double, longitude: Double, maxspeed: Int? = nil, direction: Double? = nil) {
        self.kind = kind
        self.latitude = latitude
        self.longitude = longitude
        self.maxspeed = maxspeed
        self.direction = direction
    }

    public var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Hazards shipped with the app (Tools/hazards/fetch_hazards.py, OpenStreetMap), so warnings work offline.
public struct HazardCatalog: Sendable {
    public let hazards: [Hazard]
    /// When the data was fetched (YYYY-MM-DD), shown so its age is never a surprise.
    public let fetched: String

    public init(hazards: [Hazard], fetched: String) {
        self.hazards = hazards
        self.fetched = fetched
    }

    public static func bundled() -> HazardCatalog? {
        guard let url = Bundle.module.url(forResource: "hazards-istanbul", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? decode(data)
    }

    static func decode(_ data: Data) throws -> HazardCatalog {
        struct File: Decodable {
            struct Item: Decodable {
                let k: Hazard.Kind
                let lat: Double
                let lon: Double
                let maxspeed: Int?
                let dir: Double?
            }

            let fetched: String
            let hazards: [Item]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        return HazardCatalog(
            hazards: file.hazards.map { Hazard(kind: $0.k, latitude: $0.lat, longitude: $0.lon, maxspeed: $0.maxspeed, direction: $0.dir) },
            fetched: file.fetched
        )
    }
}

/// Traffic lights from OpenStreetMap (Tools/hazards/fetch_signals.py; 4 118 in Istanbul, 15.11.2026), for the
/// map only: guidance does not warn about them.
public enum TrafficSignals {
    public static let bundled: [CLLocationCoordinate2D] = {
        guard let url = Bundle.module.url(forResource: "signals-istanbul", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        return (try? decode(data)) ?? []
    }()

    static func decode(_ data: Data) throws -> [CLLocationCoordinate2D] {
        struct File: Decodable { let points: [[Double]] }
        return try JSONDecoder().decode(File.self, from: data).points.compactMap { pair in
            pair.count == 2 ? CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1]) : nil
        }
    }
}
