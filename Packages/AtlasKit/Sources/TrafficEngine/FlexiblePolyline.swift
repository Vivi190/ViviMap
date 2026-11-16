import CoreLocation
import Foundation

/// HERE Flexible Polyline encoding, 2D only (https://github.com/heremaps/flexible-polyline); the Traffic
/// API takes route corridors in this form, and the Routing API returns a matched route's line in it.
enum FlexiblePolyline {
    private static let table = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    private static let values: [Character: Int] = Dictionary(uniqueKeysWithValues: zip(table, table.indices))

    /// The points of an encoded line; empty when the text is not a version 1 flexible polyline. A third
    /// dimension (elevation), when the header declares one, is read past.
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        // Every number is a run of 5-bit chunks, lowest first; a set sixth bit says another chunk follows.
        var numbers: [Int] = []
        var number = 0, shift = 0
        for character in encoded {
            guard let chunk = values[character], shift <= 60 else { return [] }
            number |= (chunk & 0x1F) << shift
            if chunk & 0x20 != 0 {
                shift += 5
            } else {
                numbers.append(number)
                number = 0
                shift = 0
            }
        }
        // The version, then a header: the precision in its low four bits, the kind of third dimension in the
        // next three. A text that ends inside a number is not a polyline.
        guard shift == 0, numbers.count >= 2, numbers[0] == 1 else { return [] }
        let scale = pow(10, Double(numbers[1] & 0xF))
        let width = (numbers[1] >> 4) & 0x7 == 0 ? 2 : 3
        var points: [CLLocationCoordinate2D] = []
        var lat = 0, lng = 0
        var index = 2
        while index + width <= numbers.count {
            // Wrapping: a damaged text must give wrong points, not an overflow trap.
            lat &+= delta(numbers[index])
            lng &+= delta(numbers[index + 1])
            points.append(CLLocationCoordinate2D(latitude: Double(lat) / scale, longitude: Double(lng) / scale))
            index += width
        }
        return points
    }

    /// A signed step from its encoded form: the sign is in the lowest bit.
    private static func delta(_ number: Int) -> Int {
        number & 1 != 0 ? ~(number >> 1) : number >> 1
    }

    static func encode(_ points: [CLLocationCoordinate2D], precision: Int = 5) -> String {
        var out = ""
        unsigned(1, &out) // format version
        unsigned(precision, &out) // header: precision, no third dimension
        let scale = pow(10, Double(precision))
        var lastLat = 0, lastLng = 0
        for point in points {
            let lat = Int((point.latitude * scale).rounded())
            let lng = Int((point.longitude * scale).rounded())
            signed(lat - lastLat, &out)
            signed(lng - lastLng, &out)
            lastLat = lat
            lastLng = lng
        }
        return out
    }

    private static func unsigned(_ value: Int, _ out: inout String) {
        var value = value
        while value > 0x1F {
            out.append(table[(value & 0x1F) | 0x20])
            value >>= 5
        }
        out.append(table[value])
    }

    private static func signed(_ value: Int, _ out: inout String) {
        unsigned(value < 0 ? ~(value << 1) : value << 1, &out)
    }
}
