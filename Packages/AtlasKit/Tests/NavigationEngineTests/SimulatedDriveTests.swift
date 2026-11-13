import CoreLocation
import Foundation
import RoutingEngine
import SearchEngine
import Testing
@testable import NavigationEngine

/// Drives a real Kartal route (live FOSSGIS Valhalla) through the guidance stack, fix by fix, the way the
/// in-app simulation does but without waiting a second per fix.
@MainActor
struct SimulatedDriveTests {
    @Test(.timeLimit(.minutes(2)))
    func followsARealRouteToArrivalWithoutRerouting() async throws {
        let origin = CLLocation(latitude: 40.8890, longitude: 29.1905)
        // A few kilometres inland: several turns, a main road and side streets.
        let destination = GeoPoint(latitude: 40.9050, longitude: 29.2100)
        let route = try #require(try await RoutePlanner().routes(from: origin, to: destination).first)
        let path = RoutePath(route.coordinates)
        #expect(path.length > 1000)

        let session = try NavigationSession()
        session.voice.isMuted = true
        let log = PromptLog()
        session.voice.onPrompt = { log.lines.append($0) }

        let speed = 12.0 // ≈ 43 km/h
        let startTime = Date.now
        let begin = path.fix(at: 0, speed: speed, timestamp: startTime)
        try session.start(route, from: begin)
        var travelled = 0.0
        while travelled < path.length + 30 {
            let fix = path.fix(at: travelled, speed: speed, timestamp: startTime.addingTimeInterval(travelled / speed))
            session.ingest(fix)
            // Ferrostar publishes state on the main queue; let it land before the next fix.
            try await Task.sleep(for: .milliseconds(3))
            travelled += 10
        }
        try await Task.sleep(for: .milliseconds(200))

        let prompts = log.lines
        #expect(session.hasArrived, "never arrived; last prompts: \(prompts.suffix(5))")
        #expect(prompts.first?.hasPrefix("Rota başladı") == true)
        #expect(prompts.last == "Hedefe ulaştın.")
        #expect(!prompts.contains("Yeni rota hesaplanıyor."), "rerouted while exactly on the route: \(prompts)")
        let turns = prompts.dropFirst().dropLast()
        #expect(turns.contains { $0.contains(" sonra ") }, "no advance warning: \(prompts)")
        #expect(turns.contains { !$0.contains(" sonra ") }, "no at-the-turn prompt: \(prompts)")
        #expect(session.durationRemaining == nil, "arrival must clear the remaining time")
    }
}

@MainActor
private final class PromptLog {
    var lines: [String] = []
}
