import Foundation

/// A transfer that costs something other than the global penalty — typically a
/// long walk between platforms that are officially one interchange.
///
/// Two shapes are accepted, because a transfer is not always inside one
/// station:
///
/// ```json
/// { "stationId": "yenikapi",  "lineA": "M1A", "lineB": "M2", "minutes": 14 }
/// { "stationA": "bakirkoy",   "lineA": "Marmaray",
///   "stationB": "ozgurluk_meydani", "lineB": "M3", "minutes": 15 }
/// ```
///
/// `stationId` is shorthand for "both sides are this station". The two-station
/// form re-weights the edge between two stations of one `complexId` — the data
/// build guarantees such a pair is always placed in a complex, so the edge
/// exists by the time this table is consulted.
struct TransferPenaltyOverride: Codable, Hashable {
    let stationId: StationID?
    let stationA: StationID?
    let stationB: StationID?
    let lineA: LineID
    let lineB: LineID
    let minutes: Double

    /// The two platforms this override applies to, or nil if the entry names
    /// no station at all.
    var endpoints: (PlatformNode, PlatformNode)? {
        guard let from = stationA ?? stationId, let to = stationB ?? stationId else {
            return nil
        }
        return (PlatformNode(station: from, line: lineA),
                PlatformNode(station: to, line: lineB))
    }
}

/// Lookup table for the overrides, keyed so that either direction matches.
struct TransferPenaltyTable {
    /// Unordered pair of platforms -> minutes.
    private var minutesByPair: [Pair: Double] = [:]

    private struct Pair: Hashable {
        let a: PlatformNode
        let b: PlatformNode

        /// Normalised so (x, y) and (y, x) hash identically.
        init(_ x: PlatformNode, _ y: PlatformNode) {
            if (x.station, x.line) <= (y.station, y.line) {
                a = x; b = y
            } else {
                a = y; b = x
            }
        }
    }

    init(_ overrides: [TransferPenaltyOverride]) {
        for override in overrides {
            guard let (from, to) = override.endpoints else { continue }
            minutesByPair[Pair(from, to)] = override.minutes
        }
    }

    /// The penalty for changing between these two platforms, or nil to use the
    /// network default.
    func minutes(from: PlatformNode, to: PlatformNode) -> Double? {
        minutesByPair[Pair(from, to)]
    }

    var isEmpty: Bool { minutesByPair.isEmpty }
    var count: Int { minutesByPair.count }
}
