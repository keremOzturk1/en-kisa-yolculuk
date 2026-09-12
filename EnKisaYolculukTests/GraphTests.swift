import Foundation
import Testing
@testable import EnKisaYolculuk

@Suite("LineExpandedGraph construction")
struct LineExpandedGraphTests {

    private func transferEdge(
        _ graph: LineExpandedGraph,
        _ a: StationID, _ lineA: LineID,
        _ b: StationID, _ lineB: LineID
    ) -> GraphEdge? {
        guard let from = graph.platforms(at: a).first(where: { graph.node(at: $0).line == lineA }),
              let to = graph.platforms(at: b).first(where: { graph.node(at: $0).line == lineB })
        else { return nil }
        return graph.adjacency[from].first { $0.isTransfer && $0.to == to }
    }

    @Test("One node per (station, line) pair that actually stops there")
    func nodesAreStationLinePairs() throws {
        let graph = try Fixture.graph(Fixture.divergingCriteria)
        // p, q, r across lines X, Y, Z: p∈{X,Z}, q∈{X,Y}, r∈{Y,Z} = 6 platforms.
        #expect(graph.nodeCount == 6)
        #expect(Set(graph.nodes) == [
            PlatformNode(station: "p", line: "X"), PlatformNode(station: "p", line: "Z"),
            PlatformNode(station: "q", line: "X"), PlatformNode(station: "q", line: "Y"),
            PlatformNode(station: "r", line: "Y"), PlatformNode(station: "r", line: "Z"),
        ])
    }

    @Test("A line gets no platform at a station it does not serve")
    func noPhantomPlatforms() throws {
        let graph = try Fixture.graph(Fixture.divergingCriteria)
        let linesAtQ = Set(graph.platforms(at: "q").map { graph.node(at: $0).line })
        #expect(linesAtQ == ["X", "Y"])
        #expect(!linesAtQ.contains("Z"))
    }

    @Test("Ride edges exist in both directions with the segment's weight")
    func rideEdgesAreUndirected() throws {
        let graph = try Fixture.graph(Fixture.linear)
        let a = try #require(graph.platforms(at: "a").first)
        let b = try #require(graph.platforms(at: "b").first)
        let forward = try #require(graph.adjacency[a].first { $0.to == b })
        let backward = try #require(graph.adjacency[b].first { $0.to == a })
        #expect(forward.kind == .ride)
        #expect(backward.kind == .ride)
        #expect(forward.minutes == 2)
        #expect(backward.minutes == 2)
    }

    @Test("Transfer edges join the platforms of one station at the global penalty")
    func transferEdgesUseGlobalPenalty() throws {
        let graph = try Fixture.graph(Fixture.divergingCriteria)
        let edge = try #require(transferEdge(graph, "p", "X", "p", "Z"))
        #expect(edge.minutes == 5)   // fixture's transferPenaltyMinutes
        #expect(edge.isTransfer)
    }

    @Test("Stations of one complex are joined even though no segment links them")
    func complexesAreLinked() throws {
        let graph = try Fixture.graph(Fixture.complexWithWalk)
        #expect(transferEdge(graph, "n2", "K", "n3", "M") != nil)
    }

    @Test("A custom penalty overrides the global one, both ways")
    func customPenaltyApplies() throws {
        let graph = try Fixture.graph(Fixture.complexWithWalk)
        #expect(transferEdge(graph, "n2", "K", "n3", "M")?.minutes == 15)
        #expect(transferEdge(graph, "n3", "M", "n2", "K")?.minutes == 15)
    }

    @Test("Stations outside a complex are never joined")
    func unrelatedStationsAreNotLinked() throws {
        let graph = try Fixture.graph(Fixture.complexWithWalk)
        #expect(transferEdge(graph, "n1", "K", "n4", "M") == nil)
    }

    @Test("Two stops of the SAME line inside one complex get no transfer edge")
    func noSameLineTransferInsideComplex() throws {
        // A complex whose two stations are both served by line S: you ride
        // between them, you do not 'transfer'.
        let graph = try Fixture.graph("""
        {"version":1,"transferPenaltyMinutes":10,
         "stations":[{"id":"u","name":"U","complexId":"cx"},
                     {"id":"v","name":"V","complexId":"cx"},
                     {"id":"w","name":"W"}],
         "lines":[{"id":"S","name":"S"}],
         "segments":[{"line":"S","from":"u","to":"v","minutes":1},
                     {"line":"S","from":"v","to":"w","minutes":1}]}
        """)
        #expect(transferEdge(graph, "u", "S", "v", "S") == nil)
    }

    @Test("A station served by one line only has no transfer edges")
    func singleLineStationHasNoTransfers() throws {
        let graph = try Fixture.graph(Fixture.linear)
        for platform in graph.platforms(at: "b") {
            #expect(!graph.adjacency[platform].contains { $0.isTransfer })
        }
    }

    @Test("platforms(at:) is empty for an unknown station")
    func unknownStationHasNoPlatforms() throws {
        let graph = try Fixture.graph(Fixture.linear)
        #expect(graph.platforms(at: "ghost").isEmpty)
    }

    @Test("Edge count is symmetric — every edge has a mirror")
    func adjacencyIsSymmetric() throws {
        for json in [Fixture.linear, Fixture.divergingCriteria,
                     Fixture.sharedTrunk, Fixture.complexWithWalk] {
            let graph = try Fixture.graph(json)
            for from in 0..<graph.nodeCount {
                for edge in graph.adjacency[from] {
                    let mirrored = graph.adjacency[edge.to].contains {
                        $0.to == from && $0.kind == edge.kind && $0.minutes == edge.minutes
                    }
                    #expect(mirrored, "no mirror for \(graph.nodes[from]) → \(graph.nodes[edge.to])")
                }
            }
        }
    }
}

