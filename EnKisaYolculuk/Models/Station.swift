import Foundation

/// Stable identifier used in `network.json` (e.g. "ayrilik_cesmesi").
/// Kept as a plain `String` so the JSON stays hand-editable / Excel-exportable.
typealias StationID = String

/// A physical station. A station belongs to *many* lines; that relationship is
/// expressed by the segments in `MetroNetwork`, never by inheritance.
struct Station: Identifiable, Codable, Hashable {
    let id: StationID
    let name: String
    /// Shared by every station that is part of the same interchange complex but
    /// carries a different official name per line — e.g. M7 "Mecidiyeköy" and
    /// M2 "Şişli-Mecidiyeköy".
    ///
    /// Stations in one complex keep their own ids and their own official names;
    /// only the transfer edges treat them as one place. Nil means the station
    /// is its own complex, which is the normal case.
    ///
    /// This is never inferred from name similarity — it comes from an explicit
    /// verified mapping in `Tools/build_network.py`.
    let complexId: String?
    /// Optional — only needed once a map view exists.
    let latitude: Double?
    let longitude: Double?

    /// The key used to decide "can you walk between these platforms": the
    /// complex when there is one, otherwise the station itself.
    var transferGroup: String { complexId ?? id }

    init(
        id: StationID,
        name: String,
        complexId: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.complexId = complexId
        self.latitude = latitude
        self.longitude = longitude
    }
}
