import Foundation

/// A node of the line-expanded graph: a `(station, line)` pair — think of it as
/// "the platform of line L at station S" (CONTEXT §4.2).
struct PlatformNode: Hashable {
    let station: StationID
    let line: LineID
}

enum GraphEdgeKind {
    /// Riding one hop along a line.
    case ride
    /// Changing lines inside one station. Carries the fixed penalty.
    case transfer
}

struct GraphEdge {
    let to: Int
    let kind: GraphEdgeKind
    let minutes: Double

    var isTransfer: Bool { kind == .transfer }
}

/// Builds and owns the line-expanded graph.
///
/// Why this shape (CONTEXT §4.2–4.3):
/// - the transfer penalty is an **edge weight inside the search**, so Dijkstra
///   cannot pick a "fast but 3-transfer" path by mistake;
/// - multi-line stations need no special casing — they are simply several
///   nodes;
/// - the lines used by a path are read off the nodes, so nothing has to
///   reconstruct them afterwards.
///
/// The structure is static for a given network, so it is built **once** and
/// reused for every query.
final class LineExpandedGraph {
    let network: MetroNetwork

    /// Node table. Indexes into this array are the node ids used everywhere
    /// else (adjacency, Dijkstra) — integers keep the hot loop allocation-free.
    private(set) var nodes: [PlatformNode] = []
    private(set) var adjacency: [[GraphEdge]] = []

    private var indexOfNode: [PlatformNode: Int] = [:]
    /// All platforms belonging to a station — i.e. the targets of the virtual
    /// START edges / sources of the virtual END edges.
    private(set) var platformsByStation: [StationID: [Int]] = [:]

    init(network: MetroNetwork) {
        self.network = network
        buildNodes()
        buildRideEdges()
        buildTransferEdges()
    }

    // MARK: - Construction

    /// One node per `(station, line)` pair that actually appears in a segment.
    /// A line that never serves a station gets no node there, so no phantom
    /// transfers are possible.
    private func buildNodes() {
        for segment in network.segments {
            addNode(PlatformNode(station: segment.from, line: segment.line))
            addNode(PlatformNode(station: segment.to, line: segment.line))
        }
    }

    @discardableResult
    private func addNode(_ node: PlatformNode) -> Int {
        if let existing = indexOfNode[node] { return existing }
        let index = nodes.count
        nodes.append(node)
        adjacency.append([])
        indexOfNode[node] = index
        platformsByStation[node.station, default: []].append(index)
        return index
    }

    /// Ride edges, both directions — the network is undirected (CONTEXT §3.1).
    private func buildRideEdges() {
        for segment in network.segments {
            let a = addNode(PlatformNode(station: segment.from, line: segment.line))
            let b = addNode(PlatformNode(station: segment.to, line: segment.line))
            adjacency[a].append(GraphEdge(to: b, kind: .ride, minutes: segment.minutes))
            adjacency[b].append(GraphEdge(to: a, kind: .ride, minutes: segment.minutes))
        }
    }

    /// Transfer edges between every pair of platforms you can walk between,
    /// both directions, each weighted with the fixed penalty.
    ///
    /// The grouping key is the station's `transferGroup`, not its id, so an
    /// interchange split across two officially-named stations (M7
    /// "Mecidiyeköy" / M2 "Şişli-Mecidiyeköy") connects without either station
    /// being renamed or merged away.
    private func buildTransferEdges() {
        let penalty = network.transferPenaltyMinutes
        // Per-pair exceptions to the global penalty (long walks between
        // platforms that are officially one interchange).
        let overrides = TransferPenaltyTable(network.customTransferPenalties)

        var platformsByComplex: [String: [Int]] = [:]
        for (stationID, platforms) in platformsByStation {
            let group = network.station(stationID)?.transferGroup ?? stationID
            platformsByComplex[group, default: []].append(contentsOf: platforms)
        }

        for (_, platforms) in platformsByComplex where platforms.count > 1 {
            for i in platforms.indices {
                for j in platforms.indices where i != j {
                    // Two platforms of the SAME line at two different stations
                    // of one complex are not a transfer anyone would make —
                    // they are two separate stops you ride between.
                    let from = nodes[platforms[i]]
                    let to = nodes[platforms[j]]
                    guard from.line != to.line || from.station == to.station else { continue }
                    adjacency[platforms[i]].append(
                        GraphEdge(
                            to: platforms[j],
                            kind: .transfer,
                            minutes: overrides.minutes(from: from, to: to) ?? penalty
                        )
                    )
                }
            }
        }
    }

    // MARK: - Queries

    func node(at index: Int) -> PlatformNode { nodes[index] }

    /// The virtual START construction of CONTEXT §4.2: a source node joined to
    /// every platform of the origin station by a 0-weight edge. Seeding those
    /// platforms directly at cost zero is equivalent and avoids rebuilding the
    /// graph per query.
    func platforms(at station: StationID) -> [Int] {
        platformsByStation[station] ?? []
    }

    var nodeCount: Int { nodes.count }

    var edgeCount: Int { adjacency.reduce(0) { $0 + $1.count } }
}
