@preconcurrency import FerrostarCoreFFI
import Foundation
import Testing
@testable import NavigationEngine

struct RouteDirectionsTests {
    /// A step as the router gives it: its length, the banner of the maneuver it ends with (its text is the road
    /// that maneuver leads onto), and the sentence the step itself begins with.
    private func step(
        _ distance: Double, _ type: ManeuverType?, _ modifier: ManeuverModifier? = nil, onto road: String = "",
        instruction: String = "", exit: UInt8? = nil
    ) -> RouteStep {
        var banners: [VisualInstruction] = []
        if let type {
            banners.append(VisualInstruction(
                primaryContent: VisualInstructionContent(
                    text: road, maneuverType: type, maneuverModifier: modifier, roundaboutExitDegrees: nil, laneInfo: nil, exitNumbers: []
                ),
                secondaryContent: nil, subContent: nil, triggerDistanceBeforeManeuver: distance
            ))
        }
        return RouteStep(
            geometry: [], distance: distance, duration: distance / 10, roadName: nil, exits: [], instruction: instruction,
            visualInstructions: banners, spokenInstructions: [], annotations: nil, incidents: [], drivingSide: nil,
            roundaboutExitNumber: exit
        )
    }

    @Test func listsTheTurnsWithTheRoadsTheyLeadOnto() {
        let lines = RouteDirections.list(for: [
            step(350, .turn, .right, onto: "Ankara Caddesi"),
            // Only the name changes: no line, and its 200 m count towards the next turn.
            step(200, .newName, .straight, onto: "Hürriyet Caddesi"),
            step(400, .turn, .left, onto: "Kıyı Sokak"),
            step(120, .arrive, .left, onto: "Hedef"),
            step(0, nil),
        ])
        #expect(lines.map(\.id) == [0, 2, 3])
        #expect(lines.map(\.action) == ["Sağa dönün", "Sola dönün", TurkishInstructions.action(type: .arrive, modifier: .left) ?? ""])
        #expect(lines.map(\.road) == ["Ankara Caddesi", "Kıyı Sokak", nil])
        #expect(lines.map(\.distance) == [350, 600, 120])
        #expect(lines[0].symbol == ManeuverSymbols.symbol(type: .turn, modifier: .right))
    }

    /// A road without a name: the router fills the banner with the next step's own sentence, which is no name.
    @Test func aRoadWithoutANameIsNotNamed() {
        let lines = RouteDirections.list(for: [
            step(80, .turn, .right, onto: "sağa dönün."),
            step(50, .arrive, onto: "Hedef", instruction: "sağa dönün."),
            step(0, nil),
        ])
        #expect(lines.first?.action == "Sağa dönün")
        #expect(lines.first?.road == nil)
    }

    /// The exit to take is written on the step the roundabout begins; a ferry is boarded, then left.
    @Test func roundaboutsAndFerries() {
        let lines = RouteDirections.list(for: [
            step(300, .roundabout, onto: "Sahil Yolu"),
            step(40, .notification, onto: "Eskihisar - Topçular", exit: 2),
            step(4_000, .notification, .straight, onto: "İskele Caddesi"),
            step(500, .arrive, onto: "Hedef"),
            step(0, nil),
        ])
        #expect(lines.map(\.action) == [
            TurkishInstructions.action(type: .roundabout, modifier: nil, roundaboutExitNumber: 2) ?? "",
            "Feribota binin", "Feribottan inin", TurkishInstructions.action(type: .arrive, modifier: nil) ?? "",
        ])
        #expect(lines.map(\.distance) == [300, 40, 4_000, 500])
    }

    @Test func aRouteOfOneStepHasNoTurns() {
        #expect(RouteDirections.list(for: [step(100, .arrive)]).isEmpty)
        #expect(RouteDirections.list(for: []).isEmpty)
    }
}
