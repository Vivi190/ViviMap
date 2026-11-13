import CoreLocation
import Foundation

/// HERE Flexible Polyline encoding, 2D only (https://github.com/heremaps/flexible-polyline); the Traffic
/// API takes route corridors in this form.
enum FlexiblePolyline {
    private static let table = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

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
