import Foundation

/// Turns a (origin, destination) pair into the three alternatives the UI shows.
///
/// Strategy: **3 routes by criteria**, not k-shortest (CONTEXT §5, option 2).
/// Each criterion is one Dijkstra run over the same line-expanded graph with a
/// different ordering on `PathCost`, so every run keeps the transfer penalty
/// inside the search.
final class RouteService {

    enum RoutingError: LocalizedError {
        case sameOriginAndDestination
        case unknownStation(StationID)
        case stationNotOnAnyLine(Station)
        case noRouteFound(from: Station, to: Station)

        var errorDescription: String? {
            switch self {
            case .sameOriginAndDestination:
                return "Kalkış ve varış istasyonu aynı."
            case .unknownStation(let id):
                return "Bilinmeyen istasyon: '\(id)'."
            case .stationNotOnAnyLine(let station):
                return "'\(station.name)' hiçbir hat üzerinde değil (veri hatası)."
            case .noRouteFound(let from, let to):
                return "'\(from.name)' → '\(to.name)' arasında rota bulunamadı."
            }
        }
    }

    /// Key of one undirected hop, orientation-independent.
    private struct HopKey: Hashable {
        let line: LineID
        let a: StationID
        let b: StationID

        init(line: LineID, _ x: StationID, _ y: StationID) {
            self.line = line
            // Normalised so both directions hash the same.
            self.a = min(x, y)
            self.b = max(x, y)
        }
    }

    let network: MetroNetwork
    private let graph: LineExpandedGraph
    private let hopMinutes: [HopKey: Double]
    private let topologies: [LineID: LineTopology]

    init(network: MetroNetwork) {
        self.network = network
        self.graph = LineExpandedGraph(network: network)
        self.topologies = network.lineTopologies()
        // Duplicated rows (if the data ever has any) resolve to the fastest.
        self.hopMinutes = Dictionary(
            network.segments.map { (HopKey(line: $0.line, $0.from, $0.to), $0.minutes) },
            uniquingKeysWith: min
        )
    }

    convenience init() throws {
        self.init(network: try NetworkLoader.load())
    }

    /// The three alternatives, best-first within each criterion.
    ///
    /// Returns **at most** three routes: when two criteria select the same
    /// path, that path appears once carrying both labels rather than being
    /// listed twice.
    func routes(from originID: StationID, to destinationID: StationID) throws -> [Route] {
        guard let origin = network.station(originID) else {
            throw RoutingError.unknownStation(originID)
        }
        guard let destination = network.station(destinationID) else {
            throw RoutingError.unknownStation(destinationID)
        }
        guard originID != destinationID else {
            throw RoutingError.sameOriginAndDestination
        }

        let sources = graph.platforms(at: originID)
        guard !sources.isEmpty else { throw RoutingError.stationNotOnAnyLine(origin) }
        let targetList = graph.platforms(at: destinationID)
        guard !targetList.isEmpty else { throw RoutingError.stationNotOnAnyLine(destination) }
        let targets = Set(targetList)

        var routes: [Route] = []
        /// Identity of a path for de-duplication: the station/line sequence.
        var seen: [[PlatformNode]: Int] = [:]

        for criterion in RouteCriterion.allCases {
            guard let result = Dijkstra.shortestPath(
                in: graph, from: sources, to: targets, criterion: criterion
            ) else { continue }

            let signature = result.path.map { graph.node(at: $0) }
            if let existing = seen[signature] {
                // Same path as an earlier criterion — merge the label instead
                // of showing a duplicate row.
                let previous = routes[existing]
                routes[existing] = Route(criteria: previous.criteria + [criterion],
                                         legs: previous.legs,
                                         cost: previous.cost,
                                         origin: previous.origin,
                                         destination: previous.destination,
                                         originLines: previous.originLines,
                                         destinationLines: previous.destinationLines,
                                         leadingWalkMinutes: previous.leadingWalkMinutes,
                                         trailingWalkMinutes: previous.trailingWalkMinutes)
                continue
            }

            let built = makeLegs(from: result.path)
            guard !built.legs.isEmpty else { continue }
            seen[signature] = routes.count
            routes.append(Route(criteria: [criterion],
                                legs: built.legs,
                                cost: result.cost,
                                origin: origin,
                                destination: destination,
                                originLines: lines(at: originID),
                                destinationLines: lines(at: destinationID),
                                leadingWalkMinutes: built.leadingWalk,
                                trailingWalkMinutes: built.trailingWalk))
        }

        guard !routes.isEmpty else {
            throw RoutingError.noRouteFound(from: origin, to: destination)
        }
        return routes
    }

