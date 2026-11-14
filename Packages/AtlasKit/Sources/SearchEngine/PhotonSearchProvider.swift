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
        // "benzinlik", "en yakın eczane": the nearest of that kind (PlaceRanking.kind).
        if let near, let tags = PlaceRanking.kind(query) {
            let nearest = try await places(reverseRequest(near, tags: tags))
            if !nearest.isEmpty { return nearest }
        }
        // "Atatürk Cad. No:12" as OSM spells it (PlaceRanking.address); other queries go as typed.
        let text = PlaceRanking.address(query).text
        // A query naming a kind of place also asks for that kind alone, by name (PlaceRanking.focus).
        guard let focus = PlaceRanking.focus(text) else {
            return PlaceRanking.rank(try await places(request(text, near: near)), query: text)
        }
        async let focused = places(request(focus.name, near: near, tags: focus.tags))
        let general = try await places(request(text, near: near))
        // Its hits lead; a failure there only costs the extra hits.
        let first = (try? await focused) ?? []
        let shown = Set(first.map(\.id))
        return PlaceRanking.rank(first + general.filter { !shown.contains($0.id) }, query: text)
    }

    func request(_ query: String, near: GeoPoint?, tags: [String] = []) -> URLRequest {
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
        items += tags.map { URLQueryItem(name: "osm_tag", value: $0) }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue("Atlas-iOS/1.0 (personal navigation app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        return request
    }

    private func places(_ request: URLRequest) async throws -> [Place] {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw HTTPError(status: status) }
        return try PhotonParser.places(from: data)
    }

    /// Nearest named place or address for a point picked on the map.
    public func reverse(_ point: GeoPoint) async throws -> Place? {
        let (data, response) = try await session.data(for: reverseRequest(point))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try PhotonParser.places(from: data).first
    }

    /// Photon's reverse search: the nearest place; with `tags`, the nearest 12 of that kind within 15 km.
    func reverseRequest(_ point: GeoPoint, tags: [String] = []) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: "reverse"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "lat", value: String(point.latitude)),
            URLQueryItem(name: "lon", value: String(point.longitude)),
            URLQueryItem(name: "lang", value: "default"),
            URLQueryItem(name: "limit", value: tags.isEmpty ? "1" : "12"),
        ]
        if !tags.isEmpty { items.append(URLQueryItem(name: "radius", value: "15")) }
        items += tags.map { URLQueryItem(name: "osm_tag", value: $0) }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue("Atlas-iOS/1.0 (personal navigation app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10
        return request
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
        /// Bounding box of ways and relations: [west, north, east, south].
        let extent: [Double]?
    }

    /// Diagonal of an area's bounding box in metres. Streets are lines, so their box says how long they are,
    /// not how big: nil for them, as for points.
    static func areaSpan(extent: [Double]?, key: String?) -> Double? {
        guard let extent, extent.count == 4, key != "highway" else { return nil }
        let (west, north, east, south) = (extent[0], extent[1], extent[2], extent[3])
        let dx = (east - west) * 111_320 * cos((north + south) / 2 * .pi / 180)
        let dy = (north - south) * 110_540
        return (dx * dx + dy * dy).squareRoot()
    }

    /// "Yavuz Seli̇m Devlet Hastanesi̇" → "Yavuz Selim Devlet Hastanesi": some OSM names carry a combining dot
    /// (U+0307) after "i", left from lowercasing "İ" without Turkish rules; on screen it is a doubled dot.
    static func readable(_ text: String) -> String {
        text.replacingOccurrences(of: "i\u{307}", with: "i")
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
                name: readable(name),
                subtitle: readable(subtitle),
                point: GeoPoint(latitude: coordinates[1], longitude: coordinates[0]),
                category: category,
                areaSpan: areaSpan(extent: p.extent, key: p.osm_key),
                streetAddress: p.street != nil && p.housenumber != nil ? streetLine : nil
            )
        }
    }
}

/// Small, evidence-based fixes to Photon's order (docs/research §11b): stops outrank the building people
/// mean ("Tuzla Belediyesi" → bus stop), so stops sink unless the query asks for one; a few query words lift
/// the matching kind of place; lines and plans go last; an address query puts that address, then its street,
/// first. Mirrored in Tools/searchbench/bench.py, which measures it.
enum PlaceRanking {
    private static let boosts: [(words: [String], categories: Set<String>)] = [
        (["belediye"], ["amenity=townhall"]),
        (["istasyon", "marmaray", "metro", "tren", "gar"], ["railway=station", "railway=halt", "public_transport=station"]),
        (["hastane"], ["amenity=hospital"]),
        (["havalimanı", "havaalanı"], ["aeroway=aerodrome"]),
        (["adliye"], ["amenity=courthouse"]),
    ]
    private static let stops: Set<String> = ["highway=bus_stop", "public_transport=platform", "public_transport=stop_position"]
    /// Lines and plans, never where a driver is headed: "cevizli tugay yolu" first found "Tugay Yolu", a metro
    /// line under construction (search benchmark 14.11.2026).
    private static let lines: Set<String> = [
        "railway=rail", "railway=subway", "railway=light_rail", "railway=tram", "railway=monorail",
        "railway=narrow_gauge", "railway=funicular", "railway=construction", "railway=proposed",
        "railway=abandoned", "railway=disused", "highway=construction", "highway=proposed",
    ]