@Suite("LineTopology")
struct LineTopologyTests {

    @Test("A simple line gets a running order")
    func linearOrder() throws {
        let network = try Fixture.network(Fixture.linear)
        let topology = try #require(network.lineTopologies()["L1"])
        #expect(topology.orderedStations == ["a", "b", "c"])
    }

    @Test("Direction is the terminus ahead of you, and flips with travel")
    func terminusFollowsDirection() throws {
        let network = try Fixture.network(Fixture.linear)
        let topology = try #require(network.lineTopologies()["L1"])
        #expect(topology.terminus(boarding: "a", alighting: "b") == "c")
        #expect(topology.terminus(boarding: "c", alighting: "b") == "a")
        #expect(topology.terminus(boarding: "a", alighting: "c") == "c")
    }

    @Test("Boarding and alighting at the same station has no direction")
    func sameStationHasNoDirection() throws {
        let network = try Fixture.network(Fixture.linear)
        let topology = try #require(network.lineTopologies()["L1"])
        #expect(topology.terminus(boarding: "b", alighting: "b") == nil)
    }

    @Test("A station not on the line has no direction")
    func foreignStationHasNoDirection() throws {
        let network = try Fixture.network(Fixture.linear)
        let topology = try #require(network.lineTopologies()["L1"])
        #expect(topology.terminus(boarding: "a", alighting: "ghost") == nil)
    }

    @Test("A ring has no running order, so no direction is invented")
    func loopHasNoOrder() throws {
        let network = try Fixture.network(Fixture.loopLine)
        let topology = try #require(network.lineTopologies()["O"])
        #expect(topology.orderedStations == nil)
        #expect(topology.terminus(boarding: "r1", alighting: "r2") == nil)
    }

    @Test("A line that forks has no running order")
    func branchHasNoOrder() throws {
        let network = try Fixture.network(Fixture.branchingLine)
        let topology = try #require(network.lineTopologies()["Y"])
        #expect(topology.orderedStations == nil)
    }

    @Test("Every line in the network gets a topology entry")
    func topologyCoversAllLines() throws {
        let network = try Fixture.network(Fixture.divergingCriteria)
        #expect(Set(network.lineTopologies().keys) == ["X", "Y", "Z"])
    }
}
