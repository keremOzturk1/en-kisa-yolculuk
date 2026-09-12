import Foundation
@testable import EnKisaYolculuk

/// Small hand-built networks, so unit tests assert behaviour rather than
/// re-asserting whatever happens to be in the shipped data file.
///
/// Everything is built by decoding JSON, which also keeps the fixtures honest:
/// a test network that cannot be decoded is a test network the app could not
/// load either.
enum Fixture {

    static func network(_ json: String) throws -> MetroNetwork {
        try JSONDecoder().decode(MetroNetwork.self, from: Data(json.utf8))
    }

    static func service(_ json: String) throws -> RouteService {
        RouteService(network: try network(json))
    }

    static func graph(_ json: String) throws -> LineExpandedGraph {
        LineExpandedGraph(network: try network(json))
    }

    // MARK: - Canonical shapes

    /// One line, three stations in a row: A —2— B —3— C.
    static let linear = """
    {
      "version": 1,
      "transferPenaltyMinutes": 10,
      "stations": [
        {"id": "a", "name": "A"}, {"id": "b", "name": "B"}, {"id": "c", "name": "C"}
      ],
      "lines": [{"id": "L1", "name": "Line One", "colorHex": "#112233"}],
      "segments": [
        {"line": "L1", "from": "a", "to": "b", "minutes": 2},
        {"line": "L1", "from": "b", "to": "c", "minutes": 3}
      ]
    }
    """

    /// The CONTEXT §4.1 trap, as data.
    ///
    /// `s → t` two ways:
    ///   • line D, direct, 20 min, no transfers;
    ///   • lines P1…P4, 4 min of riding but **three** transfers.
    ///
    /// Plain Dijkstra on raw time picks the 4-minute path. With the penalty
    /// inside the search it costs 4 + 30 = 34 and the direct line wins. Adding
    /// the penalty afterwards would fix the number on screen but not the path.
    static let penaltyTrap = """
    {
      "version": 1,
      "transferPenaltyMinutes": 10,
      "stations": [
        {"id": "s", "name": "S"}, {"id": "a", "name": "A"}, {"id": "b", "name": "B"},
        {"id": "c", "name": "C"}, {"id": "t", "name": "T"}
      ],
      "lines": [
        {"id": "D", "name": "Direct"}, {"id": "P1", "name": "P1"},
        {"id": "P2", "name": "P2"}, {"id": "P3", "name": "P3"}, {"id": "P4", "name": "P4"}
      ],
      "segments": [
        {"line": "D",  "from": "s", "to": "t", "minutes": 20},
        {"line": "P1", "from": "s", "to": "a", "minutes": 1},
        {"line": "P2", "from": "a", "to": "b", "minutes": 1},
        {"line": "P3", "from": "b", "to": "c", "minutes": 1},
        {"line": "P4", "from": "c", "to": "t", "minutes": 1}
      ]
    }
    """

    /// Line A, then B, then A again — the case the "n lines ⇒ n−1 transfers"
    /// formula gets wrong (AGENTS.md pitfall #5). Two distinct lines, but two
    /// transfers.
    static let aThenBThenA = """
    {
      "version": 1,
      "transferPenaltyMinutes": 5,
      "stations": [
        {"id": "s1", "name": "S1"}, {"id": "s2", "name": "S2"},
        {"id": "s3", "name": "S3"}, {"id": "s4", "name": "S4"}
      ],
      "lines": [{"id": "A", "name": "A"}, {"id": "B", "name": "B"}],
      "segments": [
        {"line": "A", "from": "s1", "to": "s2", "minutes": 1},
        {"line": "B", "from": "s2", "to": "s3", "minutes": 1},
        {"line": "A", "from": "s3", "to": "s4", "minutes": 1}
      ]
    }
    """

    /// Three criteria that genuinely disagree.
    ///   fastest         : X+Y, 2 stops, 1 transfer, 1+5+1 = 7
    ///   fewestTransfers : Z direct, 0 transfers, 1 stop, 20
    ///   fewestStops     : Z direct, 1 stop
    static let divergingCriteria = """
    {
      "version": 1,
      "transferPenaltyMinutes": 5,
      "stations": [
        {"id": "p", "name": "P"}, {"id": "q", "name": "Q"}, {"id": "r", "name": "R"}
      ],
      "lines": [{"id": "X", "name": "X"}, {"id": "Y", "name": "Y"}, {"id": "Z", "name": "Z"}],
      "segments": [
        {"line": "X", "from": "p", "to": "q", "minutes": 1},
        {"line": "Y", "from": "q", "to": "r", "minutes": 1},
        {"line": "Z", "from": "p", "to": "r", "minutes": 20}
      ]
    }
    """

