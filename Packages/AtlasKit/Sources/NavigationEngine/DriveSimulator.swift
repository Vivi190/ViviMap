import CoreLocation

/// Test drive along a route without moving: one fix per second at constant speed, heading along the
/// segment being driven. A development aid only — the app labels a simulated session on screen.
@MainActor
public final class DriveSimulator {
    private var task: Task<Void, Never>?

    public init() {}

    /// `emit` gets each fix; the drive stops at the last coordinate.
    public func start(
        along coordinates: [CLLocationCoordinate2D],
        speed: CLLocationSpeed,
        emit: @escaping @MainActor (CLLocation) -> Void
    ) {
        stop()
        let path = RoutePath(coordinates)
        guard path.length > 0, speed > 0 else { return }
        task = Task {
            var travelled: CLLocationDistance = 0
            while !Task.isCancelled {
                let arrived = travelled >= path.length
                emit(path.fix(at: travelled, speed: arrived ? 0 : speed, timestamp: .now))
                if arrived { break }
                try? await Task.sleep(for: .seconds(1))
                travelled = min(travelled + speed, path.length)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}

/// A polyline measured in metres, for positions along a route.
struct RoutePath {
    let coordinates: [CLLocationCoordinate2D]
    /// Distance from the start to each coordinate.
    let offsets: [CLLocationDistance]

    init(_ coordinates: [CLLocationCoordinate2D]) {
        self.coordinates = coordinates
        var offsets: [CLLocationDistance] = coordinates.isEmpty ? [] : [0]
        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let step = CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            offsets.append(offsets[offsets.count - 1] + step)
        }
        self.offsets = offsets
    }

    var length: CLLocationDistance { offsets.last ?? 0 }

    /// Position and direction of travel `distance` metres from the start, clamped to the route.
    func point(at distance: CLLocationDistance) -> (coordinate: CLLocationCoordinate2D, course: CLLocationDirection) {
        guard coordinates.count > 1 else { return (coordinates.first ?? .init(), 0) }
        // The segment being driven: the first one ending beyond `distance` (zero-length ones never qualify,
        // so duplicate points cannot produce a bogus course).
        let index = offsets.indices.dropLast().first { offsets[$0 + 1] > distance } ?? coordinates.count - 2
        let a = coordinates[index], b = coordinates[index + 1]
        let span = offsets[index + 1] - offsets[index]
        let fraction = span > 0 ? min(max((distance - offsets[index]) / span, 0), 1) : 0
        let coordinate = CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * fraction,
            longitude: a.longitude + (b.longitude - a.longitude) * fraction
        )
        return (coordinate, Self.bearing(from: a, to: b))
    }

    /// Where `point` meets the line, if it is within `tolerance` metres: the distance from the start there
    /// and the direction of travel. The nearest segment wins; `window` limits the search to one stretch, so a
    /// road the route takes twice cannot match the wrong pass.
    func project(
        _ point: CLLocationCoordinate2D, tolerance: CLLocationDistance, within window: ClosedRange<CLLocationDistance>? = nil
    ) -> (offset: CLLocationDistance, course: CLLocationDirection)? {
        let metresPerLon = 111_320 * cos(point.latitude * .pi / 180), metresPerLat = 110_540.0
        var best: (distance: Double, offset: Double, course: Double)?
        for index in coordinates.indices.dropLast() {
            let span = offsets[index + 1] - offsets[index]
            guard span > 0 else { continue }
            if let window, offsets[index + 1] < window.lowerBound || offsets[index] > window.upperBound { continue }
            let a = coordinates[index], b = coordinates[index + 1]
            let ax = (a.longitude - point.longitude) * metresPerLon, ay = (a.latitude - point.latitude) * metresPerLat
            let dx = (b.longitude - a.longitude) * metresPerLon, dy = (b.latitude - a.latitude) * metresPerLat
            let t = max(0, min(1, -(ax * dx + ay * dy) / (dx * dx + dy * dy)))
            let distance = hypot(ax + t * dx, ay + t * dy)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (distance, offsets[index] + t * span, Self.bearing(from: a, to: b))
            }
        }
        return best.map { ($0.offset, $0.course) }
    }

    /// The line between two distances from the start, clamped to the route.
    func slice(from start: CLLocationDistance, to end: CLLocationDistance) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 1, end > start else { return [] }
        return [point(at: start).coordinate]
            + zip(coordinates, offsets).filter { $0.1 > start && $0.1 < end }.map(\.0)
            + [point(at: end).coordinate]
    }

    /// The line after `distance` metres, starting exactly there (what is left of a route).
    func remainder(after distance: CLLocationDistance) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 1 else { return coordinates }
        return [point(at: distance).coordinate] + zip(coordinates, offsets).filter { $0.1 > distance }.map(\.0)
    }

    func fix(at distance: CLLocationDistance, speed: CLLocationSpeed, timestamp: Date) -> CLLocation {
        let (coordinate, course) = point(at: distance)
        return CLLocation(
            coordinate: coordinate, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1,
            course: course, courseAccuracy: 5, speed: speed, speedAccuracy: 0.5, timestamp: timestamp
        )
    }

    /// Initial great-circle bearing in degrees clockwise from north.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDirection {
        let φ1 = a.latitude * .pi / 180, φ2 = b.latitude * .pi / 180
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}
