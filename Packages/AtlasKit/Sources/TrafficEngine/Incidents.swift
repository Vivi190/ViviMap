import CoreLocation
import Foundation

/// A road event from HERE Traffic incidents, shown on the city layer as Yandex shows them: a closure, an
/// accident or road works. 14.11.2026, Kartal–Tuzla: 18 closures in a 3 KB answer.
public struct TrafficIncident: Sendable {
    public enum Kind: String, Sendable {
        case closure, accident, roadworks
    }

    public let kind: Kind
    /// The stretch it covers, in HERE's geometry.
    public let points: [CLLocationCoordinate2D]
    /// HERE's own words, in Turkish ("Arasında Begonya Sokak ve Aydınlı Yolu Caddesi - Kapalı arasında").
    public let summary: String
}

enum HEREIncidentsResponse {
    private struct Body: Decodable {
        struct Result: Decodable {
            let location: Location
            let incidentDetails: Details
        }

        struct Location: Decodable { let shape: Shape? }
        struct Shape: Decodable { let links: [Link] }
        struct Link: Decodable { let points: [Point] }
        struct Point: Decodable {
            let lat: Double
            let lng: Double
        }

        struct Details: Decodable {
            let type: String?
            let roadClosed: Bool?
            let description: Words?
        }

        struct Words: Decodable { let value: String }

        let results: [Result]?
    }

    /// Closures, accidents and road works; congestion belongs to the flow layer, and the rest (weather, events)
    /// says little on a map.
    static func incidents(from data: Data) throws -> [TrafficIncident] {
        try JSONDecoder().decode(Body.self, from: data).results?.compactMap { result in
            let details = result.incidentDetails
            let kind: TrafficIncident.Kind? = if details.roadClosed == true || details.type == "roadClosure" {
                .closure
            } else if details.type == "accident" {
                .accident
            } else if details.type == "construction" {
                .roadworks
            } else {
                nil
            }
            guard let kind, let links = result.location.shape?.links else { return nil }
            let points = links.flatMap(\.points).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            guard !points.isEmpty else { return nil }
            return TrafficIncident(kind: kind, points: points, summary: details.description?.value ?? "")
        } ?? []
    }
}