    /// Two separately-named stations forming one interchange, plus a custom
    /// 15-minute walk between them.
    static let complexWithWalk = """
    {
      "version": 1,
      "transferPenaltyMinutes": 10,
      "stations": [
        {"id": "n1", "name": "North One"},
        {"id": "n2", "name": "North Two", "complexId": "cx_north"},
        {"id": "n3", "name": "North Three", "complexId": "cx_north"},
        {"id": "n4", "name": "North Four"}
      ],
      "lines": [{"id": "K", "name": "K"}, {"id": "M", "name": "M"}],
      "segments": [
        {"line": "K", "from": "n1", "to": "n2", "minutes": 2},
        {"line": "M", "from": "n3", "to": "n4", "minutes": 2}
      ],
      "customTransferPenalties": [
        {"stationA": "n2", "lineA": "K", "stationB": "n3", "lineB": "M", "minutes": 15}
      ]
    }
    """

    /// Two lines sharing a trunk then diverging — the M1A/M1B shape.
    static let sharedTrunk = """
    {
      "version": 1,
      "transferPenaltyMinutes": 10,
      "stations": [
        {"id": "t1", "name": "T1"}, {"id": "t2", "name": "T2"}, {"id": "t3", "name": "T3"},
        {"id": "fa", "name": "Fork A"}, {"id": "fb", "name": "Fork B"}
      ],
      "lines": [{"id": "BA", "name": "Branch A"}, {"id": "BB", "name": "Branch B"}],
      "segments": [
        {"line": "BA", "from": "t1", "to": "t2", "minutes": 2},
        {"line": "BA", "from": "t2", "to": "t3", "minutes": 2},
        {"line": "BA", "from": "t3", "to": "fa", "minutes": 2},
        {"line": "BB", "from": "t1", "to": "t2", "minutes": 2},
        {"line": "BB", "from": "t2", "to": "t3", "minutes": 2},
        {"line": "BB", "from": "t3", "to": "fb", "minutes": 2}
      ]
    }
    """

    /// A ring: no endpoints, so no running order and therefore no direction.
    static let loopLine = """
    {
      "version": 1,
      "transferPenaltyMinutes": 10,
      "stations": [
        {"id": "r1", "name": "R1"}, {"id": "r2", "name": "R2"}, {"id": "r3", "name": "R3"}
      ],
      "lines": [{"id": "O", "name": "Orbital"}],
      "segments": [
        {"line": "O", "from": "r1", "to": "r2", "minutes": 1},
        {"line": "O", "from": "r2", "to": "r3", "minutes": 1},
        {"line": "O", "from": "r3", "to": "r1", "minutes": 1}
      ]
    }
    """

    /// A line that forks inside itself: three endpoints, so no linear order.
    static let branchingLine = """
    {
      "version": 1,
      "transferPenaltyMinutes": 10,
      "stations": [
        {"id": "h", "name": "Hub"}, {"id": "e1", "name": "End1"},
        {"id": "e2", "name": "End2"}, {"id": "e3", "name": "End3"}
      ],
      "lines": [{"id": "Y", "name": "Wye"}],
      "segments": [
        {"line": "Y", "from": "h", "to": "e1", "minutes": 1},
        {"line": "Y", "from": "h", "to": "e2", "minutes": 1},
        {"line": "Y", "from": "h", "to": "e3", "minutes": 1}
      ]
    }
    """

    /// Two islands with no link — every cross pair is unreachable.
    static let disconnected = """
    {
      "version": 1,
      "transferPenaltyMinutes": 10,
      "stations": [
        {"id": "i1", "name": "I1"}, {"id": "i2", "name": "I2"},
        {"id": "j1", "name": "J1"}, {"id": "j2", "name": "J2"}
      ],
      "lines": [{"id": "I", "name": "I"}, {"id": "J", "name": "J"}],
      "segments": [
        {"line": "I", "from": "i1", "to": "i2", "minutes": 1},
        {"line": "J", "from": "j1", "to": "j2", "minutes": 1}
      ]
    }
    """

    /// Two different stations that share a display name — the Metrobüs shape.
    static let ambiguousNames = """
    {
      "version": 1,
      "transferPenaltyMinutes": 10,
      "stations": [
        {"id": "dup_one", "name": "Dup"}, {"id": "dup_two", "name": "Dup"},
        {"id": "solo", "name": "Solo"}, {"id": "other", "name": "Other"}
      ],
      "lines": [{"id": "AA", "name": "AA"}, {"id": "BB", "name": "BB"}],
      "segments": [
        {"line": "AA", "from": "dup_one", "to": "solo", "minutes": 1},
        {"line": "BB", "from": "dup_two", "to": "other", "minutes": 1}
      ]
    }
    """
}
