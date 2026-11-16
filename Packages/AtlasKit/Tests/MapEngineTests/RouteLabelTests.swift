import CoreLocation
import Testing
@testable import MapEngine

struct RouteLabelTests {
    /// Metres east and north of a point in Kartal.
    private func at(_ east: Double, _ north: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: 40.9 + north / 110_540,
            longitude: 29.2 + east / (111_320 * cos(40.9 * .pi / 180))
        )
    }

    private func same(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D) -> Bool {
        guard let a else { return false }
        return abs(a.latitude - b.latitude) < 1e-9 && abs(a.longitude - b.longitude) < 1e-9
    }

    /// Straight north 2 km, and a detour bulging 1 km east between the same ends.
    private var straight: [CLLocationCoordinate2D] { [at(0, 0), at(0, 500), at(0, 1_000), at(0, 1_500), at(0, 2_000)] }
    private var detour: [CLLocationCoordinate2D] { [at(0, 0), at(600, 500), at(1_000, 1_000), at(600, 1_500), at(0, 2_000)] }

    @Test func eachBubbleSitsWhereOnlyItsRouteGoes() {
        #expect(same(RouteLabel.place(on: detour, awayFrom: [straight]), at(1_000, 1_000)))
        #expect(same(RouteLabel.place(on: straight, awayFrom: [detour]), at(0, 1_000)))
    }

    @Test func aLoneRouteGetsItsMiddle() {
        #expect(same(RouteLabel.place(on: straight, awayFrom: []), at(0, 1_000)))
        #expect(RouteLabel.place(on: [], awayFrom: [straight]) == nil)
    }

    @Test func samplingKeepsBothEnds() {
        let line = (0..<1_000).map { at(0, Double($0)) }
        let points = RouteLabel.sample(line, to: 80)
        #expect(points.count <= 81)
        #expect(same(points.first, line[0]) && same(points.last, line[999]))
    }

    @Test func calloutsGrowWithTheirText() {
        let here = CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2)
        let delta = RouteLabel.bubble(RouteLabel(route: 1, coordinate: here, text: "+2 dk", tone: .slower), night: false)
        let longer = RouteLabel.bubble(RouteLabel(route: 2, coordinate: here, text: "+1 sa 25 dk", tone: .slower), night: true)
        let chosen = RouteLabel.bubble(RouteLabel(route: 0, coordinate: here, text: "16 dk", detail: "6,2 km", tone: .selected), night: false)
        #expect(longer.size.width > delta.size.width)
        #expect(longer.size.height == delta.size.height)
        // The chosen route's callout carries a second line.
        #expect(chosen.size.height > delta.size.height)
    }
}

struct GuidanceAnchorTests {
    /// MapLibre pins the tracked position to the centre of the area inside the content inset; the arrow drawn
    /// for the car has to sit on the same point.
    @Test func theCarSitsLowInPortraitAndRightOfThePanelsInLandscape() {
        let portrait = AtlasMapView.guidanceAnchor(in: CGSize(width: 393, height: 852))
        #expect(abs(portrait.x - 196.5) < 0.01)
        #expect(abs(portrait.y - 852 * 0.7) < 0.01)
        let landscape = AtlasMapView.guidanceAnchor(in: CGSize(width: 852, height: 393))
        #expect(abs(landscape.x - 617.7) < 0.01)
        #expect(abs(landscape.y - 393 * 0.65) < 0.01)
    }
}

struct TrafficOverlayTests {
    private let a = CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2)
    private let b = CLLocationCoordinate2D(latitude: 40.91, longitude: 29.21)

    /// The overlay is asked on every map update; it must touch the map only when the picture changed, and a
    /// refresh that moved one colour along the same roads is such a change.
    @Test func theMapIsRedrawnOnlyWhenTheTrafficChanged() {
        let flowing = [TrafficLine(level: .free, coordinates: [a, b]), TrafficLine(level: .free, coordinates: [b, a])]
        let jammed = [TrafficLine(level: .free, coordinates: [a, b]), TrafficLine(level: .heavy, coordinates: [b, a])]
        #expect(TrafficOverlay.signature(of: flowing) == TrafficOverlay.signature(of: flowing))
        #expect(TrafficOverlay.signature(of: flowing) != TrafficOverlay.signature(of: jammed))
        #expect(TrafficOverlay.signature(of: []) != TrafficOverlay.signature(of: flowing))
    }

    @Test func everyLevelHasItsOwnColourDayAndNight() {
        for night in [false, true] {
            let colours = Set(TrafficLine.Level.allCases.map { TrafficOverlay.color($0, night: night).description })
            #expect(colours.count == TrafficLine.Level.allCases.count)
        }
    }
}

struct MapPlaceTests {
    private let here = CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2)

    @Test func aBadgeIsKnownByTheNameItsLabelShows() {
        let station = MapPlace(attributes: ["name": "Kartal Train Station", "name:tr": "Kartal Tren İstasyonu", "class": "railway"], coordinate: here)
        #expect(station?.name == "Kartal Tren İstasyonu")
        #expect(station?.coordinate.latitude == 40.9)
        #expect(MapPlace(attributes: ["name": "BP", "class": "fuel"], coordinate: here)?.name == "BP")
        // Without a name there is nothing to open a card with.
        #expect(MapPlace(attributes: ["class": "shop"], coordinate: here) == nil)
        #expect(MapPlace(attributes: ["name": ""], coordinate: here) == nil)
    }
}