    /// In order: "kartal metro durağı" is a bus stop named "Kartal Metro", not a station.
    private static let focusRules: [(words: Set<String>, tags: [String])] = [
        (["durak", "durağı"], ["highway:bus_stop", "public_transport:platform"]),
        (["istasyon", "istasyonu", "metro", "metrosu", "marmaray", "tren", "gar", "garı"],
         ["railway:station", "railway:halt", "public_transport:station"]),
        (["avm"], ["shop:mall"]),
        (["iskele", "iskelesi"], ["amenity:ferry_terminal"]),
        (["otopark", "otoparkı"], ["amenity:parking"]),
    ]

    /// Bare kinds of place and their OSM tags. Not "nöbetçi eczane": OSM has no duty roster, and the nearest
    /// pharmacy may be shut.
    private static let kinds: [String: [String]] = {
        let table: [(words: [String], tags: [String])] = [
            (["benzinlik", "benzin istasyonu", "akaryakıt", "akaryakıt istasyonu", "petrol istasyonu"], ["amenity:fuel"]),
            (["eczane"], ["amenity:pharmacy"]),
            (["otopark", "park yeri"], ["amenity:parking"]),
            (["şarj", "şarj istasyonu", "şarj noktası"], ["amenity:charging_station"]),
            (["hastane"], ["amenity:hospital"]),
            (["market", "süpermarket"], ["shop:supermarket", "shop:convenience"]),
            (["atm", "bankamatik"], ["amenity:atm"]),
            (["banka"], ["amenity:bank"]),
            (["kafe", "cafe"], ["amenity:cafe"]),
            (["restoran", "restaurant", "lokanta"], ["amenity:restaurant"]),
            (["fırın"], ["shop:bakery"]),
            (["avm", "alışveriş merkezi"], ["shop:mall"]),
            (["polis", "karakol"], ["amenity:police"]),
            (["durak", "otobüs durağı"], ["highway:bus_stop"]),
            (["metro", "istasyon", "metro istasyonu", "tren istasyonu"], ["railway:station"]),
            (["iskele", "vapur iskelesi"], ["amenity:ferry_terminal"]),
            (["taksi", "taksi durağı"], ["amenity:taxi"]),
            (["oto yıkama", "otoyıkama"], ["amenity:car_wash"]),
            (["lastikçi"], ["shop:tyres"]),
            (["ptt", "postane"], ["amenity:post_office"]),
            (["tuvalet", "wc"], ["amenity:toilets"]),
            (["otel"], ["tourism:hotel"]),
        ]
        return Dictionary(table.flatMap { row in row.words.map { ($0, row.tags) } }, uniquingKeysWith: { first, _ in first })
    }()

    /// A bare kind of place ("benzinlik", "en yakın eczane", "marketler") wants the nearest ones, not places with
    /// the word in their name: Photon's text search answered "benzinlik" with a station 148 km away and "hastane"
    /// with a building site; its reverse search filtered by kind lists the nearest (14.11.2026). Photon tags.
    static func kind(_ query: String) -> [String]? {
        var text = query.lowercased(with: Locale(identifier: "tr")).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let prefix = ["en yakın ", "yakınımdaki ", "yakındaki ", "yakınımda ", "yakında "].first(where: { text.hasPrefix($0) }) {
            text = String(text.dropFirst(prefix.count))
        }
        // Plural: "eczaneler", "otoparklar".
        let singular = text.hasSuffix("ler") || text.hasSuffix("lar") ? String(text.dropLast(3)) : text
        return kinds[text] ?? kinds[singular]
    }

