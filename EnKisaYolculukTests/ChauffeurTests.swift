import Foundation
import Testing
@testable import EnKisaYolculuk

/// `tel:` and `sms:` do nothing on the simulator, so the URLs are the only part
/// of the ride-with-me buttons a test can reach. These pin their exact shape —
/// the `sms:` one in particular, whose first version opened Messages with the
/// text filled in and no recipient.
///
/// A made-up number throughout: the real one lives only in the gitignored
/// `contact.json` and must never appear in a tracked file.
@Suite("Chauffeur URLs")
struct ChauffeurTests {

    private let phone = "+900000000000"

    @Test("The call URL is tel: with no slashes")
    func callURL() {
        #expect(Chauffeur.callURL(phone: phone)?.absoluteString == "tel:+900000000000")
    }

    @Test("The recipient is followed by &body=, never ?body=")
    func recipientSeparator() throws {
        let url = try #require(Chauffeur.messageURL(phone: phone, body: "Merhaba"))
        // Messages reads the recipient up to the first `&`. With `?` the whole
        // tail becomes part of the "number" and the recipient is dropped.
        #expect(url.absoluteString == "sms:+900000000000&body=Merhaba")
    }

    @Test("A map link inside the body cannot split the URL")
    func bodyIsFullyEncoded() throws {
        let body = Chauffeur.locationMessageBody(
            from: "Kadıköy", to: "Taksim", latitude: 41.0, longitude: 29.0)
        let url = try #require(Chauffeur.messageURL(phone: phone, body: body))
        let tail = try #require(url.absoluteString.components(separatedBy: "&body=").last)

        // Exactly one separator: the map link's own `?`, `&` and `=` are all
        // encoded, so nothing after `&body=` can be read as another parameter.
        #expect(url.absoluteString.components(separatedBy: "&body=").count == 2)
        for reserved in ["?", "&", "=", "#", "+", " "] {
            #expect(!tail.contains(reserved), "unencoded '\(reserved)' in \(tail)")
        }

        // …and it decodes back to exactly what was written.
        #expect(tail.removingPercentEncoding == body)
    }

    @Test("Turkish letters are percent-encoded, not passed through")
    func turkishLettersEncoded() throws {
        let url = try #require(Chauffeur.messageURL(phone: phone, body: "Şişli ığ"))
        #expect(url.absoluteString == "sms:+900000000000&body=%C5%9Ei%C5%9Fli%20%C4%B1%C4%9F")
    }
}
