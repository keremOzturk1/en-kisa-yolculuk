import Foundation

/// The decoded contents of `network.json` — the whole static network.
///
/// This type mirrors the JSON 1:1 and holds *no* graph logic. The graph is
/// built from it by `LineExpandedGraph`.
struct MetroNetwork: Codable {
    /// Schema version. Bump only when the shape of the JSON changes.
    let version: Int
    /// Fixed transfer penalty, in minutes (CONTEXT §4.4 — 10 for v1).
    /// Lives in the data file so tuning it needs no rebuild of the code.
    let transferPenaltyMinutes: Double
    let stations: [Station]
    let lines: [Line]
    let segments: [Segment]
    /// Per-pair exceptions to `transferPenaltyMinutes`. Optional — an older
    /// data file without the key still decodes.
    let customTransferPenalties: [TransferPenaltyOverride]

    // MARK: - Lookup indexes

    /// Built once at decode time; the rest of the app reads through these.
    private(set) var stationsByID: [StationID: Station] = [:]
    private(set) var linesByID: [LineID: Line] = [:]
    /// Which lines serve each station — used to disambiguate stations that
    /// share a name (Marmaray "Göztepe" vs M4 "Göztepe").
    private(set) var lineIDsByStation: [StationID: [LineID]] = [:]

    private enum CodingKeys: String, CodingKey {
        case version, transferPenaltyMinutes, stations, lines, segments
        case customTransferPenalties
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        transferPenaltyMinutes = try container.decode(Double.self, forKey: .transferPenaltyMinutes)
        stations = try container.decode([Station].self, forKey: .stations)
        lines = try container.decode([Line].self, forKey: .lines)
        segments = try container.decode([Segment].self, forKey: .segments)
        customTransferPenalties = try container.decodeIfPresent(
            [TransferPenaltyOverride].self, forKey: .customTransferPenalties
        ) ?? []

        stationsByID = Dictionary(stations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        linesByID = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var lineIDs: [StationID: [LineID]] = [:]
        for segment in segments {
            for station in [segment.from, segment.to]
            where !(lineIDs[station]?.contains(segment.line) ?? false) {
                lineIDs[station, default: []].append(segment.line)
            }
        }
        lineIDsByStation = lineIDs.mapValues { $0.sorted() }
    }

    func station(_ id: StationID) -> Station? { stationsByID[id] }
    func line(_ id: LineID) -> Line? { linesByID[id] }
    func lineIDs(at station: StationID) -> [LineID] { lineIDsByStation[station] ?? [] }

    /// Names shared by more than one station — Marmaray and M4 both stop at a
    /// "Göztepe", and they are different places.
    private var ambiguousNames: Set<String> {
        var seen: Set<String> = []
        var duplicated: Set<String> = []
        for station in stations {
            if !seen.insert(station.name).inserted { duplicated.insert(station.name) }
        }
        return duplicated
    }

    /// The station's name, qualified by its lines only when the bare name
    /// would be ambiguous in a list. Official names are never rewritten in the
    /// data — this is presentation only.
    func displayName(_ station: Station, ambiguous: Set<String>? = nil) -> String {
        let duplicated = ambiguous ?? ambiguousNames
        guard duplicated.contains(station.name) else { return station.name }
        let lines = lineIDs(at: station.id)
        guard !lines.isEmpty else { return station.name }
        return "\(station.name) (\(lines.joined(separator: ", ")))"
    }

    /// Stations sorted for display in a picker (Turkish-aware collation).
    var stationsSortedByName: [Station] {
        stations.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// One selectable row: a station plus a label that is unique on screen.
    struct StationEntry: Identifiable, Hashable {
        let station: Station
        let label: String
        var id: StationID { station.id }
    }

    /// Picker rows: every station with a label that is unique on screen.
    var pickerEntries: [StationEntry] {
        let duplicated = ambiguousNames
        return stationsSortedByName.map {
            StationEntry(station: $0, label: displayName($0, ambiguous: duplicated))
        }
    }

    // MARK: - Validation

    enum ValidationError: LocalizedError {
        case duplicateStationID(StationID)
        case duplicateLineID(LineID)
        case unknownStation(StationID, inSegmentOn: LineID)
        case unknownLine(LineID)
        case negativeTravelTime(Segment)
        case selfLoop(Segment)
        case negativeTransferPenalty(Double)
        case overrideNamesNoStation(TransferPenaltyOverride)
        case overrideUnknownStation(StationID)
        case overrideUnknownLine(LineID)
        case overrideNegativeMinutes(TransferPenaltyOverride)

        var errorDescription: String? {
            switch self {
            case .duplicateStationID(let id):       return "Duplicate station id '\(id)'."
            case .duplicateLineID(let id):          return "Duplicate line id '\(id)'."
            case .unknownStation(let s, let l):     return "Segment on line '\(l)' references unknown station '\(s)'."
            case .unknownLine(let l):               return "Segment references unknown line '\(l)'."
            case .negativeTravelTime(let s):        return "Segment \(s.from)->\(s.to) on '\(s.line)' has negative time (\(s.minutes))."
            case .selfLoop(let s):                  return "Segment on '\(s.line)' starts and ends at '\(s.from)'."
            case .negativeTransferPenalty(let m):   return "transferPenaltyMinutes must be >= 0, got \(m)."
            case .overrideNamesNoStation(let o):    return "customTransferPenalties entry \(o.lineA)/\(o.lineB) names no station."
            case .overrideUnknownStation(let s):    return "customTransferPenalties references unknown station '\(s)'."
            case .overrideUnknownLine(let l):       return "customTransferPenalties references unknown line '\(l)'."
            case .overrideNegativeMinutes(let o):   return "customTransferPenalties entry \(o.lineA)/\(o.lineB) has negative minutes (\(o.minutes))."
            }
        }
    }

    /// Fails fast on the mistakes a hand-built / Excel-exported data file
    /// actually makes. Cheap enough to run at every launch.
    func validate() throws {
        guard transferPenaltyMinutes >= 0 else {
            throw ValidationError.negativeTransferPenalty(transferPenaltyMinutes)
        }
        guard stationsByID.count == stations.count else {
            let dupe = Dictionary(grouping: stations, by: \.id).first { $0.value.count > 1 }!.key
            throw ValidationError.duplicateStationID(dupe)
        }
        guard linesByID.count == lines.count else {
            let dupe = Dictionary(grouping: lines, by: \.id).first { $0.value.count > 1 }!.key
            throw ValidationError.duplicateLineID(dupe)
        }
        for segment in segments {
            guard linesByID[segment.line] != nil else { throw ValidationError.unknownLine(segment.line) }
            guard stationsByID[segment.from] != nil else {
                throw ValidationError.unknownStation(segment.from, inSegmentOn: segment.line)
            }
            guard stationsByID[segment.to] != nil else {
                throw ValidationError.unknownStation(segment.to, inSegmentOn: segment.line)
            }
            guard segment.minutes >= 0 else { throw ValidationError.negativeTravelTime(segment) }
            guard segment.from != segment.to else { throw ValidationError.selfLoop(segment) }
        }
        for override in customTransferPenalties {
            guard let (from, to) = override.endpoints else {
                throw ValidationError.overrideNamesNoStation(override)
            }
            for station in [from.station, to.station] where stationsByID[station] == nil {
                throw ValidationError.overrideUnknownStation(station)
            }
            for line in [from.line, to.line] where linesByID[line] == nil {
                throw ValidationError.overrideUnknownLine(line)
            }
            guard override.minutes >= 0 else {
                throw ValidationError.overrideNegativeMinutes(override)
            }
        }
    }
}
