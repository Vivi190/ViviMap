import Foundation

/// A point typed or pasted into the search field: "40.8890, 29.1905", a location shared as a link from Google
/// Maps, Apple Maps, Yandex Maps or WhatsApp ("https://maps.google.com/?q=40.889,29.1905"), or a "geo:"
/// address. Read on the device, nothing is asked of anyone. The one exception is a short link of Google Maps
/// ("maps.app.goo.gl/…", what its app's "Share" gives): it has no coordinates in it, so the service that issued
/// it is asked where it leads (`place(following:)`).
enum CoordinateQuery {
    static func place(from text: String) -> Place? {
        let pattern = #"^\s*(-?\d{1,2}(?:\.\d+)?)\s*[,\s]\s*(-?\d{1,3}(?:\.\d+)?)\s*$"#
        if let match = text.firstMatch(of: try! Regex(pattern)), match.count == 3,
           let latitude = match[1].substring.flatMap({ Double($0) }), let longitude = match[2].substring.flatMap({ Double($0) }) {
            return valid(latitude: latitude, longitude: longitude).map { place(at: $0, label: nil, shared: false) }
        }
        return link(text).map { place(at: $0.point, label: $0.label, shared: true) }
    }

    private static func place(at point: GeoPoint, label: String?, shared: Bool) -> Place {
        let coordinates = String(format: "%.5f, %.5f", point.latitude, point.longitude)
        return Place(
            id: "coord:\(coordinates)", name: label ?? coordinates, subtitle: shared ? "Paylaşılan konum" : "Koordinat",
            point: point, category: nil
        )
    }

    /// A short link of Google Maps in a pasted text: "https://maps.app.goo.gl/…", "https://goo.gl/maps/…".
    static func shortLink(in text: String) -> URL? {
        for word in text.split(whereSeparator: \.isWhitespace) {
            guard let url = URL(string: String(word)), url.scheme?.lowercased() == "https", let host = url.host?.lowercased()
            else { continue }
            if host == "maps.app.goo.gl" || (host == "goo.gl" && url.path.hasPrefix("/maps/")) { return url }
        }
        return nil
    }

