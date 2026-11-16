import Foundation

/// İSPARK's car parks with their free spaces right now, from Istanbul's open data (api.ibb.gov.tr; İBB Açık
/// Veri Lisansı: free to use, also commercially, with the source named). One request returns every car park of
/// the city, about 50 KB, and says nothing about the user: no position is sent.
public struct ISPARKCarParks: Sendable {
    private let session: URLSession
    private static let url = URL(string: "https://api.ibb.gov.tr/ispark/Park")!

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// The open car parks as places, their free spaces in the subtitle. Throws without a connection or when the
    /// service fails; a car park list without them still stands.
    public func places() async throws -> [Place] {
        var request = URLRequest(url: Self.url)
        request.timeoutInterval = 6 // a list the driver is waiting for must not hang on this
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.places(from: data)
    }

    private struct CarPark: Decodable {
        let parkID: Int
        let parkName: String
        let lat: String
        let lng: String
        let capacity: Int?
        let emptyCapacity: Int?
        let workHours: String?
        let isOpen: Int?
    }

    static func places(from data: Data) throws -> [Place] {
        try JSONDecoder().decode([CarPark].self, from: data).compactMap { park in
            // Closed for the day: its count of free spaces would send a driver to a shut gate.
            guard park.isOpen == 1, let latitude = Double(park.lat), let longitude = Double(park.lng),
                  (40.5 ... 41.7).contains(latitude), (27.9 ... 30.0).contains(longitude)
            else { return nil }
            return Place(
                id: "ispark-\(park.parkID)",
                name: park.parkName.trimmingCharacters(in: .whitespaces),
                subtitle: subtitle(free: park.emptyCapacity, capacity: park.capacity, hours: park.workHours),
                point: GeoPoint(latitude: latitude, longitude: longitude),
                category: "amenity=parking"
            )
        }
    }

    /// "83 boş yer · 100 araçlık · 08:00-19:00 · İSPARK", "Dolu" when no space is left. What a driver decides
    /// on comes first: a list row shows one line of it.
    static func subtitle(free: Int?, capacity: Int?, hours: String?) -> String {
        var parts: [String] = []
        if let free { parts.append(free > 0 ? "\(free) boş yer" : "Dolu") }
        if let capacity, capacity > 0 { parts.append("\(capacity) araçlık") }
        if let hours = hours?.trimmingCharacters(in: .whitespaces), !hours.isEmpty { parts.append(hours) }
        return (parts + ["İSPARK"]).joined(separator: " · ")
    }

    /// One list of car parks, nearest first: the live ones, and those of the indexes that are not one of them
    /// (within 80 m of a live car park it is the same one under another name, and the live record says more).
    static func merged(_ live: [Place], with others: [Place], near: GeoPoint, limit: Int = 20) -> [Place] {
        let rest = others.filter { other in !live.contains { $0.point.distance(to: other.point) <= 80 } }
        return Array((live + rest).map { ($0, $0.point.distance(to: near)) }.sorted { $0.1 < $1.1 }.map { $0.0 }.prefix(limit))
    }
}
