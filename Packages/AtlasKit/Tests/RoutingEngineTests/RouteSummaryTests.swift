import Testing
@testable import RoutingEngine

struct RouteSummaryTests {
    @Test func picksLongestRoadsInDrivingOrder() {
        let steps: [(name: String?, distance: Double)] = [
            ("Yaz Sokak", 120),
            ("Sahil Bulvarı", 6_000),
            (nil, 40),
            ("Ankara Caddesi", 2_500),
            ("Sahil Bulvarı", 1_000),
            ("Mustafa Kemal Caddesi", 900),
        ]
        #expect(RouteSummary.mainRoads(steps) == ["Sahil Bulvarı", "Ankara Caddesi"])
    }

    /// Kartal → Kartal Adliyesi as Valhalla returned it on 2026-11-14: OSM names one road both ways.
    @Test func oneRoadSpelledTwoWaysCountsOnceWithTurkishLetters() {
        let steps: [(name: String?, distance: Double)] = [
            ("İhlas Sokağı", 65),
            ("Turgut Özal Bulvarı", 2_586),
            ("Canakkale Caddesi", 1_596),
            ("Çanakkale Caddesi", 160),
            ("Anafartalar Caddesi", 878),
        ]
        #expect(RouteSummary.mainRoads(steps) == ["Turgut Özal Bulvarı", "Çanakkale Caddesi"])
    }

    @Test func ignoresUnnamedAndBlankSteps() {
        #expect(RouteSummary.mainRoads([(nil, 500), ("  ", 300)]).isEmpty)
    }
}
