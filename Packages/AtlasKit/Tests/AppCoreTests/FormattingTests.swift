import Testing
@testable import AppCore

struct FormattingTests {
    @Test(arguments: [
        (4.0, "10 m"),
        (346.0, "350 m"),
        (949.0, "950 m"),
        (1_234.0, "1,2 km"),
        (9_960.0, "10,0 km"),
        (18_400.0, "18 km"),
    ])
    func distance(meters: Double, expected: String) {
        #expect(Formatting.distance(meters: meters) == expected)
    }

    @Test(arguments: [
        (10.0, "1 dk"),
        (1_610.0, "27 dk"),
        (3_600.0, "1 sa"),
        (4_330.0, "1 sa 12 dk"),
    ])
    func duration(seconds: Double, expected: String) {
        #expect(Formatting.duration(seconds: seconds) == expected)
    }
}
