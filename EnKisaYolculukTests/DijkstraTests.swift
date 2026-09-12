import Foundation
import Testing
@testable import EnKisaYolculuk

@Suite("Dijkstra")
struct DijkstraTests {

    private func shortest(
        _ json: String,
        _ from: StationID,
        _ to: StationID,
        _ criterion: RouteCriterion = .fastest
    ) throws -> (graph: LineExpandedGraph, result: Dijkstra.Result?) {
        let graph = try Fixture.graph(json)
        let result = Dijkstra.shortestPath(
            in: graph,
            from: graph.platforms(at: from),
            to: Set(graph.platforms(at: to)),
            criterion: criterion
        )
        return (graph, result)
    }

    @Test("A straight run sums its segments")
    func straightRun() throws {
        let (_, result) = try shortest(Fixture.linear, "a", "c")
        let found = try #require(result)
        #expect(found.cost.minutes == 5)
        #expect(found.cost.stops == 2)
        #expect(found.cost.transfers == 0)
    }

    @Test("The path is returned origin-first")
    func pathOrder() throws {
        let (graph, result) = try shortest(Fixture.linear, "a", "c")
        let found = try #require(result)
        #expect(found.path.map { graph.node(at: $0).station } == ["a", "b", "c"])
    }

    /// The whole reason the graph is line-expanded (CONTEXT §4.1).
    @Test("The transfer penalty is inside the search, so it changes the path chosen")
    func penaltyIsInsideTheSearch() throws {
        let (graph, result) = try shortest(Fixture.penaltyTrap, "s", "t")
        let found = try #require(result)
        let lines = found.path.map { graph.node(at: $0).line }

        // Riding P1…P4 takes only 4 minutes but needs three transfers.
        // If the penalty were applied after the search, that path would win.
        #expect(lines.allSatisfy { $0 == "D" }, "took the many-transfer path: \(lines)")
        #expect(found.cost.minutes == 20)
        #expect(found.cost.transfers == 0)
    }

    @Test("fewestTransfers and fastest can legitimately disagree")
    func criteriaDisagree() throws {
        let (_, fastest) = try shortest(Fixture.divergingCriteria, "p", "r", .fastest)
        let (_, fewest) = try shortest(Fixture.divergingCriteria, "p", "r", .fewestTransfers)
        #expect(try #require(fastest).cost.minutes == 7)
        #expect(try #require(fastest).cost.transfers == 1)
        #expect(try #require(fewest).cost.transfers == 0)
        #expect(try #require(fewest).cost.minutes == 20)
    }

    @Test("fewestStops minimises hops even when slower")
    func fewestStops() throws {
        let (_, result) = try shortest(Fixture.divergingCriteria, "p", "r", .fewestStops)
        #expect(try #require(result).cost.stops == 1)
    }

    @Test("An unreachable destination returns nil, it does not hang or crash")
    func unreachable() throws {
        let (_, result) = try shortest(Fixture.disconnected, "i1", "j2")
        #expect(result == nil)
    }

    @Test("Empty sources or targets return nil")
    func emptyEndpoints() throws {
        let graph = try Fixture.graph(Fixture.linear)
        #expect(Dijkstra.shortestPath(in: graph, from: [], to: [0], criterion: .fastest) == nil)
        #expect(Dijkstra.shortestPath(in: graph, from: [0], to: [], criterion: .fastest) == nil)
    }

    @Test("Boarding at a multi-line station costs nothing — all platforms are seeded")
    func multiSourceSeeding() throws {
        // p is on X and Z; reaching r must not pay a transfer just to pick a line.
        let (_, result) = try shortest(Fixture.divergingCriteria, "p", "r", .fewestTransfers)
        #expect(try #require(result).cost.transfers == 0)
    }

    /// Cross-check against an obviously-correct but slow algorithm.
    @Test("Agrees with a Bellman-Ford oracle on every pair of every fixture")
    func matchesBruteForce() throws {
        let fixtures = [
            Fixture.linear, Fixture.penaltyTrap, Fixture.aThenBThenA,
            Fixture.divergingCriteria, Fixture.complexWithWalk,
            Fixture.sharedTrunk, Fixture.loopLine, Fixture.branchingLine,
            Fixture.disconnected,
        ]
        for json in fixtures {
            let network = try Fixture.network(json)
            let graph = LineExpandedGraph(network: network)
            for origin in network.stations {
                for destination in network.stations where origin.id != destination.id {
                    let sources = graph.platforms(at: origin.id)
                    let targets = Set(graph.platforms(at: destination.id))
                    guard !sources.isEmpty, !targets.isEmpty else { continue }
                    for criterion in RouteCriterion.allCases {
                        let expected = bellmanFord(graph, sources, targets, criterion)
                        let actual = Dijkstra.shortestPath(
                            in: graph, from: sources, to: targets, criterion: criterion
                        )?.cost
                        switch (expected, actual) {
                        case (nil, nil):
                            break
                        case let (lhs?, rhs?):
                            // Equal under the criterion's own ordering.
                            #expect(!criterion.isLower(lhs, rhs) && !criterion.isLower(rhs, lhs),
                                    "\(origin.id)→\(destination.id) \(criterion): \(lhs) vs \(rhs)")
                        default:
                            Issue.record("reachability disagreement for \(origin.id)→\(destination.id) under \(criterion)")
                        }
                    }
                }
            }
        }
    }

    /// Relax every edge |V| times — no heap, no early exit, no settling logic.
    private func bellmanFord(
        _ graph: LineExpandedGraph,
        _ sources: [Int],
        _ targets: Set<Int>,
        _ criterion: RouteCriterion
    ) -> PathCost? {
        var best = [PathCost?](repeating: nil, count: graph.nodeCount)
        for source in sources { best[source] = .zero }
        for _ in 0..<graph.nodeCount {
            var changed = false
            for node in 0..<graph.nodeCount {
                guard let current = best[node] else { continue }
                for edge in graph.adjacency[node] {
                    let candidate = current.adding(minutes: edge.minutes, isTransfer: edge.isTransfer)
                    if best[edge.to] == nil || criterion.isLower(candidate, best[edge.to]!) {
                        best[edge.to] = candidate
                        changed = true
                    }
                }
            }
            if !changed { break }
        }
        return targets.compactMap { best[$0] }.min { criterion.isLower($0, $1) }
    }
}
