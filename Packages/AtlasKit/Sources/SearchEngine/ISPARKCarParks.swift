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
            let name = park.parkName.trimmingCharacters(in: .whitespaces)
            // Closed for the day: its count of free spaces would send a driver to a shut gate.
            guard park.isOpen == 1, !isForBuses(name), let latitude = Double(park.lat), let longitude = Double(park.lng),
                  (40.5 ... 41.7).contains(latitude), (27.9 ... 30.0).contains(longitude)
            else { return nil }
            return Place(
                id: "ispark-\(park.parkID)",
                name: name,
                subtitle: subtitle(free: park.emptyCapacity, capacity: park.capacity, hours: park.workHours),
                point: GeoPoint(latitude: latitude, longitude: longitude),
                category: "amenity=parking"
            )
        }
    }

    /// A car park for coaches and service buses, by its name ("… Otobüs Otoparkı", "… Servis ve Turizm
    /// Araçları Açık Otoparkı"): the list has them among the others. One that also takes cars says "binek".
    static func isForBuses(_ name: String) -> Bool {
        let folded = TurkishFold.fold(name)
        return !folded.contains("binek") && (folded.contains("otobus") || folded.contains("turizm arac"))
    }

    /// "83 boş yer · 100 araçlık · 08:00-19:00 · İSPARK". What a driver decides on comes first: a list row
    /// shows one line of it. No free space is left unsaid, not called full: the service reports zero for car
    /// parks it does not count too (46 of the 184 open ones on the evening of 2026-11-16, the largest among
    /// them), and a "full" that is wrong sends a driver past a car park with room.
    static func subtitle(free: Int?, capacity: Int?, hours: String?) -> String {
        var parts: [String] = []
        if let free, free > 0 { parts.append("\(free) boş yer") }
        if let capacity, capacity > 0 { parts.append("\(capacity) araçlık") }
        if let hours = hours?.trimmingCharacters(in: .whitespaces), !hours.isEmpty { parts.append(hours) }
        return (parts + ["İSPARK"]).joined(separator: " · ")
    }

    /// What a car park costs, for its card: "1 sa 110 TL · 2 sa 140 TL · Tam gün 370 TL · İlk 15 dk ücretsiz".
    /// One request for the one car park (its id, nothing about the user); nil without an answer or a tariff.
    public func fees(of place: Place) async -> String? {
        guard place.id.hasPrefix("ispark-"), let id = Int(place.id.dropFirst("ispark-".count)),
              var components = URLComponents(string: "https://api.ibb.gov.tr/ispark/ParkDetay")
        else { return nil }
        components.queryItems = [URLQueryItem(name: "id", value: String(id))]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return Self.fees(from: data)
    }

    private struct Detail: Decodable {
        let tariff: String?
        let freeTime: Int?
    }

    /// The service writes a tariff as "0-1 Saat : 110,00;1-2 Saat : 140,00;…;Tam Gün : 370,00". The first two
    /// steps and the whole day are what a driver weighs; the rest would not fit a line.
    static func fees(from data: Data) -> String? {
        guard let detail = (try? JSONDecoder().decode([Detail].self, from: data))?.first else { return nil }
        var steps: [(label: String, price: String)] = []
        for entry in (detail.tariff ?? "").split(separator: ";") {
            let parts = entry.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, !parts[1].isEmpty else { continue }
            // "110,00" is 110 TL; "112,50" stays as written.
            let price = parts[1].hasSuffix(",00") ? String(parts[1].dropLast(3)) : parts[1]
            // "0-1 Saat": up to an hour.
            if let range = parts[0].range(of: #"^\d+\s*-\s*(\d+)\s*Saat$"#, options: .regularExpression) {
                let hours = parts[0][range].split(separator: "-").last.map { $0.replacingOccurrences(of: "Saat", with: "").trimmingCharacters(in: .whitespaces) } ?? ""
                steps.append((label: "\(hours) sa", price: price))
            } else if TurkishFold.fold(parts[0]) == "tam gun" {
                steps.append((label: "Tam gün", price: price))
            }
        }
        let shown = steps.filter { $0.label != "Tam gün" }.prefix(2) + steps.filter { $0.label == "Tam gün" }
        var pieces = shown.map { "\($0.label) \($0.price) TL" }
        if let free = detail.freeTime, free > 0 { pieces.append("İlk \(free) dk ücretsiz") }
        return pieces.isEmpty ? nil : pieces.joined(separator: " · ")
    }

    /// One list of car parks, nearest first: the live ones, and those of the indexes that are not one of them
    /// (within 80 m of a live car park it is the same one under another name, and the live record says more).
    static func merged(_ live: [Place], with others: [Place], near: GeoPoint, limit: Int = 20) -> [Place] {
        let rest = others.filter { other in !live.contains { $0.point.distance(to: other.point) <= 80 } }
        return Array((live + rest).map { ($0, $0.point.distance(to: near)) }.sorted { $0.1 < $1.1 }.map { $0.0 }.prefix(limit))
    }
}
