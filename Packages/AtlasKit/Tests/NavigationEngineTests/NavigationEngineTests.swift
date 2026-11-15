@preconcurrency import FerrostarCoreFFI
import CoreLocation
import Testing
@testable import NavigationEngine

struct TurkishInstructionsTests {
    @Test func aTurnAtATrafficLight() {
        #expect(TurkishInstructions.atLights("Sağa dön") == "Işıklarda sağa dön")
        #expect(TurkishInstructions.atLights("U dönüşü yap") == "Işıklarda U dönüşü yap")
        #expect(TurkishInstructions.spoken(action: "Işıklarda sağa dön", distance: 300, road: "Ankara Caddesi")
            == "300 metre sonra ışıklarda sağa dön, Ankara Caddesi.")
    }

    @Test func turnsAndKeeps() {
        #expect(TurkishInstructions.action(type: .turn, modifier: .left) == "Sola dön")
        #expect(TurkishInstructions.action(type: .turn, modifier: .slightRight) == "Hafif sağa dön")
        #expect(TurkishInstructions.action(type: .turn, modifier: .uTurn) == "U dönüşü yap")
        #expect(TurkishInstructions.action(type: .continue, modifier: .straight) == "Düz devam et")
        #expect(TurkishInstructions.action(type: .endOfRoad, modifier: .right) == "Yolun sonunda sağa dön")
    }

    @Test func rampsForksMergesAndArrival() {
        #expect(TurkishInstructions.action(type: .offRamp, modifier: .slightRight) == "Sağdaki çıkışa gir")
        #expect(TurkishInstructions.action(type: .onRamp, modifier: .left) == "Soldaki bağlantı yoluna gir")
        #expect(TurkishInstructions.action(type: .fork, modifier: .slightLeft) == "Yol ayrımında soldan devam et")
        #expect(TurkishInstructions.action(type: .merge, modifier: .right) == "Sağdan yola katıl")
        #expect(TurkishInstructions.action(type: .arrive, modifier: .right) == "Hedef sağında")
        #expect(TurkishInstructions.action(type: nil, modifier: nil) == nil)
    }

    @Test func roundaboutExitsByBearing() {
        #expect(TurkishInstructions.action(type: .roundabout, modifier: nil, roundaboutExitDegrees: 90) == "Göbekten sağa çık")
        #expect(TurkishInstructions.action(type: .roundabout, modifier: nil, roundaboutExitDegrees: 180) == "Göbekten düz çık")
        #expect(TurkishInstructions.action(type: .roundabout, modifier: nil, roundaboutExitDegrees: 270) == "Göbekten sola çık")
    }

    @Test func spokenSentences() {
        #expect(TurkishInstructions.spoken(action: "Sola dön", distance: 287, road: "Ankara Caddesi")
            == "300 metre sonra sola dön, Ankara Caddesi.")
        #expect(TurkishInstructions.spoken(action: "U dönüşü yap", distance: 1_234, road: nil)
            == "1,2 kilometre sonra U dönüşü yap.")
        #expect(TurkishInstructions.spoken(action: "Sağa dön", distance: nil, road: "") == "Sağa dön.")
        #expect(TurkishInstructions.spoken(action: "Sağa dön", distance: 120, road: "İhlas Sokağı", then: "Sola dön")
            == "120 metre sonra sağa dön, İhlas Sokağı, ardından sola dön.")
        #expect(TurkishInstructions.spoken(action: "Sağa dön", distance: nil, road: nil, then: "Hedef solunda")
            == "Sağa dön, ardından hedef solunda.")
    }

    @Test func followUpOnlyForCloseRealManeuvers() {
        #expect(TurkishInstructions.followUp(type: .turn, modifier: .left, roundaboutExitDegrees: nil, after: 80) == "Sola dön")
        #expect(TurkishInstructions.followUp(type: .arrive, modifier: .right, roundaboutExitDegrees: nil, after: 40) == "Hedef sağında")
        // Too far to chain, or not worth a word.
        #expect(TurkishInstructions.followUp(type: .turn, modifier: .left, roundaboutExitDegrees: nil, after: 400) == nil)
        #expect(TurkishInstructions.followUp(type: .newName, modifier: .straight, roundaboutExitDegrees: nil, after: 50) == nil)
        #expect(TurkishInstructions.followUp(type: .continue, modifier: .slightLeft, roundaboutExitDegrees: nil, after: 50) == nil)
        #expect(TurkishInstructions.followUp(type: .turn, modifier: .straight, roundaboutExitDegrees: nil, after: 50) == nil)
        #expect(TurkishInstructions.followUp(type: .exitRoundabout, modifier: .right, roundaboutExitDegrees: nil, after: 30) == nil)
        #expect(TurkishInstructions.followUp(type: nil, modifier: nil, roundaboutExitDegrees: nil, after: 50) == nil)
    }
}

struct AnnouncementPlannerTests {
    @Test func cityStagesOncePerStep() {
        var planner = AnnouncementPlanner()
        #expect(planner.stage(step: 5, distance: 600, speed: 0) == nil)
        #expect(planner.stage(step: 5, distance: 380, speed: 0) == .early)
        #expect(planner.stage(step: 5, distance: 300, speed: 0) == nil)
        #expect(planner.stage(step: 5, distance: 110, speed: 0) == .close)
        #expect(planner.stage(step: 5, distance: 20, speed: 0) == .now)
        #expect(planner.stage(step: 5, distance: 5, speed: 0) == nil)
        #expect(planner.stage(step: 4, distance: 350, speed: 0) == .early) // next maneuver resets
    }

    @Test func highwayAnnouncesEarlier() {
        var planner = AnnouncementPlanner()
        #expect(planner.stage(step: 9, distance: 1_000, speed: 25) == nil)
        #expect(planner.stage(step: 9, distance: 600, speed: 25) == .early)
        #expect(planner.stage(step: 9, distance: 200, speed: 25) == .close)
        #expect(planner.stage(step: 9, distance: 70, speed: 25) == .now)
    }

    @Test func shortStepSkipsTheEarlyCall() {
        var planner = AnnouncementPlanner()
        #expect(planner.stage(step: 2, distance: 90, speed: 6) == .close)
        #expect(planner.stage(step: 2, distance: 300, speed: 6) == nil) // never back to a farther stage
    }
}

struct TrafficLightManeuverTests {
    private let junction = CLLocationCoordinate2D(latitude: 40.8890, longitude: 29.1905)

    @Test func aLightAtTheJunctionCountsOneDownTheRoadDoesNot() {
        let close = CLLocationCoordinate2D(latitude: 40.8890 + 20 / 110_540.0, longitude: 29.1905) // 20 m north
        let far = CLLocationCoordinate2D(latitude: 40.8890 + 60 / 110_540.0, longitude: 29.1905) // 60 m north
        #expect(NavigationSession.nearLight(junction, lights: [far, close]))
        #expect(!NavigationSession.nearLight(junction, lights: [far]))
    }

    @Test func onlyPlainTurnsAreAtTheLights() {
        #expect(NavigationSession.turnsAtJunction(.turn))
        #expect(NavigationSession.turnsAtJunction(.endOfRoad))
        #expect(!NavigationSession.turnsAtJunction(.roundabout))
        #expect(!NavigationSession.turnsAtJunction(.offRamp))
        #expect(!NavigationSession.turnsAtJunction(nil))
    }
}
