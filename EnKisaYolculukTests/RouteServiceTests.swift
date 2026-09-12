import Foundation
import Testing
@testable import EnKisaYolculuk

@Suite("RouteService")
struct RouteServiceTests {

    @Test("A direct trip is one leg with no transfers")
    func directTrip() throws {
        let service = try Fixture.service(Fixture.linear)
        let route = try #require(service.routes(from: "a", to: "c").first)
        #expect(route.legs.count == 1)
        #expect(route.transferCount == 0)
        #expect(route.totalMinutes == 5)
        #expect(route.stopCount == 2)
        #expect(route.legs[0].stations.map(\.id) == ["a", "b", "c"])
    }

    @Test("Legs carry their own riding time, excluding the transfer penalty")
    func legMinutesExcludePenalty() throws {
        let service = try Fixture.service(Fixture.divergingCriteria)
        let route = try #require(
            service.routes(from: "p", to: "r").first { $0.criteria.contains(.fastest) }
        )
        #expect(route.legs.map(\.minutes) == [1, 1])
        // 1 + 1 riding + one 5-minute transfer.
        #expect(route.totalMinutes == 7)
    }

    @Test("The three criteria collapse to distinct routes, each keeping its labels")
    func criteriaDeduplicate() throws {
        let service = try Fixture.service(Fixture.divergingCriteria)
        let routes = try service.routes(from: "p", to: "r")
        #expect(routes.count == 2, "expected fastest to differ from the other two")
        let labels = routes.flatMap(\.criteria)
        #expect(Set(labels) == Set(RouteCriterion.allCases), "a criterion went missing")
        #expect(labels.count == RouteCriterion.allCases.count, "a criterion was duplicated")
    }

    @Test("When all three criteria agree there is a single route carrying all labels")
    func criteriaMerge() throws {
        let service = try Fixture.service(Fixture.linear)
        let routes = try service.routes(from: "a", to: "c")
        #expect(routes.count == 1)
        #expect(Set(routes[0].criteria) == Set(RouteCriterion.allCases))
    }

    /// AGENTS.md pitfall #5.
    @Test("A → B → A counts two transfers, not one")
    func aThenBThenACountsCorrectly() throws {
        let service = try Fixture.service(Fixture.aThenBThenA)
        let route = try #require(service.routes(from: "s1", to: "s4").first)
        #expect(route.legs.map(\.line.id) == ["A", "B", "A"])
        #expect(route.transferCount == 2)
        // Two distinct lines are used; the "n lines ⇒ n−1 transfers" formula
        // would have said one.
        #expect(Set(route.legs.map(\.line.id)).count == 2)
        #expect(route.totalMinutes == 3 + 10)   // 3 rides + 2 × 5 penalty
    }

    @Test("Riding a shared trunk costs no transfer")
    func sharedTrunkIsFree() throws {
        let service = try Fixture.service(Fixture.sharedTrunk)
        let route = try #require(service.routes(from: "t1", to: "t3").first)
        #expect(route.transferCount == 0)
        #expect(route.totalMinutes == 4)
    }

    @Test("Changing branches where they diverge does cost a transfer")
    func realDivergenceCosts() throws {
        let service = try Fixture.service(Fixture.sharedTrunk)
        let route = try #require(service.routes(from: "fa", to: "fb").first)
        #expect(route.transferCount == 1)
        #expect(route.totalMinutes == 2 + 10 + 2)
    }

    @Test("Legs report the terminus they are heading towards")
    func legsCarryDirection() throws {
        let service = try Fixture.service(Fixture.linear)
        let route = try #require(service.routes(from: "a", to: "b").first)
        #expect(route.legs[0].direction?.id == "c")
        #expect(route.legs[0].directionText == "C yönü")
    }

    @Test("A line with no running order reports no direction instead of guessing")
    func noDirectionOnLoop() throws {
        let service = try Fixture.service(Fixture.loopLine)
        let route = try #require(service.routes(from: "r1", to: "r2").first)
        #expect(route.legs[0].direction == nil)
        #expect(route.legs[0].directionText == nil)
    }

    // MARK: - Walks at the ends of a journey

    @Test("Starting beside the boarding station reports a leading walk")
    func leadingWalk() throws {
        let service = try Fixture.service(Fixture.complexWithWalk)
        let route = try #require(service.routes(from: "n2", to: "n4").first)
        #expect(route.origin.id == "n2", "the requested origin must be preserved")
        #expect(route.legs.first?.boarding.id == "n3", "you board after walking")
        #expect(route.leadingWalkMinutes == 15)
        #expect(route.startsWithWalk)
        #expect(route.totalMinutes == 17)   // 15 walk + 2 ride
    }

    @Test("Finishing beside the alighting station reports a trailing walk")
    func trailingWalk() throws {
        let service = try Fixture.service(Fixture.complexWithWalk)
        let route = try #require(service.routes(from: "n4", to: "n2").first)
        #expect(route.destination.id == "n2")
        #expect(route.legs.last?.alighting.id == "n3")
        #expect(route.trailingWalkMinutes == 15)
        #expect(route.endsWithWalk)
    }

    @Test("An ordinary journey has no walk at either end")
    func noWalksOnOrdinaryJourney() throws {
        let service = try Fixture.service(Fixture.linear)
        let route = try #require(service.routes(from: "a", to: "c").first)
        #expect(!route.startsWithWalk)
        #expect(!route.endsWithWalk)
        #expect(route.origin.id == "a")
        #expect(route.destination.id == "c")
    }

    // MARK: - Errors

    @Test("The same origin and destination is rejected")
    func sameEndpoints() throws {
        let service = try Fixture.service(Fixture.linear)
        #expect(throws: RouteService.RoutingError.self) {
            _ = try service.routes(from: "a", to: "a")
        }
    }

    @Test("An unknown station is rejected, naming the id")
    func unknownStation() throws {
        let service = try Fixture.service(Fixture.linear)
        do {
            _ = try service.routes(from: "a", to: "ghost")
            Issue.record("expected a routing error")
        } catch let error as RouteService.RoutingError {
            guard case .unknownStation("ghost") = error else {
                Issue.record("wrong error: \(error)")
                return
            }
            #expect(error.errorDescription?.contains("ghost") == true)
        }
    }

    @Test("An unreachable destination is reported, not returned empty")
    func unreachableDestination() throws {
        let service = try Fixture.service(Fixture.disconnected)
        do {
            _ = try service.routes(from: "i1", to: "j2")
            Issue.record("expected a routing error")
        } catch let error as RouteService.RoutingError {
            guard case .noRouteFound = error else {
                Issue.record("wrong error: \(error)")
                return
            }
        }
    }

    @Test("Every routing error carries a user-facing message")
    func errorsHaveMessages() throws {
        let station = Station(id: "x", name: "X")
        let errors: [RouteService.RoutingError] = [
            .sameOriginAndDestination,
            .unknownStation("x"),
            .stationNotOnAnyLine(station),
            .noRouteFound(from: station, to: station),
        ]
        for error in errors {
            #expect(error.errorDescription?.isEmpty == false)
        }
    }

    // MARK: - Invariants across all fixtures

    @Test("Reported totals always match the legs they are built from")
    func totalsAreSelfConsistent() throws {
        for json in [Fixture.linear, Fixture.penaltyTrap, Fixture.aThenBThenA,
                     Fixture.divergingCriteria, Fixture.sharedTrunk,
                     Fixture.complexWithWalk] {
            let network = try Fixture.network(json)
            let service = RouteService(network: network)
            for origin in network.stations {
                for destination in network.stations where origin.id != destination.id {
                    guard let routes = try? service.routes(from: origin.id, to: destination.id)
                    else { continue }
                    for route in routes {
                        #expect(route.stopCount == route.legs.reduce(0) { $0 + $1.stopCount })
                        #expect(route.transferCount == route.legs.count - 1)
                        #expect(route.totalMinutes >= route.legs.reduce(0) { $0 + $1.minutes })
                        #expect(route.legs.allSatisfy { $0.stations.count >= 2 })
                        #expect(!route.criteria.isEmpty)
                        #expect(route.legs.first?.boarding.id == route.origin.id
                                || route.startsWithWalk)
                        #expect(route.legs.last?.alighting.id == route.destination.id
                                || route.endsWithWalk)
                    }
                }
            }
        }
    }

    @Test("Routes are symmetric: reversing a trip costs the same")
    func routesAreSymmetric() throws {
        for json in [Fixture.linear, Fixture.penaltyTrap, Fixture.divergingCriteria,
                     Fixture.sharedTrunk] {
            let network = try Fixture.network(json)
            let service = RouteService(network: network)
            for origin in network.stations {
                for destination in network.stations where origin.id != destination.id {
                    guard
                        let there = try? service.routes(from: origin.id, to: destination.id).first,
                        let back = try? service.routes(from: destination.id, to: origin.id).first
                    else { continue }
                    #expect(there.totalMinutes == back.totalMinutes,
                            "\(origin.id) ⇄ \(destination.id)")
                    #expect(there.stopCount == back.stopCount)
                }
            }
        }
    }

    @Test("Route summary reads as a sentence")
    func summaryText() throws {
        let service = try Fixture.service(Fixture.linear)
        let route = try #require(service.routes(from: "a", to: "c").first)
        #expect(route.summary == "5 dakika, 0 aktarma")
        #expect(route.totalMinutesText == "5")
    }
}
