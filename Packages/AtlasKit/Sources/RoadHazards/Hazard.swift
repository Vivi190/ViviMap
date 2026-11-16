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
    /// Where a camera looks, in degrees, when mapped: it faces the traffic it watches. nil = not mapped.
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

/// Traffic lights of Istanbul, for the map and for "Işıklarda sağa dönün": the lights OpenStreetMap has (a point
/// per signal, at the stop line; Tools/hazards/fetch_signals.py, 4 118 on 2026-11-15) and, where it has none, the
/// municipality's signalised junctions (a point per junction; fetch_junctions.py, 2 587 on 2026-11-16).
/// OpenStreetMap misses about half of them: 1 246 of the 2 587 had no light of its within 80 m, 320 of the 479
/// around Kartal, Pendik and Tuzla. The two files stay apart, each under its own licence, and meet here.
public enum TrafficSignals {
    public static let bundled: [CLLocationCoordinate2D] = merged(points(in: "signals-istanbul"), junctions: points(in: "junctions-istanbul"))

    private static func points(in file: String) -> [CLLocationCoordinate2D] {
        guard let url = Bundle.module.url(forResource: file, withExtension: "json"), let data = try? Data(contentsOf: url) else { return [] }
        return (try? decode(data)) ?? []
    }

    /// `lights`, and every junction with none of them within `reach` metres. 60 m: a light stands at its stop
    /// line, 10 to 40 m from the centre of its junction, and the next junction is rarely nearer than 100 m.
    static func merged(_ lights: [CLLocationCoordinate2D], junctions: [CLLocationCoordinate2D], reach: Double = 60) -> [CLLocationCoordinate2D] {
        // Lights by cell of 0.001° (about 100 m): a junction looks in its own cell and the eight around it.
        var cells: [Cell: [CLLocationCoordinate2D]] = [:]
        for light in lights { cells[Cell(light), default: []].append(light) }
        let unlit = junctions.filter { junction in
            let home = Cell(junction)
            for row in home.row - 1 ... home.row + 1 {
                for column in home.column - 1 ... home.column + 1 {
                    for light in cells[Cell(row: row, column: column)] ?? [] where metres(light, junction) <= reach {
                        return false
                    }
                }
            }
            return true
        }
        return lights + unlit
    }

    private struct Cell: Hashable {
        let row: Int
        let column: Int

        init(row: Int, column: Int) {
            self.row = row
            self.column = column
        }

        init(_ point: CLLocationCoordinate2D) {
            row = Int((point.latitude * 1000).rounded(.down))
            column = Int((point.longitude * 1000).rounded(.down))
        }
    }

    private static func metres(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dx = (b.longitude - a.longitude) * 111_320 * cos(a.latitude * .pi / 180)
        let dy = (b.latitude - a.latitude) * 110_540
        return (dx * dx + dy * dy).squareRoot()
    }

    static func decode(_ data: Data) throws -> [CLLocationCoordinate2D] {
        struct File: Decodable { let points: [[Double]] }
        return try JSONDecoder().decode(File.self, from: data).points.compactMap { pair in
            pair.count == 2 ? CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1]) : nil
        }
    }
}
