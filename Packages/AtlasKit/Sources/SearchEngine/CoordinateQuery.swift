import Foundation

/// "40.8890, 29.1905" or "40.8890 29.1905" → a place at that coordinate (search by coordinates).
enum CoordinateQuery {
    static func place(from text: String) -> Place? {
        let pattern = #"^\s*(-?\d{1,2}(?:\.\d+)?)\s*[,\s]\s*(-?\d{1,3}(?:\.\d+)?)\s*$"#
        guard let match = text.firstMatch(of: try! Regex(pattern)),
              match.count == 3,
              let latText = match[1].substring, let lonText = match[2].substring,
              let lat = Double(latText), let lon = Double(lonText),
              (-90 ... 90).contains(lat), (-180 ... 180).contains(lon)
        else { return nil }
        let name = String(format: "%.5f, %.5f", lat, lon)
        return Place(id: "coord:\(name)", name: name, subtitle: "Koordinat", point: GeoPoint(latitude: lat, longitude: lon), category: nil)
    }
}
