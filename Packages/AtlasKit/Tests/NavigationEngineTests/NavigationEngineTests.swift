@preconcurrency import FerrostarCoreFFI
import CoreLocation
import Foundation
import Testing
@testable import NavigationEngine

struct TurkishInstructionsTests {
    @Test func aTurnAtATrafficLight() {
        #expect(TurkishInstructions.atLights("Sağa dönün") == "Işıklarda sağa dönün")
        #expect(TurkishInstructions.atLights("Geri dönün") == "Işıklarda geri dönün")
        #expect(TurkishInstructions.spoken(action: "Işıklarda sağa dönün", distance: 300, road: "Ankara Caddesi")
            == "300 metre sonra ışıklarda sağa dönün, Ankara Caddesi.")
    }

    @Test func turnsAndKeeps() {
        #expect(TurkishInstructions.action(type: .turn, modifier: .left) == "Sola dönün")
        #expect(TurkishInstructions.action(type: .turn, modifier: .slightRight) == "Hafif sağa dönün")
        #expect(TurkishInstructions.action(type: .turn, modifier: .sharpLeft) == "Keskin sola dönün")
        #expect(TurkishInstructions.action(type: .turn, modifier: .uTurn) == "Geri dönün")
        #expect(TurkishInstructions.action(type: .continue, modifier: .straight) == "Düz devam edin")
        #expect(TurkishInstructions.action(type: .newName, modifier: .slightRight) == "Hafif sağdan devam edin")
        #expect(TurkishInstructions.action(type: .endOfRoad, modifier: .right) == "Yolun sonunda sağa dönün")
    }

    @Test func rampsForksMergesAndArrival() {
        #expect(TurkishInstructions.action(type: .offRamp, modifier: .slightRight) == "Sağdaki çıkıştan çıkın")
        #expect(TurkishInstructions.action(type: .offRamp, modifier: nil) == "Çıkıştan çıkın")
        #expect(TurkishInstructions.action(type: .onRamp, modifier: .left) == "Soldaki bağlantı yoluna girin")
        #expect(TurkishInstructions.action(type: .fork, modifier: .slightLeft) == "Yol ayrımında soldan devam edin")
        #expect(TurkishInstructions.action(type: .merge, modifier: .right) == "Sağdan yola katılın")
        #expect(TurkishInstructions.action(type: .arrive, modifier: .right) == "Hedefiniz sağda")
        #expect(TurkishInstructions.action(type: .depart, modifier: nil) == "Rotaya başlayın")
        #expect(TurkishInstructions.action(type: nil, modifier: nil) == nil)
    }

    /// Valhalla sends "turn left to stay on X", and every U-turn, as `continue`.
    @Test func aContinueThatTurnsIsATurn() {
        #expect(TurkishInstructions.action(type: .continue, modifier: .left) == "Sola dönün")
        #expect(TurkishInstructions.action(type: .continue, modifier: .sharpRight) == "Keskin sağa dönün")
        #expect(TurkishInstructions.action(type: .continue, modifier: .uTurn) == "Geri dönün")
        // A slight bend on the same road is still "keep left".
        #expect(TurkishInstructions.action(type: .continue, modifier: .slightLeft) == "Hafif soldan devam edin")
        #expect(TurkishInstructions.isTurn(type: .continue, modifier: .left))
        #expect(TurkishInstructions.isTurn(type: .continue, modifier: .uTurn))
        #expect(!TurkishInstructions.isTurn(type: .continue, modifier: .slightLeft))
        #expect(!TurkishInstructions.isTurn(type: .continue, modifier: .straight))
        #expect(TurkishInstructions.followUp(type: .continue, modifier: .left, roundaboutExitDegrees: nil, after: 80) == "Sola dönün")
    }

    @Test func roundaboutExitsByNumberThenByBearing() {
        #expect(TurkishInstructions.action(type: .roundabout, modifier: nil, roundaboutExitDegrees: 180, roundaboutExitNumber: 2)
            == "Döner kavşakta ikinci çıkıştan çıkın")
        // The first maneuver of the recorded Kartal route: the fourth exit, back the way the car came (7°).
        #expect(TurkishInstructions.action(type: .roundabout, modifier: .slightRight, roundaboutExitDegrees: 7, roundaboutExitNumber: 4)
            == "Döner kavşakta dördüncü çıkıştan çıkın")
        #expect(TurkishInstructions.action(type: .rotary, modifier: nil, roundaboutExitDegrees: 90, roundaboutExitNumber: 1)
            == "Döner kavşakta birinci çıkıştan çıkın")
        // No number: by the angle driven round it.
        #expect(TurkishInstructions.action(type: .roundabout, modifier: nil, roundaboutExitDegrees: 90) == "Döner kavşaktan sağa çıkın")
        #expect(TurkishInstructions.action(type: .roundabout, modifier: nil, roundaboutExitDegrees: 180) == "Döner kavşaktan düz devam edin")
        #expect(TurkishInstructions.action(type: .roundabout, modifier: nil, roundaboutExitDegrees: 270) == "Döner kavşaktan sola çıkın")
        // A U-turn is 0°, given on either side of the 0/360 wrap.
        #expect(TurkishInstructions.action(type: .roundabout, modifier: .slightRight, roundaboutExitDegrees: 7) == "Döner kavşaktan geri dönün")
        #expect(TurkishInstructions.action(type: .roundabout, modifier: nil, roundaboutExitDegrees: 350) == "Döner kavşaktan geri dönün")
        // A number there is no word for falls back to the angle.
        #expect(TurkishInstructions.action(type: .roundabout, modifier: nil, roundaboutExitDegrees: 90, roundaboutExitNumber: 0) == "Döner kavşaktan sağa çıkın")
        #expect(TurkishInstructions.action(type: .roundabout, modifier: nil, roundaboutExitDegrees: 90, roundaboutExitNumber: 11) == "Döner kavşaktan sağa çıkın")
        #expect(TurkishInstructions.action(type: .roundabout, modifier: .left) == "Döner kavşaktan sola çıkın")
        #expect(TurkishInstructions.action(type: .exitRoundabout, modifier: .right, roundaboutExitDegrees: 7) == "Döner kavşaktan çıkın")
    }

    @Test func theRoundaboutSymbolFollowsTheExit() {
        #expect(ManeuverSymbols.symbol(type: .roundabout, modifier: nil, roundaboutExitDegrees: 90) == "arrow.triangle.turn.up.right.circle")
        #expect(ManeuverSymbols.symbol(type: .roundabout, modifier: nil, roundaboutExitDegrees: 180) == "arrow.up")
        #expect(ManeuverSymbols.symbol(type: .roundabout, modifier: nil, roundaboutExitDegrees: 270) == "arrow.turn.up.left")
        #expect(ManeuverSymbols.symbol(type: .roundabout, modifier: .slightRight, roundaboutExitDegrees: 7) == "arrow.uturn.left")
        #expect(ManeuverSymbols.symbol(type: .rotary, modifier: nil, roundaboutExitDegrees: 330) == "arrow.uturn.left")
        // Without an angle the modifier decides; inside the circle the way out is to the right.
        #expect(ManeuverSymbols.symbol(type: .roundabout, modifier: .left) == "arrow.turn.up.left")
        #expect(ManeuverSymbols.symbol(type: .roundabout, modifier: nil) == "arrow.triangle.turn.up.right.circle")
        #expect(ManeuverSymbols.symbol(type: .exitRoundabout, modifier: .right, roundaboutExitDegrees: 7) == "arrow.triangle.turn.up.right.circle")
        #expect(ManeuverSymbols.symbol(type: .turn, modifier: .left) == "arrow.turn.up.left")
    }

    @Test func spokenSentences() {
        #expect(TurkishInstructions.spoken(action: "Sola dönün", distance: 287, road: "Ankara Caddesi")
            == "300 metre sonra sola dönün, Ankara Caddesi.")
        #expect(TurkishInstructions.spoken(action: "Geri dönün", distance: 1_234, road: nil)
            == "1,2 kilometre sonra geri dönün.")
        #expect(TurkishInstructions.spoken(action: "Sağa dönün", distance: nil, road: "") == "Sağa dönün.")
        #expect(TurkishInstructions.spoken(action: "Sağa dönün", distance: 120, road: "İhlas Sokağı", then: "Sola dönün")
            == "120 metre sonra sağa dönün, İhlas Sokağı, ardından sola dönün.")
        #expect(TurkishInstructions.spoken(action: "Sağa dönün", distance: nil, road: nil, then: "Hedefiniz solda")
            == "Sağa dönün, ardından hedefiniz solda.")
    }

    @Test func wholeKilometresHaveNoDecimal() {
        #expect(TurkishInstructions.distancePhrase(1_000) == "1 kilometre")
        #expect(TurkishInstructions.distancePhrase(1_049) == "1 kilometre")
        #expect(TurkishInstructions.distancePhrase(1_050) == "1,1 kilometre")
        #expect(TurkishInstructions.distancePhrase(2_000) == "2 kilometre")
        #expect(TurkishInstructions.distancePhrase(12_300) == "12 kilometre")
        #expect(TurkishInstructions.distancePhrase(940) == "950 metre")
    }

    @Test func approachingTheDestination() {
        #expect(TurkishInstructions.action(type: .arrive, modifier: nil) == "Hedef")
        #expect(TurkishInstructions.action(type: .arrive, modifier: .left) == "Hedefiniz solda")
        #expect(TurkishInstructions.arrival(distance: 395, modifier: nil) == "Hedefe 400 metre kaldı.")
        #expect(TurkishInstructions.arrival(distance: 119, modifier: .left) == "Hedefe 120 metre kaldı, solda.")
        #expect(TurkishInstructions.arrival(distance: 77, modifier: .slightRight) == "Hedefe 80 metre kaldı, sağda.")
        #expect(TurkishInstructions.arrival(distance: 1_000, modifier: nil) == "Hedefe 1 kilometre kaldı.")
        // At the destination itself only its side is a sentence.
        #expect(TurkishInstructions.arrival(distance: nil, modifier: .right) == "Hedefiniz sağda.")
    }

    /// A stop on the way is never called the destination: the trip goes on from there.
    @Test func approachingAStopOnTheWay() {
        #expect(TurkishInstructions.action(type: .arrive, modifier: .left, isStop: true) == "Ara durak solda")
        #expect(TurkishInstructions.action(type: .arrive, modifier: .sharpRight, isStop: true) == "Ara durak sağda")
        #expect(TurkishInstructions.action(type: .arrive, modifier: nil, isStop: true) == "Ara durak")
        #expect(TurkishInstructions.arrival(distance: 395, modifier: nil, isStop: true) == "Ara durağa 400 metre kaldı.")
        #expect(TurkishInstructions.arrival(distance: 119, modifier: .left, isStop: true) == "Ara durağa 120 metre kaldı, solda.")
        #expect(TurkishInstructions.arrival(distance: nil, modifier: .slightRight, isStop: true) == "Ara durak sağda.")
        #expect(TurkishInstructions.followUp(type: .arrive, modifier: nil, roundaboutExitDegrees: nil, after: 40, isStop: true)
            == "Ara durağa ulaşacaksınız")
        let then = TurkishInstructions.followUp(type: .arrive, modifier: .left, roundaboutExitDegrees: nil, after: 40, isStop: true)
        #expect(then == "Ara durak solda")
        #expect(TurkishInstructions.spoken(action: "Sağa dönün", distance: 120, road: nil, then: then)
            == "120 metre sonra sağa dönün, ardından ara durak solda.")
        // The flag means nothing to any other maneuver.
        #expect(TurkishInstructions.action(type: .turn, modifier: .left, isStop: true) == "Sola dönün")
    }

    @Test func followUpOnlyForCloseRealManeuvers() {
        #expect(TurkishInstructions.followUp(type: .turn, modifier: .left, roundaboutExitDegrees: nil, after: 80) == "Sola dönün")
        #expect(TurkishInstructions.followUp(type: .arrive, modifier: .right, roundaboutExitDegrees: nil, after: 40) == "Hedefiniz sağda")
        // With no side, "ardından hedef" would not be a clause.
        #expect(TurkishInstructions.followUp(type: .arrive, modifier: nil, roundaboutExitDegrees: nil, after: 40) == "Hedefinize ulaşacaksınız")
        #expect(TurkishInstructions.followUp(type: .roundabout, modifier: nil, roundaboutExitDegrees: 180, roundaboutExitNumber: 3, after: 60)
            == "Döner kavşakta üçüncü çıkıştan çıkın")
        // Too far to chain, or not worth a word.
        #expect(TurkishInstructions.followUp(type: .turn, modifier: .left, roundaboutExitDegrees: nil, after: 400) == nil)
        #expect(TurkishInstructions.followUp(type: .newName, modifier: .straight, roundaboutExitDegrees: nil, after: 50) == nil)
        #expect(TurkishInstructions.followUp(type: .continue, modifier: .slightLeft, roundaboutExitDegrees: nil, after: 50) == nil)
        #expect(TurkishInstructions.followUp(type: .turn, modifier: .straight, roundaboutExitDegrees: nil, after: 50) == nil)
        #expect(TurkishInstructions.followUp(type: .notification, modifier: .straight, roundaboutExitDegrees: nil, after: 50) == nil)
        #expect(TurkishInstructions.followUp(type: .exitRoundabout, modifier: .right, roundaboutExitDegrees: nil, after: 30) == nil)
        #expect(TurkishInstructions.followUp(type: nil, modifier: nil, roundaboutExitDegrees: nil, after: 50) == nil)
    }

    @Test func nameChangesAndStraightOnAreNotSpoken() {
        #expect(TurkishInstructions.isSilent(type: .newName, modifier: .straight))
        #expect(TurkishInstructions.isSilent(type: .newName, modifier: .slightLeft))
        #expect(TurkishInstructions.isSilent(type: .continue, modifier: .straight))
        #expect(TurkishInstructions.isSilent(type: .continue, modifier: nil))
        #expect(TurkishInstructions.isSilent(type: .turn, modifier: .straight))
        #expect(TurkishInstructions.isSilent(type: .notification, modifier: .straight))
        #expect(TurkishInstructions.isSilent(type: .depart, modifier: nil))
        #expect(TurkishInstructions.isSilent(type: nil, modifier: nil))
        // Anything the driver has to do is spoken.
        #expect(!TurkishInstructions.isSilent(type: .turn, modifier: .left))
        #expect(!TurkishInstructions.isSilent(type: .continue, modifier: .left))
        #expect(!TurkishInstructions.isSilent(type: .continue, modifier: .slightRight))
        #expect(!TurkishInstructions.isSilent(type: .fork, modifier: .straight))
        #expect(!TurkishInstructions.isSilent(type: .offRamp, modifier: .slightRight))
        #expect(!TurkishInstructions.isSilent(type: .exitRoundabout, modifier: .right))
        #expect(!TurkishInstructions.isSilent(type: .arrive, modifier: nil))
    }

    @Test func aFerryHasItsOwnWords() {
        #expect(TurkishInstructions.action(type: .notification, modifier: .straight) == "Feribota binin")
        #expect(TurkishInstructions.action(type: .notification, modifier: .straight, leavingFerry: true) == "Feribottan inin")
        // The recorded ferry route: driving, the crossing, driving again. Counted from the current step on.
        let beforeTheFerry: [ManeuverType?] = [.turn, .notification, .notification, .turn, .arrive, nil]
        let onTheFerry: [ManeuverType?] = [.notification, .turn, .arrive, nil]
        let afterTheFerry: [ManeuverType?] = [.turn, .arrive, nil]
        #expect(!NavigationSession.isOnFerry(beforeTheFerry))
        #expect(NavigationSession.isOnFerry(onTheFerry))
        #expect(!NavigationSession.isOnFerry(afterTheFerry))
    }
}

