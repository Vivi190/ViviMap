import Foundation

/// Online search through Photon (komoot, OSM data). The public instance is for light personal use;
/// pass a self-hosted `baseURL` once traffic grows (docs/architecture.md, ADR-6).
public struct PhotonSearchProvider: PlaceSearchProvider {
    public struct HTTPError: Error {
        public let status: Int
    }

    private let baseURL: URL
    private let session: URLSession

    // Results outside Turkey are noise for this app.
    private static let turkeyBBox = "25.6,35.8,44.9,42.2"

    public init(baseURL: URL = URL(string: "https://photon.komoot.io")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func search(_ query: String, near: GeoPoint?) async throws -> [Place] {
        var components = URLComponents(url: baseURL.appending(path: "api"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "12"),
            URLQueryItem(name: "bbox", value: Self.turkeyBBox),
            // Without it Photon follows Accept-Language: an English device got "Anadolu Palace of Justice".
            URLQueryItem(name: "lang", value: "default"),
        ]
        if let near {
            items.append(URLQueryItem(name: "lat", value: String(near.latitude)))
            items.append(URLQueryItem(name: "lon", value: String(near.longitude)))
        }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue("Atlas-iOS/1.0 (personal navigation app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw HTTPError(status: status) }
        return PlaceRanking.rank(try PhotonParser.places(from: data), query: query)
    }
}

/// Photon GeoJSON → `Place`, de-duplicated (Photon returns one hit per OSM way of the same street).
enum PhotonParser {
    private struct Response: Decodable {
        let features: [Feature]
    }

    private struct Feature: Decodable {
        let geometry: Geometry
        let properties: Properties
    }

    private struct Geometry: Decodable {
        let coordinates: [Double] // [lon, lat]
    }

    private struct Properties: Decodable {
        let osm_type: String?
        let osm_id: Int64?
        let osm_key: String?
        let osm_value: String?
        let name: String?
        let street: String?
        let housenumber: String?
        let locality: String?
        let district: String?
        let city: String?
        let county: String?
        let state: String?
    }

    static func places(from data: Data) throws -> [Place] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        var seen = Set<String>()
        return response.features.compactMap { feature in
            let p = feature.properties
            let coordinates = feature.geometry.coordinates
            guard coordinates.count >= 2 else { return nil }
            let streetLine = [p.street, p.housenumber].compactMap { $0 }.joined(separator: " ")
            guard let name = p.name ?? (streetLine.isEmpty ? nil : streetLine) else { return nil }

            var parts: [String] = []
            for part in [streetLine == name ? nil : streetLine, p.locality ?? p.district, p.city ?? p.county ?? p.state] {
                if let part, !part.isEmpty, part != name, !parts.contains(part) { parts.append(part) }
            }
            let subtitle = parts.joined(separator: ", ")
            guard seen.insert("\(name)|\(subtitle)").inserted else { return nil }

            let category = p.osm_key.flatMap { key in p.osm_value.map { "\(key)=\($0)" } }
            return Place(
                id: "\(p.osm_type ?? "?")\(p.osm_id ?? 0)",
                name: name,
                subtitle: subtitle,
                point: GeoPoint(latitude: coordinates[1], longitude: coordinates[0]),
                category: category
            )
        }
    }
}

/// Small, evidence-based fixes to Photon's order (docs/research §11b): stops outrank the building people
/// mean ("Tuzla Belediyesi" → bus stop), so stops sink unless the query asks for one, and a few query words
/// lift the matching kind of place.
enum PlaceRanking {
    private static let boosts: [(words: [String], categories: Set<String>)] = [
        (["belediye"], ["amenity=townhall"]),
        (["istasyon", "marmaray", "metro", "tren", "gar"], ["railway=station", "railway=halt", "public_transport=station"]),
        (["hastane"], ["amenity=hospital"]),
        (["havalimanı", "havaalanı"], ["aeroway=aerodrome"]),
        (["adliye"], ["amenity=courthouse"]),
    ]
    private static let stops: Set<String> = ["highway=bus_stop", "public_transport=platform", "public_transport=stop_position"]

    static func rank(_ places: [Place], query: String) -> [Place] {
        let text = query.lowercased(with: Locale(identifier: "tr"))
        let boosted = boosts.filter { rule in rule.words.contains { text.contains($0) } }
            .reduce(into: Set<String>()) { $0.formUnion($1.categories) }
        // Turkish softens k → ğ before a vowel suffix: "durak" but "durağı".
        let wantsStops = text.contains("durak") || text.contains("durağ")

        func bucket(_ place: Place) -> Int {
            guard let category = place.category else { return 1 }
            if wantsStops { return stops.contains(category) ? 0 : 1 }
            if boosted.contains(category) { return 0 }
            return stops.contains(category) ? 2 : 1
        }
        // Stable: equal buckets keep Photon's relevance order.
        return places.enumerated()
            .sorted { (bucket($0.element), $0.offset) < (bucket($1.element), $1.offset) }
            .map(\.element)
    }
}
