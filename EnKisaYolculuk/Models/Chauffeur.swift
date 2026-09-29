import Foundation

/// The one personal thing in this app: the offer, at the top of every list of
/// alternatives, to drive her there instead.
///
/// Deliberately **not** a `Route` and **not** a `RouteCriterion` — it claims no
/// duration, no distance and no stop count, so it needs no station coordinates
/// and touches neither the graph nor the data. It is presentation only
/// (CONTEXT.md §7.3).
///
/// Every string lives here so the wording is set in one place and never
/// scattered through the views. Same shape as `Brand`.
///
/// The phone number is the one exception: it is **not** in this file, because
/// this repository is public. It is read at launch from `contact.json`, which
/// is gitignored — see `phoneNumber`.
enum Chauffeur {
    /// Digits only, with the country code — `tel:` and `sms:` reject spaces and
    /// punctuation.
    ///
    /// Read from `contact.json` in the app bundle rather than written here, so
    /// a real number never enters a public repository. `contact.json` is
    /// gitignored; `contact.example.json` beside it records the shape, and
    /// README says how to recreate it.
    ///
    /// `nil` when the file is absent (a fresh clone). Nothing crashes: the
    /// detail screen keeps its buttons but disables them and says why, which is
    /// far better than a build that will not compile without an untracked file.
    static let phoneNumber: String? = loadPhoneNumber()

    private struct Contact: Decodable { let phoneNumber: String }

    private static func loadPhoneNumber(in bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "contact", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let contact = try? JSONDecoder().decode(Contact.self, from: data)
        else { return nil }

        let trimmed = contact.phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Shown to a human, so it keeps its spaces.
    static let plate = "34 KRM 050"

    /// The capsule on the card, where the other cards carry "En Hızlı".
    static let badge = "Kerem ile"

    static let cardTitle = "Seni ben götüreyim"
    static let cardSubtitle = "kapından kapına"

    static let detailTitle = "Seni ben götüreyim"

    /// The closing line on the detail screen.
    static let closingLine = "Nereye gidersen git, yolun bana çıksın."

    /// Pre-filled body for the message button. The journey is already known, so
    /// she never has to type where she is going.
    ///
    /// Phrased so that no Turkish case suffix is ever attached to a station
    /// name: "Yenikapı'den" / "Levent'a" would be wrong, and getting vowel
    /// harmony right for all 307 official names is not worth it here.
    /// "civarındayım" and "tarafına" attach to nothing and read correctly for
    /// every one of them.
    static func messageBody(from origin: String, to destination: String) -> String {
        "\(origin) civarındayım, \(destination) tarafına gideceğim. Beni alır mısın?"
    }

    /// Same message, with a tappable Apple Maps pin for her exact position.
    static func locationMessageBody(
        from origin: String,
        to destination: String,
        latitude: Double,
        longitude: Double
    ) -> String {
        let pin = "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=Konumum"
        return "\(messageBody(from: origin, to: destination)) Konumum: \(pin)"
    }

    // MARK: - URLs

    /// `tel:+90…` — the canonical form; no `//`.
    static func callURL(phone: String) -> URL? {
        URL(string: "tel:\(phone)")
    }

    /// `sms:+90…&body=…`
    ///
    /// Built by hand on purpose. `URLComponents` produces `sms:+90…?body=…`, and
    /// Messages reads the recipient up to the first `&`, so with `?` the
    /// recipient comes out as `+90…?body=…`, is rejected, and the message opens
    /// with the text filled in and **no number** — which is exactly what
    /// happened on device.
    ///
    /// The body is encoded down to RFC 3986 unreserved characters: it can carry
    /// a map link whose own `?`, `&` and `=` would otherwise be read as more
    /// parameters and cut the message short.
    static func messageURL(phone: String, body: String) -> URL? {
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        // `alphanumerics` includes non-ASCII letters such as "ı" and "ş"; those
        // must be percent-encoded too, so restrict to ASCII explicitly.
        unreserved = unreserved.intersection(
            CharacterSet(charactersIn: Unicode.Scalar(0x21)...Unicode.Scalar(0x7E)))
        guard let encoded = body.addingPercentEncoding(withAllowedCharacters: unreserved)
        else { return nil }
        return URL(string: "sms:\(phone)&body=\(encoded)")
    }
}