struct BannerRoadNameTests {
    /// Banner texts and the next step's instruction as Valhalla returned them (2026-11-14).
    @Test func valhallasFallbackSentenceIsNotARoadName() {
        #expect(NavigationSession.roadName(banner: "sağa dönün.", nextInstruction: "sağa dönün.") == nil)
        #expect(NavigationSession.roadName(banner: "sağ.", nextInstruction: "sağ.") == nil)
        #expect(NavigationSession.roadName(banner: "batı yönüne doğru sürün.", nextInstruction: "batı yönüne doğru sürün.") == nil)
        #expect(NavigationSession.roadName(banner: "", nextInstruction: nil) == nil)
        // A real name differs from the sentence that mentions it.
        #expect(NavigationSession.roadName(banner: "Spor Caddesi", nextInstruction: "Spor Caddesi caddesine doğru sağa dönün.") == "Spor Caddesi")
        #expect(NavigationSession.roadName(banner: "Sirkeci - Harem", nextInstruction: "Sirkeci - Harem caddesine dönün Feribot.") == "Sirkeci - Harem")
        #expect(NavigationSession.roadName(banner: "Kennedy Caddesi", nextInstruction: nil) == "Kennedy Caddesi")
    }
}

struct AnnouncementPlannerTests {
    @Test func cityStagesOncePerStep() {
        var planner = AnnouncementPlanner()
        #expect(planner.stage(step: 5, distance: 600, speed: 0) == nil)
        #expect(planner.stage(step: 5, distance: 380, speed: 0) == .early)
        #expect(planner.stage(step: 5, distance: 300, speed: 0) == nil)
        #expect(planner.stage(step: 5, distance: 115, speed: 0) == .close)
        #expect(planner.stage(step: 5, distance: 40, speed: 0) == .now)
        #expect(planner.stage(step: 5, distance: 5, speed: 0) == nil)
        #expect(planner.stage(step: 4, distance: 350, speed: 0) == .early) // next maneuver resets
    }

