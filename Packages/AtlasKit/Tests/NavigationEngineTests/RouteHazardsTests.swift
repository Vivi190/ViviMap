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

    /// A camera's mapped direction is where it looks, so it faces the traffic it watches.
    @Test func onlyHazardsTheRoutePasses() {
        let hazards = [
            Hazard(kind: .bump, latitude: 40.9, longitude: 29.205), // on the road
            Hazard(kind: .bump, latitude: 40.9002, longitude: 29.206), // ~22 m off: a side street
            Hazard(kind: .camera, latitude: 40.90012, longitude: 29.203, maxspeed: 50), // beside the road, no direction mapped
            Hazard(kind: .camera, latitude: 40.9001, longitude: 29.207, direction: 270), // looks west, at us driving east
            Hazard(kind: .camera, latitude: 40.9001, longitude: 29.208, direction: 95), // looks our way: watches the oncoming carriageway
            Hazard(kind: .bump, latitude: 41.2, longitude: 28.9), // elsewhere in Istanbul
        ]
        let found = RouteHazards.along(path, hazards: hazards)
        #expect(found.map(\.hazard.kind) == [.camera, .bump, .camera])
        #expect(found.map(\.hazard.longitude) == [29.203, 29.205, 29.207])
        #expect(found.map(\.offset) == found.map(\.offset).sorted())
    }

    /// Only a camera looking within 60° of the car's own course is left out.
    @Test func aCameraIsDroppedOnlyWhenItLooksTheWayTheCarDrives() {
        // The route runs east (90°). 160° and 0° look across the road rather than along it.
        let directions: [Double?] = [90, 45, 140, 160, 0, 292, nil]
        let kept: [Bool] = directions.map { direction in
            let camera = Hazard(kind: .camera, latitude: 40.9001, longitude: 29.204, direction: direction)
            return !RouteHazards.along(path, hazards: [camera]).isEmpty
        }
        #expect(kept == [false, false, false, true, true, true, true])
    }

    @Test func neighboursOfOneKindCountOnce() {
        let hazards = [
            Hazard(kind: .bump, latitude: 40.9, longitude: 29.2020),
            Hazard(kind: .bump, latitude: 40.9, longitude: 29.2023), // ~25 m on: the same run of bumps
            Hazard(kind: .bump, latitude: 40.9, longitude: 29.2026), // ~25 m after that one, 50 m after the first
            Hazard(kind: .camera, latitude: 40.9, longitude: 29.2024), // another kind keeps its own warning
            Hazard(kind: .bump, latitude: 40.9, longitude: 29.2060), // ~285 m further: a new warning
        ]
        let found = RouteHazards.along(path, hazards: hazards)
        #expect(found.map(\.hazard.longitude) == [29.2020, 29.2024, 29.2060])
        #expect(found.map(\.hazard.kind) == [.bump, .camera, .bump])
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

    /// Each kind has its own next hazard: looking only at the nearest one, the bump kept the camera behind it
    /// (in range from 300 m) unannounced until the bump was passed.
    @Test func aBumpDoesNotHideTheCameraBehindIt() {
        var watch = HazardWatch(hazards: [hazard(.bump, at: 1000), hazard(.camera, at: 1050, limit: 50)])
        #expect(watch.update(travelled: 700, speed: 14).alert == nil)
        let first = watch.update(travelled: 760, speed: 14)
        #expect(first.alert == HazardAlert(kind: .camera, distance: 290, maxspeed: 50))
        #expect(first.sentence == "300 metre sonra hız kamerası, hız sınırı 50.")
        // Both in range: the chip shows the nearer one, and the bump gets its own sentence.
        let second = watch.update(travelled: 925, speed: 14)
        #expect(second.alert == HazardAlert(kind: .bump, distance: 75, maxspeed: nil))
        #expect(second.sentence == "80 metre sonra kasis.")
        // Past the bump the camera is shown again, and not announced again.
        let third = watch.update(travelled: 1010, speed: 14)
        #expect(third.alert == HazardAlert(kind: .camera, distance: 40, maxspeed: 50))
        #expect(third.sentence == nil)
    }

    /// The watch outlives a change of route: the session only replaces its hazards.
    @Test func aNewRouteDoesNotRepeatAWarning() {
        let camera = Hazard(kind: .camera, latitude: 41.0, longitude: 29.0, maxspeed: 50)
        var watch = HazardWatch(hazards: [RouteHazard(hazard: camera, offset: 1000)])
        #expect(watch.update(travelled: 750, speed: 14).sentence == "250 metre sonra hız kamerası, hız sınırı 50.")
        // The new route starts at the car: the same camera is now 200 m from its start.
        watch.hazards = [RouteHazard(hazard: camera, offset: 200)]
        let after = watch.update(travelled: 0, speed: 14)
        #expect(after.alert == HazardAlert(kind: .camera, distance: 200, maxspeed: 50))
        #expect(after.sentence == nil)
        // Another camera on the new route is announced as usual.
        let other = Hazard(kind: .camera, latitude: 41.01, longitude: 29.0)
        watch.hazards.append(RouteHazard(hazard: other, offset: 600))
        #expect(watch.update(travelled: 310, speed: 14).sentence == "300 metre sonra hız kamerası.")
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
struct SpeedLimitTests {
    // Annotation shapes as FOSSGIS Valhalla returned them on a Kartal route (2026-11-14): 50 and 110 km/h
    // where OSM has maxspeed, {"unknown":true} on 88 of 180 segments.
    @Test func onlyMappedLimitsBecomeASign() {
        #expect(NavigationSession.speedLimit(fromAnnotation: #"{"maxspeed":{"speed":50,"unit":"km/h"},"speed":13.9,"distance":21.3,"duration":1.5}"#) == 50)
        #expect(NavigationSession.speedLimit(fromAnnotation: #"{"maxspeed":{"speed":110,"unit":"km/h"}}"#) == 110)
        #expect(NavigationSession.speedLimit(fromAnnotation: #"{"maxspeed":{"unknown":true},"speed":8.0}"#) == nil)
        #expect(NavigationSession.speedLimit(fromAnnotation: #"{"maxspeed":{"none":true}}"#) == nil) // no limit is not a sign
        #expect(NavigationSession.speedLimit(fromAnnotation: #"{"speed":8.0}"#) == nil)
        #expect(NavigationSession.speedLimit(fromAnnotation: nil) == nil)
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

struct TrafficSignalsTests {
    @Test func readsPairsAndSkipsMalformedOnes() throws {
        let json = #"{"source":"x","fetched":"2026-11-15","count":3,"points":[[40.88925,29.18712],[41.0],[40.9,29.2]]}"#
        let points = try TrafficSignals.decode(Data(json.utf8))
        #expect(points.count == 2)
        #expect(points[0].latitude == 40.88925 && points[0].longitude == 29.18712)
    }

    @Test func theShippedFileHasIstanbulsLights() {
        // 4 118 nodes on 2026-11-15; refreshed with Tools/hazards/fetch_signals.py.
        #expect(TrafficSignals.bundled.count > 3_000)
        #expect(TrafficSignals.bundled.allSatisfy { (40.75 ... 41.6).contains($0.latitude) && (28.0 ... 29.95).contains($0.longitude) })
    }
}
