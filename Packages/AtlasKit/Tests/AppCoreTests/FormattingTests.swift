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
}