    /// At the turn means 4 s ahead and never under 45 m: Ferrostar looks for the end of a step from 30 m.
    @Test func thePromptAtTheTurnLeadsTheStepAdvance() {
        var slow = AnnouncementPlanner()
        #expect(slow.stage(step: 3, distance: 46, speed: 0) == nil)
        #expect(slow.stage(step: 3, distance: 45, speed: 0) == .now)
        var fast = AnnouncementPlanner()
        #expect(fast.stage(step: 3, distance: 101, speed: 25) == nil)
        #expect(fast.stage(step: 3, distance: 100, speed: 25) == .now)
    }

    @Test func highwayAnnouncesEarlier() {
        var planner = AnnouncementPlanner()
        #expect(planner.stage(step: 9, distance: 1_000, speed: 25) == nil)
        #expect(planner.stage(step: 9, distance: 600, speed: 25) == .early)
        // At 90 km/h the close call (9 s) would be 5 s before the one at the turn (4 s): one of them is enough.
        #expect(planner.stage(step: 9, distance: 200, speed: 25) == nil)
        #expect(planner.stage(step: 9, distance: 95, speed: 25) == .now)
    }

    @Test func shortStepSkipsTheEarlyCall() {
        var planner = AnnouncementPlanner()
        #expect(planner.stage(step: 2, distance: 115, speed: 6) == .close)
        #expect(planner.stage(step: 2, distance: 300, speed: 6) == nil) // never back to a farther stage
    }

