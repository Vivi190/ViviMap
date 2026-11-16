import CoreLocation
import SearchEngine
import Testing
@testable import NavigationEngine

struct StopsAlongRouteTests {
    /// About 10 km due north in steps of 0.001° (111 m); the car 10 steps in.
    private let route = (0 ... 90).map { CLLocationCoordinate2D(latitude: 40.90 + Double($0) * 0.001, longitude: 29.1) }

    /// `metres` east of the route at `latitude` (west when negative).
    private func place(_ id: String, _ name: String, at latitude: Double, east metres: Double) -> Place {
        let longitude = 29.1 + metres / (111_320 * cos(latitude * .pi / 180))
        return Place(id: id, name: name, subtitle: "", point: GeoPoint(latitude: latitude, longitude: longitude), category: "amenity=fuel")
    }

    @Test func theCheapestToTurnIntoComesFirst() throws {
        let path = RoutePath(route)
        let car = path.offsets[10]
        let opet = place("p1", "Opet", at: 40.930, east: 50)
        let bp = place("p2", "BP", at: 40.920, east: -50)
        let total = place("p3", "Total", at: 40.925, east: 200)
        let passing = place("p4", "Passing", at: 40.911, east: 30)
        let behind = place("p5", "Behind", at: 40.905, east: 30)
        let far = place("p6", "Far", at: 40.940, east: 500)
        let onTheLine = place("p7", "On the line", at: 40.950, east: 0)
        let nearLeft = place("p8", "Near left", at: 40.913, east: -40)
        let found = StopsAlongRoute.ranked([opet, bp, total, passing, behind, far, onTheLine, nearLeft], on: path, from: car)
        // Passed already (111 m ahead), behind the car, or 500 m off the road: none of them is on the way.
        // A place on the left costs a turn across the traffic: BP 1.1 km ahead after Opet 2.2 km ahead, but one
        // 330 m ahead still before Total 200 m off the road.
        #expect(found.map(\.place.name) == ["Near left", "Total", "Opet", "BP", "On the line"])
        let right = try #require(found.first(where: { $0.place.id == "p1" }))
        #expect(abs(right.ahead - 20 * 111.2) < 15)
        #expect(abs(right.offRoute - 50) < 1)
        #expect(right.side == .right)
        let left = try #require(found.first(where: { $0.place.id == "p2" }))
        #expect(left.side == .left)
        let line = try #require(found.first(where: { $0.place.id == "p7" }))
        #expect(line.side == nil)
        #expect(StopsAlongRoute.ranked([opet, bp, total, nearLeft], on: path, from: car, limit: 2).map(\.place.name) == ["Near left", "Total"])
    }

    /// The same places driven the other way: left and right swap, and so does the order.
    @Test func theSideIsTheDriversSide() {
        let back = RoutePath(Array(route.reversed()))
        let opet = place("p1", "Opet", at: 40.930, east: 50)
        let bp = place("p2", "BP", at: 40.920, east: -50)
        let found = StopsAlongRoute.ranked([opet, bp], on: back, from: back.offsets[50])
        #expect(found.map(\.place.name) == ["BP", "Opet"])
        #expect(found.map(\.side) == [PlaceAhead.Side.right, .left])
    }

    @Test func pointsToAskAboutEveryKilometreAndAHalfAhead() {
        let path = RoutePath(route)
        let points = StopsAlongRoute.points(on: path, from: path.offsets[10])
        #expect(points.count == 6)
        #expect(abs((points.first?.latitude ?? 0) - 40.91) < 1e-9)
        #expect(StopsAlongRoute.points(on: path, from: path.length).isEmpty)
        // 40 km ahead at most, however long the route.
        let long = RoutePath((0 ..< 500).map { CLLocationCoordinate2D(latitude: 40.50 + Double($0) * 0.001, longitude: 29.1) })
        #expect(StopsAlongRoute.points(on: long, from: 0).count == 27)
    }

    /// OpenStreetMap's record first: a business both indexes list is kept once, at its surveyed position.
    @Test func aPlaceBothIndexesListIsListedOnce() {
        let shell = place("offline-1", "Shell", at: 40.93, east: 0)
        let street = [shell, place("offline-2", "Opet", at: 40.95, east: 0), shell]
        let businesses = [
            place("poi-1", "Shell Kartal", at: 40.93, east: 30),
            place("poi-2", "Opet", at: 40.9527, east: 0), // 300 m from the other Opet: another station
            place("poi-3", "Petrol Ofisi", at: 40.93, east: 20),
            place("poi-4", "SHELL", at: 40.93, east: -50),
        ]
        #expect(StopsAlongRoute.merged([street, businesses]).map(\.id) == ["offline-1", "offline-2", "poi-2", "poi-3"])
        // An apostrophe joins, as people type the name.
        #expect(StopsAlongRoute.same(place("a", "McDonald's", at: 40.93, east: 0), place("b", "mcdonalds", at: 40.93, east: 10)))
        #expect(!StopsAlongRoute.same(shell, place("c", "Shell", at: 40.93, east: 150)))
    }
}