    // MARK: - Path → legs

    /// Groups the node path into continuous rides on one line. Because nodes
    /// carry their line, the lines used are read straight off the path — no
    /// post-hoc transfer detection (CONTEXT §4.3).
    private func makeLegs(
        from path: [Int]
    ) -> (legs: [RouteLeg], leadingWalk: Double?, trailingWalk: Double?) {
        let nodes = path.map { graph.node(at: $0) }
        guard nodes.count >= 2 else { return ([], nil, nil) }

        var legs: [RouteLeg] = []
        var currentLine = nodes[0].line
        var currentStations: [StationID] = [nodes[0].station]
        var currentMinutes: Double = 0

        for index in 1..<nodes.count {
            let previous = nodes[index - 1]
            let node = nodes[index]

            if node.line == currentLine {
                // Riding one hop.
                currentStations.append(node.station)
                currentMinutes += rideMinutes(line: currentLine, from: previous.station, to: node.station)
            } else {
                // Transfer edge: same station, different line. Close the leg —
                // unless nothing was actually ridden on it (the start station
                // may be entered on a line we immediately change away from).
                if currentStations.count >= 2 {
                    legs.append(makeLeg(line: currentLine, stations: currentStations, minutes: currentMinutes))
                }
                currentLine = node.line
                currentStations = [node.station]
                currentMinutes = 0
            }
        }

        if currentStations.count >= 2 {
            legs.append(makeLeg(line: currentLine, stations: currentStations, minutes: currentMinutes))
        }
        guard let first = legs.first, let last = legs.last else { return ([], nil, nil) }

        // A transfer edge crossed before the first ride (or after the last) is
        // a walk between two stations of one complex. It is already priced in
        // the cost; without surfacing it the route would appear to begin at
        // the boarding station.
        let leading = nodes[0].station == first.boarding.id
            ? nil
            : transferWeight(path, from: 0, to: 1)
        let trailing = nodes[nodes.count - 1].station == last.alighting.id
            ? nil
            : transferWeight(path, from: path.count - 2, to: path.count - 1)
        return (legs, leading, trailing)
    }

    /// Weight of the transfer edge between two adjacent nodes of the path.
    private func transferWeight(_ path: [Int], from: Int, to: Int) -> Double? {
        guard path.indices.contains(from), path.indices.contains(to) else { return nil }
        for edge in graph.adjacency[path[from]] where edge.isTransfer && edge.to == path[to] {
            return edge.minutes
        }
        return nil
    }

    private func makeLeg(line lineID: LineID, stations ids: [StationID], minutes: Double) -> RouteLeg {
        let line = network.line(lineID) ?? Line(id: lineID, name: lineID, colorHex: nil)
        let stations = ids.map { network.station($0) ?? Station(id: $0, name: $0) }
        // The terminus this leg is heading towards — what the platform sign
        // says. Nil for a line with no linear running order.
        let terminusID = topologies[lineID]?.terminus(boarding: ids.first!, alighting: ids.last!)
        return RouteLeg(
            line: line,
            stations: stations,
            minutes: minutes,
            direction: terminusID.flatMap { network.station($0) }
        )
    }

    /// The lines that serve a station, as `Line` values.
    private func lines(at station: StationID) -> [Line] {
        network.lineIDs(at: station).compactMap { network.line($0) }
    }

    /// Travel time of one hop, looked up in the precomputed index.
    private func rideMinutes(line: LineID, from: StationID, to: StationID) -> Double {
        hopMinutes[HopKey(line: line, from, to)] ?? 0
    }
}