    /// Turkish address shorthand in OSM's spelling, in order: door and flat numbers go, "No:12" becomes the
    /// house number, "Cad." "Sk." "Mah." "Blv." are spelled out.
    private static let addressSteps: [(pattern: String, template: String)] = [
        (#"(?<!\w)iç\s+kapı(?:\s+no)?\s*[\.:]?\s*\d+\w*"#, " "),
        (#"(?<!\w)dış\s+kapı(?!\w)"#, " "),
        (#"(?<!\w)(?:d|k)\s*[\.:]\s*\d+\w*"#, " "),
        (#"(?<!\w)(?:daire|kat)\s*[\.:]?\s*\d+\w*"#, " "),
        (#"(?<!\w)(?:no|numara|nu)\s*[\.:]?\s*(\d+[a-zçğıöşü]?)(?:\s*/\s*\d+)?(?!\w)"#, " $1 "),
        ("/", " "),
        (#"(?<!\w)(?:cad|cd)(?:\.|(?!\w))"#, " caddesi "),
        (#"(?<!\w)(?:sok|sk)(?:\.|(?!\w))"#, " sokak "),
        (#"(?<!\w)(?:mah|mh)(?:\.|(?!\w))"#, " mahallesi "),
        (#"(?<!\w)(?:blv|bulv)(?:\.|(?!\w))|(?<!\w)bul\."#, " bulvarı "),
    ]
    private static let streetWord = #"(?<!\w)(?:caddesi|cadde|sokak|sokağı|bulvarı|bulvar|yolu)(?!\w)"#
    private static let numberAfterStreet =
        #"(?<!\w)(?:caddesi|cadde|sokak|sokağı|bulvarı|bulvar|yolu)\s+\d+[a-zçğıöşü]?(?!\w)"#

    /// Addresses as they are written in Turkey, in OSM's spelling: "Yakacık Mah. Atatürk Cad. No:12 D:5
    /// Kartal/İstanbul" → "yakacık mahallesi atatürk caddesi 12 kartal istanbul", house number "12". Photon took
    /// "No:5" and "Cad." for words and answered with notaries and tyre shops; spelled out, it found the building
    /// or the street (search benchmark 14.11.2026). Other queries pass unchanged.
    static func address(_ query: String) -> (text: String, houseNumber: String?) {
        let lower = query.lowercased(with: Locale(identifier: "tr"))
        var text = lower
        for step in addressSteps {
            text = text.replacingOccurrences(of: step.pattern, with: step.template, options: .regularExpression)
        }
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let spelled = text
        let number = spelled.range(of: numberAfterStreet, options: .regularExpression)
            .flatMap { spelled[$0].split(whereSeparator: \.isWhitespace).last.map(String.init) }
        let changed = spelled != lower.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return (changed ? spelled : query, number)
    }

    /// Lowercased words, "sokak"/"sokağı" and "cadde"/"caddesi" alike, padded so that `contains` matches whole
    /// words: "atatürk caddesi 1" is not in "atatürk caddesi 12".
    private static func comparable(_ text: String) -> String {
        let same = ["sokağı": "sokak", "cadde": "caddesi", "bulvar": "bulvarı"]
        let words = text.lowercased(with: Locale(identifier: "tr")).split(whereSeparator: \.isWhitespace)
            .map { same[String($0)] ?? String($0) }
        return " " + words.joined(separator: " ") + " "
    }

    /// A query naming a kind of place the full-text search tends to miss: the rest of the query and Photon's
    /// osm_tag filters for that kind. Search benchmark 14.11.2026: "kartal metro istasyonu" and "akasya avm"
    /// (OSM: "Akasya Alışveriş Merkezi") found nothing right; "kartal" + railway:station and "akasya" + shop:mall
    /// put it first.
    static func focus(_ query: String) -> (name: String, tags: [String])? {
        let text = address(query).text.lowercased(with: Locale(identifier: "tr"))
        // "istasyon caddesi tuzla": the kind word is part of the street's name.
        guard text.range(of: streetWord, options: .regularExpression) == nil else { return nil }
        let words = text.split(separator: " ").map(String.init)
        for rule in focusRules {
            let name = words.filter { !rule.words.contains($0) }
            if name.count < words.count, !name.isEmpty { return (name.joined(separator: " "), rule.tags) }
        }
        return nil
    }

    static func rank(_ places: [Place], query: String) -> [Place] {
        let text = address(query).text.lowercased(with: Locale(identifier: "tr"))
        let asked = comparable(text)
        // The query names a street: streets lead, and its words lift no kind of place.
        let street = text.range(of: streetWord, options: .regularExpression) != nil
        var boosted = Set<String>()
        if let kind = focus(query) {
            // The kind asked for, not one its name suggests: "istanbul havalimanı otopark" wants the car park.
            boosted = Set(kind.tags.map { $0.replacingOccurrences(of: ":", with: "=") })
        } else if !street {
            boosted = boosts.filter { rule in rule.words.contains { text.contains($0) } }
                .reduce(into: Set<String>()) { $0.formUnion($1.categories) }
        }
        // Turkish softens k → ğ before a vowel suffix: "durak" but "durağı".
        let wantsStops = !street && (text.contains("durak") || text.contains("durağ"))

        func bucket(_ place: Place) -> Int {
            guard let category = place.category else { return 2 }
            if lines.contains(category) { return 4 }
            // The very address, street included: number 12 on another street is not it.
            if let line = place.streetAddress, asked.contains(comparable(line)) { return 0 }
            if wantsStops { return stops.contains(category) ? 1 : 2 }
            if boosted.contains(category) || (street && category.hasPrefix("highway=") && !stops.contains(category)) {
                return 1
            }
            return stops.contains(category) ? 3 : 2
        }
        // Stable: equal buckets keep Photon's relevance order.
        return places.enumerated()
            .sorted { (bucket($0.element), $0.offset) < (bucket($1.element), $1.offset) }
            .map(\.element)
    }
}