    @Test func aStageRightBeforeTheNextOneIsLeftOut() {
        var planner = AnnouncementPlanner()
        // A 154 m step: "120 metre sonra" would follow "150 metre sonra" 34 m on.
        #expect(planner.stage(step: 3, distance: 154, speed: 5) == nil)
        #expect(planner.stage(step: 3, distance: 119, speed: 5) == .close)
        #expect(planner.stage(step: 3, distance: 44, speed: 5) == .now)
        // A 49 m step: the prompt at the turn is due 4 m on, so only that one is spoken.
        #expect(planner.stage(step: 2, distance: 49, speed: 3) == nil)
        #expect(planner.stage(step: 2, distance: 44, speed: 3) == .now)
        // At 50 km/h a 200 m step keeps its advance notice: there is no close call for it to run into, and
        // the turn is 10 s away.
        var faster = AnnouncementPlanner()
        #expect(faster.stage(step: 7, distance: 200, speed: 14) == .early)
        #expect(faster.stage(step: 7, distance: 120, speed: 14) == nil)
        #expect(faster.stage(step: 7, distance: 56, speed: 14) == .now)
    }

    @Test func aDestinationWithoutASideHasNoStageAtThePoint() {
        var planner = AnnouncementPlanner()
        #expect(planner.stage(step: 1, distance: 390, speed: 0, hasNow: false) == .early)
        // Nothing follows the close call, so it is not left out however near the end is.
        #expect(planner.stage(step: 1, distance: 80, speed: 0, hasNow: false) == .close)
        #expect(planner.stage(step: 1, distance: 30, speed: 0, hasNow: false) == nil)
        #expect(planner.stage(step: 1, distance: 5, speed: 0, hasNow: false) == nil)
    }

