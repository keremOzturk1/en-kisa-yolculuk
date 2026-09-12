import Foundation

/// Stable identifier used in `network.json` (e.g. "M4", "B1").
typealias LineID = String

/// A line. A line has *many* stations; see `Station` for the other half of the
/// many-to-many association.
struct Line: Identifiable, Codable, Hashable {
    let id: LineID
    let name: String
    /// Optional "#RRGGBB". Drives the line colour in the UI when present.
    let colorHex: String?

    init(id: LineID, name: String, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}
