import CoreLocation
import Foundation
import RoutingEngine
import SearchEngine
import Testing
@testable import NavigationEngine

/// Drives a real Kartal route (live FOSSGIS Valhalla) through the guidance stack, fix by fix, the way the
/// in-app simulation does but without waiting a second per fix. Serialized: one live request at a time
/// for the shared public server.
@MainActor
@Suite(.serialized)
struct SimulatedDriveTests {
    private let speed = 12.0 // ≈ 43 km/h

    /// A few kilometres from the Kartal coast inland: several turns, a main road and side streets.
    private func kartalRoute() async throws -> (RouteOption, RoutePath) {
        let origin = CLLocation(latitude: 40.8890, longitude: 29.1905)
        let destination = GeoPoint(latitude: 40.9050, longitude: 29.2100)
        let route = try #require(try await RoutePlanner().routes(from: origin, to: destination).first)
        let path = RoutePath(route.coordinates)
        #expect(path.length > 1000)
        return (route, path)
    }

    /// Feeds fixes every 10 m from `from` to `to`; Ferrostar publishes state on the main queue, so each
    /// fix gets a moment to land before the next one.
    private func drive(_ session: NavigationSession, along path: RoutePath, from: Double, to: Double, start: Date) async throws {
        var travelled = from
        while travelled < to {
            session.ingest(path.fix(at: travelled, speed: speed, timestamp: start.addingTimeInterval(travelled / speed)))
            try await Task.sleep(for: .milliseconds(3))
            travelled += 10
        }
    }

    private func makeSession(logging log: PromptLog) throws -> NavigationSession {
        let session = NavigationSession(routes: try RoutePlanner())
        session.voice.isMuted = true
        session.voice.onPrompt = { log.lines.append($0) }
        return session
    }

    @Test(.timeLimit(.minutes(2)))
    func followsARealRouteToArrivalWithoutRerouting() async throws {
        let (route, path) = try await kartalRoute()
        let log = PromptLog()
        let session = try makeSession(logging: log)
        var updates = 0, arrivalSeen = false, arrowSeen = false
        session.onUpdate = { session in
            updates += 1
            if session.hasArrived { arrivalSeen = true }
            if !session.maneuverArrow.isEmpty { arrowSeen = true }
        }
        let startTime = Date.now
        try session.start(route, from: path.fix(at: 0, speed: speed, timestamp: startTime))
        try await drive(session, along: path, from: 0, to: path.length + 30, start: startTime)
        try await Task.sleep(for: .milliseconds(200))

        let prompts = log.lines
        #expect(session.hasArrived, "never arrived; last prompts: \(prompts.suffix(5))")
        // The lock-screen path: every update reaches the callback, the arrival included, with its time.
        #expect(updates > 10, "update callback ran \(updates) times")
        #expect(arrivalSeen, "the callback never saw the arrival")
        #expect(session.arrivedAt.map { $0 >= startTime } == true)
        #expect(prompts.first?.hasPrefix("Rota başladı") == true)
        #expect(prompts.last == "Hedefe ulaştın.")
        #expect(!prompts.contains("Yeni rota hesaplanıyor."), "rerouted while exactly on the route: \(prompts)")
        // Maneuver prompts only: camera / bump warnings ("80 metre sonra kasis.") would also match " sonra ".
        let turns = prompts.dropFirst().dropLast().filter { !$0.contains("kasis") && !$0.contains("Kasis") && !$0.contains("kamera") }
        #expect(turns.contains { $0.contains(" sonra ") }, "no advance warning: \(prompts)")
        #expect(turns.contains { !$0.contains(" sonra ") }, "no at-the-turn prompt: \(prompts)")
        #expect(session.durationRemaining == nil, "arrival must clear the remaining time")
        #expect(arrowSeen, "no turn arrow on a route with turns")
        #expect(session.maneuverArrow.isEmpty, "arrival must clear the turn arrow")
    }

    @Test(.timeLimit(.minutes(2)))
    func reroutesFromWhereTheDriverLeftTheRoute() async throws {
        let (route, path) = try await kartalRoute()
        let log = PromptLog()
        let session = try makeSession(logging: log)
        let startTime = Date.now
        try session.start(route, from: path.fix(at: 0, speed: speed, timestamp: startTime))
        try await drive(session, along: path, from: 0, to: 300, start: startTime)
        let originalStart = try #require(session.routeCoordinates.first)

        // 150 m to the side of the route, well past the 50 m deviation threshold; keep reporting it until
        // Ferrostar has fetched and loaded the new route (live Valhalla), at most ~15 s.
        let here = path.point(at: 300)
        let away = Self.offset(here.coordinate, metres: 150, bearing: here.course + 90)
        for tick in 0 ..< 150 {
            session.ingest(CLLocation(
                coordinate: away, altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1,
                course: here.course, courseAccuracy: 5, speed: speed, speedAccuracy: 0.5,
                timestamp: startTime.addingTimeInterval(300 / speed + Double(tick + 1))
            ))
            try await Task.sleep(for: .milliseconds(100))
            if let first = session.routeCoordinates.first, Self.distance(first, originalStart) > 100 { break }
        }
        try await Task.sleep(for: .milliseconds(200))

        #expect(log.lines.contains("Yeni rota hesaplanıyor."), "no reroute prompt: \(log.lines)")
        let newStart = try #require(session.routeCoordinates.first)
        #expect(Self.distance(newStart, originalStart) > 100, "route geometry was not replaced")
        #expect(Self.distance(newStart, away) < 250, "new route does not start where the driver is")
        #expect(!session.isRerouting)
    }