    /// A prompt with a distance is not queued behind another sentence: it waits and is asked for again.
    @Test func aPromptWithADistanceWaitsWhileAnotherSentenceIsSpoken() {
        var planner = AnnouncementPlanner()
        #expect(planner.stage(step: 6, distance: 395, speed: 0, holdsDistance: true) == nil)
        #expect(planner.stage(step: 6, distance: 387, speed: 0, holdsDistance: true) == nil)
        #expect(planner.stage(step: 6, distance: 379, speed: 0) == .early) // the voice is free again
        // The prompt at the turn does not wait.
        #expect(planner.stage(step: 6, distance: 40, speed: 0, holdsDistance: true) == .now)
    }

    /// The session starts a new planner when Ferrostar replaces the route: a maneuver is known by the number of
    /// steps left, and the new route can have as many left as the old one.
    @Test func aReplacedRouteStartsItsStagesAgain() {
        var planner = AnnouncementPlanner()
        #expect(planner.stage(step: 6, distance: 380, speed: 0) == .early)
        #expect(planner.stage(step: 6, distance: 115, speed: 0) == .close)
        // Carried over, the new route's first maneuver (also 6 steps left) would stay silent until the turn.
        #expect(planner.stage(step: 6, distance: 390, speed: 0) == nil)
        planner = AnnouncementPlanner()
        #expect(planner.stage(step: 6, distance: 390, speed: 0) == .early)
    }
}

