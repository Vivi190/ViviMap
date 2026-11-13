import CoreLocation
import Testing
@testable import TrafficEngine

struct RerouteAdvisorTests {
    private let advisor = RerouteAdvisor()
    private func alt(_ index: Int, _ minutes: Double) -> RerouteAdvisor.Candidate {
        .init(index: index, duration: minutes * 60)
    }

    @Test func suggestsAClearGain() {
        // 30 min now, 24 min elsewhere: 6 min ≥ max(3 min, 4.5 min).
        let pick = advisor.suggestion(current: 30 * 60, alternatives: [alt(1, 27), alt(2, 24)], distanceToManeuver: 800, sinceLastChange: 600)
        #expect(pick == alt(2, 24))
    }

    @Test func smallGainsAreNotWorthARouteChange() {
        // 3.5 min saved on a 40 min trip is below 15 % (6 min).
        #expect(advisor.suggestion(current: 40 * 60, alternatives: [alt(1, 36.5)], distanceToManeuver: 800, sinceLastChange: 600) == nil)
        // On a short trip the 3 min floor applies: 2 min saved out of 10 is 20 % but under 3 min.
        #expect(advisor.suggestion(current: 10 * 60, alternatives: [alt(1, 8)], distanceToManeuver: 800, sinceLastChange: 600) == nil)
    }

    @Test func staysQuietBeforeATurnAndDuringCooldown() {
        #expect(advisor.suggestion(current: 30 * 60, alternatives: [alt(1, 20)], distanceToManeuver: 250, sinceLastChange: 600) == nil)
        #expect(advisor.suggestion(current: 30 * 60, alternatives: [alt(1, 20)], distanceToManeuver: 800, sinceLastChange: 120) == nil)
        #expect(advisor.suggestion(current: 30 * 60, alternatives: [], distanceToManeuver: nil, sinceLastChange: 600) == nil)
    }
}

struct RouteOverlapTests {
    // A straight street east from Kartal, points every ~85 m.
    private let street = (0 ... 10).map { CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2 + Double($0) * 0.001) }

    @Test func sameLineOverlapsFully() {
        #expect(RouteOverlap.share(of: street, along: street) == 1)
    }

    @Test func parallelStreetTwoBlocksAwayDoesNotOverlap() {
        let parallel = street.map { CLLocationCoordinate2D(latitude: $0.latitude + 0.002, longitude: $0.longitude) } // ~220 m north
        #expect(RouteOverlap.share(of: parallel, along: street) == 0)
    }

    @Test func detourCountsOnlyItsSharedPart() {
        let detour = Array(street.prefix(6)) + (1 ... 4).map { CLLocationCoordinate2D(latitude: 40.9 + Double($0) * 0.001, longitude: 29.205) }
        let share = RouteOverlap.share(of: detour, along: street)
        #expect(share == 0.6)
        #expect(share < RouteOverlap.sameRoute)
    }

    @Test func distanceToSegment() {
        let a = CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2)
        let b = CLLocationCoordinate2D(latitude: 40.9, longitude: 29.21)
        let above = CLLocationCoordinate2D(latitude: 40.9001, longitude: 29.205) // ~11 m north of the middle
        #expect(abs(RouteOverlap.distance(above, a, b) - 11.05) < 0.5)
        #expect(abs(RouteOverlap.distance(a, a, b)) < 0.001)
    }
}