    /// GPS drifting 15 m off the road, as between buildings: the arrow stays on the route (Ferrostar's snapped
    /// position; the drift is inside the 50 m deviation threshold).
    @Test(.timeLimit(.minutes(2)))
    func thePuckKeepsToTheRouteThroughGPSDrift() async throws {
        let (route, path) = try await kartalRoute()
        let session = try makeSession(logging: PromptLog())
        var pucks: [CLLocation] = []
        session.onPuck = { pucks.append($0) }
        let startTime = Date.now
        try session.start(route, from: path.fix(at: 0, speed: speed, timestamp: startTime))
        var travelled = 10.0
        while travelled < 600 {
            let here = path.point(at: travelled)
            session.ingest(CLLocation(
                coordinate: Self.offset(here.coordinate, metres: 15, bearing: here.course + 90), altitude: 0,
                horizontalAccuracy: 10, verticalAccuracy: -1, course: here.course, courseAccuracy: 10,
                speed: speed, speedAccuracy: 0.5, timestamp: startTime.addingTimeInterval(travelled / speed)
            ))
            try await Task.sleep(for: .milliseconds(3))
            travelled += 10
        }
        try await Task.sleep(for: .milliseconds(200))

        #expect(pucks.count > 20, "puck updates: \(pucks.count)")
        let drifting = pucks.suffix(20).filter { path.project($0.coordinate, tolerance: 3) == nil }
        #expect(drifting.isEmpty, "\(drifting.count) of the last 20 pucks are off the route")
    }

    /// Phase 8, long drive: Pendik to Kadıköy (over 18 km of main road and city streets) through the whole
    /// guidance stack. It has to arrive without a reroute, and memory must not grow with the distance driven:
    /// a leak per fix (about 1 000 fixes per half) would show as megabytes in the second half.
    @Test(.timeLimit(.minutes(5)))
    func longDriveArrivesWithoutMemoryGrowth() async throws {
        let origin = CLLocation(latitude: 40.8767, longitude: 29.2337)
        let destination = GeoPoint(latitude: 40.9905, longitude: 29.0280)
        let route = try #require(try await RoutePlanner().routes(from: origin, to: destination).first)
        let path = RoutePath(route.coordinates)
        #expect(path.length > 18_000, "route is only \(Int(path.length)) m")
        let log = PromptLog()
        let session = try makeSession(logging: log)
        let startTime = Date.now
        try session.start(route, from: path.fix(at: 0, speed: speed, timestamp: startTime))
        try await drive(session, along: path, from: 0, to: path.length / 2, start: startTime)
        let halfway = Self.peakMemory()
        try await drive(session, along: path, from: path.length / 2, to: path.length + 30, start: startTime)
        try await Task.sleep(for: .milliseconds(200))
        let grown = Self.peakMemory() - halfway

        #expect(session.hasArrived, "never arrived; last prompts: \(log.lines.suffix(5))")
        #expect(!log.lines.contains("Yeni rota hesaplanıyor."), "rerouted while exactly on the route")
        #expect(log.lines.count > 20, "only \(log.lines.count) prompts in \(Int(path.length)) m")
        #expect(grown < 8 * 1024 * 1024, "memory grew \(grown / 1024) KB in the second half")
    }

    /// Peak resident memory of this process so far (bytes on Darwin): a leak keeps raising it.
    private static func peakMemory() -> Int64 {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int64(usage.ru_maxrss)
    }

    private static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Flat-earth offset, fine for a few hundred metres.
    private static func offset(_ c: CLLocationCoordinate2D, metres: Double, bearing: Double) -> CLLocationCoordinate2D {
        let θ = bearing * .pi / 180
        return CLLocationCoordinate2D(
            latitude: c.latitude + metres * cos(θ) / 111_320,
            longitude: c.longitude + metres * sin(θ) / (111_320 * cos(c.latitude * .pi / 180))
        )
    }
}

@MainActor
private final class PromptLog {
    var lines: [String] = []
}
