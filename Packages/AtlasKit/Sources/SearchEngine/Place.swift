import CoreLocation

/// Plain latitude/longitude pair: Sendable and Codable, unlike CLLocationCoordinate2D.
public struct GeoPoint: Hashable, Sendable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Great-circle distance in metres.
    public func distance(to other: GeoPoint) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

public struct Place: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let point: GeoPoint
    /// OSM `key=value` (e.g. `amenity=townhall`); nil for coordinates typed by the user.
    public let category: String?
    /// Diagonal of the place's area in metres when it is an area (airport, campus, hospital, mall); nil for
    /// points and streets. The routing uses it to end on a public road rather than inside the area.
    /// Optional, so places saved before it existed still decode.
    public let areaSpan: Double?

    public init(id: String, name: String, subtitle: String, point: GeoPoint, category: String?, areaSpan: Double? = nil) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.point = point
        self.category = category
        self.areaSpan = areaSpan
    }
}

/// Anything that turns free text into places. Photon today; the offline FTS index (Phase 4) plugs in here.
public protocol PlaceSearchProvider: Sendable {
    func search(_ query: String, near: GeoPoint?) async throws -> [Place]
}
