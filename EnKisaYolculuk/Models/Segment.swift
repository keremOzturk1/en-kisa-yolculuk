import Foundation

/// One hop between two adjacent stations **on a given line** — the raw edge as
/// it appears in `network.json`.
///
/// Segments are **undirected**: a single row describes travel in both
/// directions (CONTEXT §3.1). Do not emit the mirrored row from Excel; the
/// graph builder adds the reverse edge itself.
struct Segment: Codable, Hashable {
    let line: LineID
    let from: StationID
    let to: StationID
    /// Travel time in minutes. Must be >= 0 (Dijkstra requirement).
    ///
    /// Double because tram and funicular hops are 2.5 min. Half-minute values
    /// are exact in binary floating point, so sums stay exact and the
    /// lexicographic cost comparisons need no epsilon.
    let minutes: Double
}
