import Foundation
import Testing
@testable import AppCore

struct SolarTests {
    private let istanbul = (lat: 41.0082, lon: 28.9784)

    private func date(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test func summerSolarNoonMatchesGeometry() throws {
        // Solar noon in Istanbul on the June solstice is ≈10:05 UTC; expected elevation 90 − 41.0 + 23.44 ≈ 72.4°.
        let elevation = Solar.elevation(at: try date("2026-06-21T10:05:00Z"), latitude: istanbul.lat, longitude: istanbul.lon)
        #expect(abs(elevation - 72.4) < 1.0)
    }

    @Test func dayAndNightAroundWinterSunset() throws {
        // Turkey stays on UTC+3 all year, so sunset in Istanbul on 21 Dec is ≈17:42 local (14:42 UTC).
        #expect(Solar.isNight(at: try date("2026-12-21T10:00:00Z"), latitude: istanbul.lat, longitude: istanbul.lon) == false)
        #expect(Solar.isNight(at: try date("2026-12-21T15:00:00Z"), latitude: istanbul.lat, longitude: istanbul.lon))
        #expect(Solar.isNight(at: try date("2026-06-21T21:00:00Z"), latitude: istanbul.lat, longitude: istanbul.lon))
    }

    @Test func forcedModesIgnoreTheSun() throws {
        let noon = try date("2026-06-21T10:05:00Z")
        #expect(AppearanceMode.night.isNight(at: noon, latitude: istanbul.lat, longitude: istanbul.lon))
        #expect(AppearanceMode.day.isNight(at: noon, latitude: istanbul.lat, longitude: istanbul.lon) == false)
        #expect(AppearanceMode.automatic.isNight(at: noon, latitude: istanbul.lat, longitude: istanbul.lon) == false)
    }
}