    /// The place a short link leads to. One request to the service that issued the link, carrying the link and
    /// nothing else: it answers with the long link, which has the point in it. nil when it does not answer, or
    /// leads somewhere without a point.
    static func place(following short: URL, session: URLSession = .shared) async -> Place? {
        var request = URLRequest(url: short)
        // The answer is in where the request ends up, not in a page.
        request.httpMethod = "HEAD"
        request.timeoutInterval = 8
        request.setValue("Atlas-iOS/1.0 (personal navigation app)", forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await session.data(for: request), var target = response.url else { return nil }
        // A consent page in between carries the link it was asked for.
        if target.host?.contains("consent.") == true,
           let onward = URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "continue" })?.value,
           let url = URL(string: onward) {
            target = url
        }
        return link(target.absoluteString).map { place(at: $0.point, label: $0.label, shared: true) }
    }

    /// The point a pasted link shows, and the name the link gives it, if it gives one.
    static func link(_ text: String) -> (point: GeoPoint, label: String?)? {
        // The link may stand in a sentence ("Buradayım: https://…").
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let token = words.first(where: { word in
            let lower = word.lowercased()
            return lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("geo:")
        }) else { return nil }
        if token.lowercased().hasPrefix("geo:") { return geo(String(token.dropFirst(4))) }
        guard let components = URLComponents(string: token) else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
        }
        if (components.host ?? "").lowercased().contains("yandex") {
            // Yandex writes the longitude first: "pt=29.1905,40.889".
            for name in ["pt", "whatshere[point]", "ll"] {
                if let pair = value(name).flatMap(numbers(in:)), let spot = valid(latitude: pair.1, longitude: pair.0) {
                    return (spot, nil)
                }
            }
            return nil
        }
        // Google's place links carry the place itself as "!3d<lat>!4d<lon>"; the "@lat,lon" before it is only
        // where the map was looking.
        if let match = token.firstMatch(of: try! Regex(#"!3d(-?\d{1,2}(?:\.\d+)?)!4d(-?\d{1,3}(?:\.\d+)?)"#)), match.count == 3,
           let latitude = match[1].substring.flatMap({ Double($0) }), let longitude = match[2].substring.flatMap({ Double($0) }),
           let spot = valid(latitude: latitude, longitude: longitude) {
            return (spot, name(inPath: components.path))
        }
        for name in ["q", "query", "ll", "destination", "daddr", "coordinate", "center", "sll"] {
            guard let pair = value(name).flatMap(numbers(in:)), let spot = valid(latitude: pair.0, longitude: pair.1) else { continue }
            // Apple Maps names the place beside its point: "ll=40.889,29.1905&q=Kıyı Pastanesi".
            let label = [value("name"), value("q")].compactMap { $0 }.first { numbers(in: $0) == nil }
            return (spot, label.map { $0.replacingOccurrences(of: "+", with: " ") })
        }
        if let at = components.path.range(of: "@"), let pair = numbers(in: String(components.path[at.upperBound...])),
           let spot = valid(latitude: pair.0, longitude: pair.1) {
            return (spot, name(inPath: components.path))
        }
        // "/maps/search/40.889,29.1905": a dropped pin has its point as a part of the path.
        for part in components.path.split(separator: "/") {
            if let pair = numbers(in: String(part)), let spot = valid(latitude: pair.0, longitude: pair.1) { return (spot, nil) }
        }
        return nil
    }

    /// "40.889,29.1905", "40.889,29.1905?z=17", "0,0?q=40.889,29.1905(Kartal)".
    private static func geo(_ body: String) -> (point: GeoPoint, label: String?)? {
        let parts = body.split(separator: "?", maxSplits: 1).map(String.init)
        // "q=" is the pin and its label; what stands before the "?" is then only the centre of the map.
        if parts.count == 2,
           let pin = parts[1].split(separator: "&").first(where: { $0.hasPrefix("q=") }).flatMap({ String($0.dropFirst(2)).removingPercentEncoding }),
           let pair = numbers(in: pin), let spot = valid(latitude: pair.0, longitude: pair.1) {
            let label = pin.firstMatch(of: try! Regex(#"\(([^)]+)\)"#)).flatMap { $0[1].substring }
            return (spot, label.map { $0.replacingOccurrences(of: "+", with: " ") })
        }
        guard let pair = numbers(in: parts.first ?? ""), let spot = valid(latitude: pair.0, longitude: pair.1) else { return nil }
        return (spot, nil)
    }

    /// "/maps/place/Kıyı+Pastanesi/@40.89,29.19,17z": the name Google puts in a place link's path.
    private static func name(inPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let index = parts.firstIndex(of: "place"), index + 1 < parts.count else { return nil }
        let name = parts[index + 1].replacingOccurrences(of: "+", with: " ")
        return name.hasPrefix("@") || numbers(in: name) != nil ? nil : name
    }

    /// The two numbers a text begins with: "40.889,29.1905(Kartal)", "40.889,29.1905,17z", "loc:40.889,29.1905".
    private static func numbers(in text: String) -> (Double, Double)? {
        let pattern = #"^\s*(?:loc:)?\s*(-?\d{1,3}(?:\.\d+)?)\s*,\s*(-?\d{1,3}(?:\.\d+)?)"#
        guard let match = text.firstMatch(of: try! Regex(pattern)), match.count == 3,
              let first = match[1].substring.flatMap({ Double($0) }), let second = match[2].substring.flatMap({ Double($0) })
        else { return nil }
        return (first, second)
    }

    /// A point on the globe; (0, 0) is a link's way of saying it has none.
    private static func valid(latitude: Double, longitude: Double) -> GeoPoint? {
        guard (-90 ... 90).contains(latitude), (-180 ... 180).contains(longitude), latitude != 0 || longitude != 0 else { return nil }
        return GeoPoint(latitude: latitude, longitude: longitude)
    }
}