struct StatusThrottleTests {
    private let start = Date(timeIntervalSince1970: 1_794_000_000)

    @Test func theSameSentenceAtMostOnceInThirtySeconds() {
        var throttle = StatusThrottle()
        #expect(throttle.allows("Rotadan çıktınız.", at: start) == true)
        // Another sentence has its own clock: leaving the route and its new route are both heard.
        #expect(throttle.allows("Rota yeniden oluşturuldu.", at: start.addingTimeInterval(2)) == true)
        #expect(throttle.allows("Rotadan çıktınız.", at: start.addingTimeInterval(8)) == false)
        #expect(throttle.allows("Rota yeniden oluşturuldu.", at: start.addingTimeInterval(9)) == false)
        #expect(throttle.allows("Rotadan çıktınız.", at: start.addingTimeInterval(31)) == true)
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

    @Test func onlyTurnsAreAtTheLights() {
        #expect(TurkishInstructions.isTurn(type: .turn, modifier: .left))
        #expect(TurkishInstructions.isTurn(type: .endOfRoad, modifier: .right))
        #expect(!TurkishInstructions.isTurn(type: .roundabout, modifier: nil))
        #expect(!TurkishInstructions.isTurn(type: .offRamp, modifier: .slightRight))
        #expect(!TurkishInstructions.isTurn(type: nil, modifier: nil))
    }
}

struct RouteDeviationTests {
    @Test func leavingTheRouteAltogether() {
        let lost = RouteDeviation.deviation(kind: .completelyOffRoute(deviationFromRouteLine: 150))
        let ahead = RouteDeviation.deviation(kind: .offStepOnRoute(deviationFromStepLine: 60))
        #expect(NavigationSession.isCompletelyOffRoute(lost))
        // On a later step of the route, or on it: the banner and its distance stay.
        #expect(!NavigationSession.isCompletelyOffRoute(ahead))
        #expect(!NavigationSession.isCompletelyOffRoute(RouteDeviation.noDeviation))
        #expect(!NavigationSession.isCompletelyOffRoute(nil))
    }
}
