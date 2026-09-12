import Foundation

/// Minutes as a person reads them: "72", or "7,5" for a half minute.
/// Travel times are Double since tram/funicular hops are 2.5 min, but almost
/// every total lands on a whole number and should not read "72.0".
func formatMinutes(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    if rounded == rounded.rounded() {
        return String(Int(rounded))
    }
    return String(format: "%.1f", rounded).replacingOccurrences(of: ".", with: ",")
}

/// The cost accumulated along a path. All three components are non-negative and
/// additive, so Dijkstra stays correct under *any* lexicographic ordering of
/// them — which is exactly how the three criteria are implemented.
struct PathCost: Hashable {
    /// Travel time **including** transfer penalties (CONTEXT §4.1: the penalty
    /// is part of the weight, not something added afterwards).
    var minutes: Double = 0
    var transfers: Int = 0
    /// Number of inter-station hops ridden.
    var stops: Int = 0

    static let zero = PathCost()

    func adding(minutes m: Double, isTransfer: Bool) -> PathCost {
        PathCost(minutes: minutes + m,
                 transfers: transfers + (isTransfer ? 1 : 0),
                 stops: stops + (isTransfer ? 0 : 1))
    }
}

/// The three alternatives the app offers (CONTEXT §5, option 2).
/// Each criterion is a different *ordering* over `PathCost` on the same
/// line-expanded graph — not a different algorithm, and not k-shortest paths.
enum RouteCriterion: String, CaseIterable, Codable, Identifiable {
    case fastest
    case fewestTransfers
    case fewestStops

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fastest:          return "En Hızlı"
        case .fewestTransfers:  return "En Az Aktarma"
        case .fewestStops:      return "En Az Durak"
        }
    }

    var systemImageName: String {
        switch self {
        case .fastest:          return "bolt.fill"
        case .fewestTransfers:  return "arrow.triangle.swap"
        case .fewestStops:      return "smallcircle.filled.circle"
        }
    }

    /// Lexicographic key. The leading component is what the criterion
    /// optimises; the rest are deterministic tie-breakers so equal-primary
    /// paths still come out in a sensible order.
    private func key(_ c: PathCost) -> [Double] {
        switch self {
        case .fastest:          return [c.minutes, Double(c.transfers), Double(c.stops)]
        case .fewestTransfers:  return [Double(c.transfers), c.minutes, Double(c.stops)]
        case .fewestStops:      return [Double(c.stops), c.minutes, Double(c.transfers)]
        }
    }

    func isLower(_ a: PathCost, _ b: PathCost) -> Bool {
        let ka = key(a), kb = key(b)
        for (x, y) in zip(ka, kb) where x != y { return x < y }
        return false
    }
}

/// A continuous ride on one line, with no transfer inside it.
struct RouteLeg: Identifiable, Hashable {
    let id = UUID()
    let line: Line
    /// Boarding station first, alighting station last. Always >= 2 entries.
    let stations: [Station]
    /// Riding time for this leg only — excludes the transfer penalty that
    /// precedes it.
    let minutes: Double
    /// The line's terminus in the direction of travel — what the platform sign
    /// says. Nil only when the line has no linear running order
    /// (see `LineTopology`).
    let direction: Station?

    var boarding: Station { stations.first! }
    var alighting: Station { stations.last! }
    var stopCount: Int { stations.count - 1 }
    var minutesText: String { formatMinutes(minutes) }

    /// e.g. "Sabiha Gökçen yönü"
    var directionText: String? {
        direction.map { "\($0.name) yönü" }
    }
}

/// One presentable alternative.
struct Route: Identifiable, Hashable {
    let id = UUID()
    /// Which criteria selected this route. More than one when two criteria
    /// happen to agree on the same path (see `RouteService` de-duplication).
    let criteria: [RouteCriterion]
    let legs: [RouteLeg]
    let cost: PathCost
    /// The station the traveller asked to start from. This is **not** always
    /// where they board: at an interchange spread over two stations (a
    /// Metrobüs stop and the rail station beside it) the journey can begin
    /// with a walk. Without this the route would claim to start at the
    /// boarding station and silently swallow that walk.
    let origin: Station
    let destination: Station
    /// The lines that actually serve `origin` / `destination`.
    ///
    /// Needed because a walk endpoint is often **not** on the line you ride:
    /// Zincirlikuyu is a Metrobüs stop, and labelling it with the M2 you board
    /// after walking to Gayrettepe would put it on a line it is not on.
    let originLines: [Line]
    let destinationLines: [Line]
    /// Minutes spent walking before the first ride / after the last one.
    let leadingWalkMinutes: Double?
    let trailingWalkMinutes: Double?

    var startsWithWalk: Bool { leadingWalkMinutes != nil }
    var endsWithWalk: Bool { trailingWalkMinutes != nil }

    /// Derived straight from the leg structure — no "n lines → n−1 transfers"
    /// guesswork (AGENTS.md pitfall #5). An A→B→A path yields three legs and
    /// therefore two transfers, correctly.
    var transferCount: Int { legs.count - 1 }
    var totalMinutes: Double { cost.minutes }
    var stopCount: Int { cost.stops }

    var primaryCriterion: RouteCriterion { criteria.first! }

    /// e.g. "50" — for display next to a "dakika" label.
    var totalMinutesText: String { formatMinutes(totalMinutes) }

    /// e.g. "50 dakika, 2 aktarma"
    var summary: String {
        "\(totalMinutesText) dakika, \(transferCount) aktarma"
    }
}
