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

    @Test func ignoresUnnamedAndBlankSteps() {
        #expect(RouteSummary.mainRoads([(nil, 500), ("  ", 300)]).isEmpty)
    }
}
