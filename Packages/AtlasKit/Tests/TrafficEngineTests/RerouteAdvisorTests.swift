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

    /// The street shifted north: 0.002° is two blocks away (about 220 m), 0.00005° the same road (about 5.5 m).
    private func shifted(_ line: [CLLocationCoordinate2D], north degrees: Double) -> [CLLocationCoordinate2D] {
        line.map { CLLocationCoordinate2D(latitude: $0.latitude + degrees, longitude: $0.longitude) }
    }

    /// The first `shared` points of the street, then north: 11 points in all, so 6 shared are 55 % of it and
    /// 9 are 82 %, both another route than the street itself.
    private func detour(sharing shared: Int) -> [CLLocationCoordinate2D] {
        let turn = street[shared - 1].longitude
        return Array(street.prefix(shared)) + (1 ... 11 - shared).map { CLLocationCoordinate2D(latitude: 40.9 + Double($0) * 0.001, longitude: turn) }
    }

    @Test func anExtraCandidateIsOfferedOnlyOnAnotherRoad() {
        let parallel = shifted(street, north: 0.002)
        // The router's one route and a local-streets route along the same road: one tile.
        #expect(RouteOverlap.choice(of: [street, shifted(street, north: 0.00005)], own: 1) == [0])
        #expect(RouteOverlap.choice(of: [street, parallel], own: 1) == [0, 1])
        // Like one of the router's alternates is like any of its routes.
        #expect(RouteOverlap.choice(of: [street, parallel, shifted(parallel, north: 0.00005)], own: 2) == [0, 1])
        #expect(RouteOverlap.choice(of: [street, detour(sharing: 6), parallel], own: 2) == [0, 1, 2])
        // The router's own routes are not judged against each other: they stay as before.
        #expect(RouteOverlap.choice(of: [street, shifted(street, north: 0.00005)], own: 2) == [0, 1])
    }

    @Test func ofFourCandidatesTheFirstAndTheTwoMostDifferentStay() {
        let mostly = detour(sharing: 9), half = detour(sharing: 6), parallel = shifted(street, north: 0.002)
        #expect(abs(RouteOverlap.share(of: mostly, along: street) - 9.0 / 11) < 1e-9)
        #expect(abs(RouteOverlap.share(of: half, along: street) - 6.0 / 11) < 1e-9)
        // The router's first, then the parallel road (nothing shared), then the detour that shares less; in
        // the order they came in, so the router's order is kept.
        #expect(RouteOverlap.choice(of: [street, mostly, half, parallel], own: 3) == [0, 2, 3])
        #expect(RouteOverlap.choice(of: [street, half, mostly, parallel], own: 3) == [0, 1, 3])
        #expect(RouteOverlap.choice(of: [street, mostly, half, parallel], own: 4) == [0, 2, 3])
        #expect(RouteOverlap.choice(of: [street, mostly, half, parallel], own: 3, limit: 2) == [0, 3])
        // An extra candidate along the first route's road changes nothing: the router's three stay.
        #expect(RouteOverlap.choice(of: [street, mostly, half, shifted(street, north: 0.00005)], own: 3) == [0, 1, 2])
    }

    @Test func choiceOfNothingOrOne() {
        #expect(RouteOverlap.choice(of: [], own: 0) == [])
        #expect(RouteOverlap.choice(of: [street], own: 1) == [0])
        #expect(RouteOverlap.choice(of: [street], own: 0) == [0])
        #expect(RouteOverlap.choice(of: [street, shifted(street, north: 0.002)], own: 5) == [0, 1])
    }

    @Test func aCandidateThroughAClosedStretchIsReplacedByAnotherRoad() {
        // The street is closed between its fifth and seventh point.
        let closed = [29.2045, 29.2055].map { CLLocationCoordinate2D(latitude: 40.9, longitude: $0) }
        let half = detour(sharing: 4), parallel = shifted(street, north: 0.002)
        // The first of the router's new routes that keeps off the stretch...
        #expect(RouteOverlap.replacement(among: [street, half, parallel], besides: [], avoiding: closed) == 1)
        // ...and is another road than the tiles beside it.
        #expect(RouteOverlap.replacement(among: [street, half, parallel], besides: [half], avoiding: closed) == 2)
        #expect(RouteOverlap.replacement(among: [half], besides: [half], avoiding: closed) == nil)
        // 2 m beside the points is the very road; 5.5 m beside is the other carriageway.
        #expect(RouteOverlap.replacement(among: [street, shifted(street, north: 0.00002)], besides: [], avoiding: closed) == nil)
        #expect(RouteOverlap.replacement(among: [street, shifted(street, north: 0.00005)], besides: [], avoiding: closed) == 1)
        // One that leaves the stretch half way keeps off part of it: better than driving all of it.
        let leaving = Array(street.prefix(6)) + (1 ... 5).map { CLLocationCoordinate2D(latitude: 40.9 + Double($0) * 0.001, longitude: 29.205) }
        #expect(RouteOverlap.replacement(among: [leaving], besides: [], avoiding: closed) == 0)
        #expect(RouteOverlap.replacement(among: [], besides: [], avoiding: closed) == nil)
    }

    @Test func distanceToSegment() {
        let a = CLLocationCoordinate2D(latitude: 40.9, longitude: 29.2)
        let b = CLLocationCoordinate2D(latitude: 40.9, longitude: 29.21)
        let above = CLLocationCoordinate2D(latitude: 40.9001, longitude: 29.205) // ~11 m north of the middle
        #expect(abs(RouteOverlap.distance(above, a, b) - 11.05) < 0.5)
        #expect(abs(RouteOverlap.distance(a, a, b)) < 0.001)
    }
}
