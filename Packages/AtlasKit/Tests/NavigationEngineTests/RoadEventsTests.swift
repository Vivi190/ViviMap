import CoreLocation
import Testing
@testable import NavigationEngine

/// Closures, accidents and road works on the route, said once each on the way.
struct RoadEventWatchTests {
    // East along a road from Kartal, a point every 0.01° (about 843 m), 8.4 km long.
    private let path = RoutePath((0 ... 10).map { CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2 + Double($0) * 0.01) })

    /// An event that begins `metres` along `route`, `north` metres beside it.
    private func event(_ kind: RoadEvent.Kind, at metres: Double, north: Double = 0, on route: RoutePath? = nil) -> RoadEvent {
        let point = (route ?? path).point(at: metres).coordinate
        return RoadEvent(kind: kind, coordinate: CLLocationCoordinate2D(latitude: point.latitude + north / 110_540, longitude: point.longitude))
    }

    @Test func sentencesAreBuiltFromTheKind() {
        #expect(TurkishInstructions.roadEvent(.roadworks, distance: 2000) == "2 kilometre sonra yol çalışması.")
        #expect(TurkishInstructions.roadEvent(.accident, distance: 800) == "800 metre sonra kaza.")
        #expect(TurkishInstructions.roadEvent(.closure, distance: 1000) == "1 kilometre sonra yol kapalı.")
        #expect(TurkishInstructions.roadEvent(.accident, distance: 1234) == "1,2 kilometre sonra kaza.")
    }

    @Test func anEventIsSaidOnceFromAKilometreAhead() {
        var watch = RoadEventWatch()
        watch.place([event(.closure, at: 3000)], on: path)
        // City speed (14 m/s): in range from a kilometre.
        #expect(watch.update(travelled: 1900, speed: 14) == nil)
        #expect(watch.update(travelled: 2005, speed: 14) == "1 kilometre sonra yol kapalı.")
        #expect(watch.update(travelled: 2100, speed: 14) == nil)
    }

    @Test func fasterMeansEarlier() {
        #expect(RoadEventWatch.warningDistance(speed: 14) == 1000)
        #expect(abs(RoadEventWatch.warningDistance(speed: 33.4) - 2004) < 1e-6) // 120 km/h: a minute's drive
        var watch = RoadEventWatch()
        watch.place([event(.roadworks, at: 5000)], on: path)
        #expect(watch.update(travelled: 2990, speed: 33.4) == nil)
        #expect(watch.update(travelled: 3000, speed: 33.4) == "2 kilometre sonra yol çalışması.")
    }

    /// A traffic round can find an event that is already close.
    @Test func anEventFoundLateIsSaidWithTheDistanceLeft() {
        var watch = RoadEventWatch()
        watch.place([event(.accident, at: 4000)], on: path)
        #expect(watch.update(travelled: 3200, speed: 14) == "800 metre sonra kaza.")
    }

    @Test func theNextRoundDoesNotRepeatAnEvent() {
        var watch = RoadEventWatch()
        watch.place([event(.accident, at: 4000)], on: path)
        #expect(watch.update(travelled: 3200, speed: 14) == "800 metre sonra kaza.")
        // The next round reports it again, beginning 80 m further on, and another accident 600 m after it.
        watch.place([event(.accident, at: 4080), event(.accident, at: 4680)], on: path)
        #expect(watch.update(travelled: 3300, speed: 14) == nil)
        #expect(watch.update(travelled: 3700, speed: 14) == "1 kilometre sonra kaza.")
    }

    /// The watch outlives a change of route: the session only places the events again.
    @Test func aNewRouteDoesNotRepeatAnEvent() {
        var watch = RoadEventWatch()
        let closure = event(.closure, at: 3000)
        watch.place([closure], on: path)
        #expect(watch.update(travelled: 2500, speed: 14) == "500 metre sonra yol kapalı.")
        // The new route starts 2.5 km along the old one: the closure is about 480 m from its start.
        let rerouted = RoutePath((3 ... 10).map { CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2 + Double($0) * 0.01) })
        watch.place([closure], on: rerouted)
        #expect(watch.events.count == 1)
        #expect(watch.update(travelled: 0, speed: 14) == nil)
    }

    @Test func nothingIsSaidOfAnEventBehindOrRightAtTheCar() {
        var behind = RoadEventWatch()
        behind.place([event(.accident, at: 1000)], on: path)
        #expect(behind.update(travelled: 1500, speed: 14) == nil)
        // 30 m ahead when first heard of: the driver sees it. Not said later either, were it ahead again.
        var close = RoadEventWatch()
        close.place([event(.accident, at: 2000)], on: path)
        #expect(close.update(travelled: 1970, speed: 14) == nil)
        #expect(close.update(travelled: 1500, speed: 14) == nil)
    }

    @Test func onlyEventsOnTheRouteArePlaced() {
        var watch = RoadEventWatch()
        watch.place([event(.accident, at: 2000, north: 40)], on: path) // a parallel street
        #expect(watch.events.isEmpty)
        // The provider's line lies a few metres beside the route's.
        watch.place([event(.accident, at: 2000, north: 20)], on: path)
        #expect(watch.events.count == 1)
        #expect(abs((watch.events.first?.offset ?? 0) - 2000) < 1)
    }

    @Test func twoEventsInRangeAreSaidOneAfterTheOther() {
        var watch = RoadEventWatch()
        // In driving order whatever order they are given in.
        watch.place([event(.accident, at: 2600), event(.closure, at: 2400)], on: path)
        #expect(watch.update(travelled: 2000, speed: 14) == "400 metre sonra yol kapalı.")
        #expect(watch.update(travelled: 2010, speed: 14) == "600 metre sonra kaza.")
        #expect(watch.update(travelled: 2020, speed: 14) == nil)
    }
}
