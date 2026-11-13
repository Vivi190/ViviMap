import Testing
@testable import LocationEngine

struct LocationQualityTests {
    @Test(arguments: [
        (5.0, 1.0, LocationQuality.good),
        (20.0, 1.0, LocationQuality.fair),
        (80.0, 1.0, LocationQuality.poor),
        (-1.0, 1.0, LocationQuality.unavailable),
        (5.0, 30.0, LocationQuality.unavailable),
    ])
    func classifies(accuracy: Double, age: Double, expected: LocationQuality) {
        #expect(LocationQuality(horizontalAccuracy: accuracy, age: age) == expected)
    }
}
