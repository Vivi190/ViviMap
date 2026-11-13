import CoreLocation
import Foundation
import Testing
@testable import NavigationEngine
@testable import RoadHazards

struct RouteHazardsTests {
    // East along a street from Kartal, ~85 m per point, 850 m long.
    private let path = RoutePath((0 ... 10).map { CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2 + Double($0) * 0.001) })

    @Test func projectionGivesTheDistanceAlongTheRoute() throws {
        let hit = try #require(path.project(CLLocationCoordinate2D(latitude: 40.90005, longitude: 29.2025), tolerance: 10))
        #expect(abs(hit.offset - path.offsets[2] - (path.offsets[3] - path.offsets[2]) / 2) < 1)
        #expect(abs(hit.course - 90) < 0.5)
        #expect(path.project(CLLocationCoordinate2D(latitude: 40.9003, longitude: 29.2025), tolerance: 10) == nil) // ~33 m away
    }

    @Test func onlyHazardsTheRoutePasses() {
        let hazards = [
            Hazard(kind: .bump, latitude: 40.9, longitude: 29.205), // on the road
            Hazard(kind: .bump, latitude: 40.9002, longitude: 29.206), // ~22 m off: a side street
            Hazard(kind: .camera, latitude: 40.90012, longitude: 29.203, maxspeed: 50), // beside the road, both ways
            Hazard(kind: .camera, latitude: 40.9001, longitude: 29.207, direction: 270), // watches westbound traffic
            Hazard(kind: .camera, latitude: 40.9001, longitude: 29.208, direction: 95), // watches us
            Hazard(kind: .bump, latitude: 41.2, longitude: 28.9), // elsewhere in Istanbul
        ]
        let found = RouteHazards.along(path, hazards: hazards)
        #expect(found.map(\.hazard.kind) == [.camera, .bump, .camera])
        #expect(found.map(\.hazard.longitude) == [29.203, 29.205, 29.208])
        #expect(found.map(\.offset) == found.map(\.offset).sorted())
    }
}

struct HazardWatchTests {
    private func hazard(_ kind: Hazard.Kind, at offset: Double, limit: Int? = nil) -> RouteHazard {
        RouteHazard(hazard: Hazard(kind: kind, latitude: 0, longitude: 0, maxspeed: limit), offset: offset)
    }

    @Test func warnsOnceEarlyEnoughThenMovesOn() {
        var watch = HazardWatch(hazards: [hazard(.camera, at: 1000, limit: 50), hazard(.bump, at: 1200)])
        // City speed (14 m/s): camera range is 300 m.
        #expect(watch.update(travelled: 600, speed: 14).alert == nil)
        let first = watch.update(travelled: 710, speed: 14)
        #expect(first.alert == HazardAlert(kind: .camera, distance: 290, maxspeed: 50))
        // Spoken rounded like a road sign (50 m steps above 200 m); the chip shows the exact 290 m.
        #expect(first.sentence == "300 metre sonra hız kamerası, hız sınırı 50.")
        #expect(watch.update(travelled: 800, speed: 14).sentence == nil) // said once
        // Past the camera the bump is next, but only in range from 80 m (14 m/s × 6 s = 84 m).
        #expect(watch.update(travelled: 1010, speed: 14).alert == nil)
        #expect(watch.update(travelled: 1120, speed: 14).sentence == "80 metre sonra kasis.")
    }

    @Test func fasterMeansEarlier() {
        #expect(HazardWatch.warningDistance(.camera, speed: 25) == 375) // 90 km/h
        #expect(HazardWatch.warningDistance(.bump, speed: 5) == 80)
    }

    @Test func switchedOffKindsStayQuiet() {
        var watch = HazardWatch(hazards: [hazard(.bump, at: 100)])
        watch.kinds = [.camera]
        #expect(watch.update(travelled: 50, speed: 10).alert == nil)
    }

    @Test func rightAtTheHazard() {
        #expect(HazardWatch.sentence(HazardAlert(kind: .bump, distance: 10, maxspeed: nil)) == "Kasis.")
        #expect(HazardWatch.sentence(HazardAlert(kind: .camera, distance: 0, maxspeed: nil)) == "Hız kamerası.")
    }
}

@MainActor
struct UserHazardStoreTests {
    @Test func marksPersistAndReplaceTheSameSpot() {
        let defaults = UserDefaults(suiteName: "atlas.test.\(UUID())")!
        let store = UserHazardStore(defaults: defaults)
        store.mark(.camera, latitude: 40.9, longitude: 29.2)
        store.mark(.bump, latitude: 40.90003, longitude: 29.20004) // same spot (~5 m): replaces, no double warning
        store.mark(.camera, latitude: 40.91, longitude: 29.21)
        #expect(store.hazards.map(\.kind) == [.bump, .camera])
        let reopened = UserHazardStore(defaults: defaults)
        #expect(reopened.hazards == store.hazards)
        reopened.remove(atOffsets: IndexSet(integer: 0))
        #expect(reopened.hazards.map(\.latitude) == [40.91])
    }
}

struct HazardCatalogTests {
    @Test func shippedDataLoads() throws {
        let catalog = try #require(HazardCatalog.bundled())
        #expect(catalog.hazards.contains { $0.kind == .camera })
        #expect(catalog.hazards.contains { $0.kind == .bump })
        #expect(catalog.fetched.count == 10) // YYYY-MM-DD
    }

    @Test func decodesTheToolsFormat() throws {
        let json = #"{"fetched":"2026-11-14","hazards":[{"k":"camera","lat":41.0,"lon":29.0,"maxspeed":70,"dir":90.0},{"k":"bump","lat":40.9,"lon":29.2}]}"#
        let catalog = try HazardCatalog.decode(Data(json.utf8))
        #expect(catalog.hazards == [
            Hazard(kind: .camera, latitude: 41.0, longitude: 29.0, maxspeed: 70, direction: 90),
            Hazard(kind: .bump, latitude: 40.9, longitude: 29.2),
        ])
    }
}
