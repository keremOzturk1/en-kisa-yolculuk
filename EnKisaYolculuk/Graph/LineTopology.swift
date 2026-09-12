import Foundation

/// The running order of the stations on one line, derived from its segments.
///
/// Needed for one thing only: naming the **direction** of a leg ("M4, Sabiha
/// Gökçen yönü"). The routing itself never uses this — it is presentation.
///
/// A line is normally a simple path, so its stations have a linear order with
/// two endpoints. Data that is a loop, or that branches (a fork modelled as one
/// line instead of two — see CONTEXT §7.1 item 7), has no single running order;
/// in that case `orderedStations` is nil and the UI simply omits the direction
/// rather than inventing one.
struct LineTopology {
    let lineID: LineID
    /// Stations end to end, or nil when the line is not a simple path.
    let orderedStations: [StationID]?

    private let position: [StationID: Int]

    init(lineID: LineID, segments: [Segment]) {
        self.lineID = lineID

        var neighbours: [StationID: Set<StationID>] = [:]
        for segment in segments {
            neighbours[segment.from, default: []].insert(segment.to)
            neighbours[segment.to, default: []].insert(segment.from)
        }

        let endpoints = neighbours
            .filter { $0.value.count == 1 }
            .keys
            .sorted()

        // Exactly two ends == a simple path. Anything else (a loop has none, a
        // fork has three or more) has no meaningful "direction".
        guard endpoints.count == 2, let firstSegment = segments.first else {
            self.orderedStations = nil
            self.position = [:]
            return
        }

        // Walk from the end the data itself starts at, so the order matches the
        // source listing rather than flipping on an id comparison.
        let start = endpoints.contains(firstSegment.from) ? firstSegment.from : endpoints[0]

        var order: [StationID] = [start]
        var visited: Set<StationID> = [start]
        var cursor = start
        while let next = neighbours[cursor]?.first(where: { !visited.contains($0) }) {
            order.append(next)
            visited.insert(next)
            cursor = next
        }

        // A path walk must reach every station; if it did not, the line is
        // disconnected and direction cannot be trusted.
        guard order.count == neighbours.count else {
            self.orderedStations = nil
            self.position = [:]
            return
        }

        self.orderedStations = order
        self.position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
    }

    /// The terminus a rider is heading towards when travelling from `boarding`
    /// to `alighting` on this line. Nil when the line has no linear order.
    func terminus(boarding: StationID, alighting: StationID) -> StationID? {
        guard let orderedStations,
              let from = position[boarding],
              let to = position[alighting],
              from != to
        else { return nil }
        return to > from ? orderedStations.last : orderedStations.first
    }
}

extension MetroNetwork {
    /// Topology per line, built once.
    func lineTopologies() -> [LineID: LineTopology] {
        let byLine = Dictionary(grouping: segments, by: \.line)
        return byLine.reduce(into: [:]) { result, entry in
            result[entry.key] = LineTopology(lineID: entry.key, segments: entry.value)
        }
    }
}
