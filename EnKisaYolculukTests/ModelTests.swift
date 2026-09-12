import Foundation
import SwiftUI
import Testing
@testable import EnKisaYolculuk

@Suite("Station, Line, Segment")
struct ModelTests {

    @Test("A station with no complex is its own transfer group")
    func transferGroupDefaultsToID() {
        let station = Station(id: "abc", name: "ABC")
        #expect(station.transferGroup == "abc")
        #expect(station.complexId == nil)
    }

    @Test("A station in a complex reports the complex as its transfer group")
    func transferGroupUsesComplex() {
        let station = Station(id: "abc", name: "ABC", complexId: "cx_x")
        #expect(station.transferGroup == "cx_x")
    }

    @Test("Stations round-trip through Codable")
    func stationCodableRoundTrip() throws {
        let original = Station(id: "s", name: "Ş", complexId: "cx", latitude: 41.0, longitude: 29.0)
        let decoded = try JSONDecoder().decode(
            Station.self, from: try JSONEncoder().encode(original)
        )
        #expect(decoded == original)
    }

    @Test("Optional station fields may be absent")
    func stationDecodesWithoutOptionals() throws {
        let decoded = try JSONDecoder().decode(
            Station.self, from: Data(#"{"id":"x","name":"X"}"#.utf8)
        )
        #expect(decoded.complexId == nil)
        #expect(decoded.latitude == nil)
        #expect(decoded.longitude == nil)
    }

    @Test("Segment minutes decode from both whole numbers and decimals")
    func segmentMinutesAreDouble() throws {
        let whole = try JSONDecoder().decode(
            Segment.self, from: Data(#"{"line":"L","from":"a","to":"b","minutes":3}"#.utf8)
        )
        let half = try JSONDecoder().decode(
            Segment.self, from: Data(#"{"line":"L","from":"a","to":"b","minutes":2.5}"#.utf8)
        )
        #expect(whole.minutes == 3)
        #expect(half.minutes == 2.5)
    }

    @Test("Lines keep an optional colour")
    func lineColourIsOptional() throws {
        let bare = try JSONDecoder().decode(
            Line.self, from: Data(#"{"id":"L","name":"L"}"#.utf8)
        )
        #expect(bare.colorHex == nil)
    }
}

@Suite("Minute formatting")
struct FormattingTests {

    @Test("Whole minutes print without a decimal", arguments: [
        (0.0, "0"), (1.0, "1"), (10.0, "10"), (72.0, "72"), (123.0, "123"),
    ])
    func wholeMinutes(value: Double, expected: String) {
        #expect(formatMinutes(value) == expected)
    }

    @Test("Half minutes print with a Turkish decimal comma", arguments: [
        (2.5, "2,5"), (0.5, "0,5"), (17.5, "17,5"), (99.5, "99,5"),
    ])
    func halfMinutes(value: Double, expected: String) {
        #expect(formatMinutes(value) == expected)
    }

    @Test("Values are rounded to one decimal place")
    func roundsToOneDecimal() {
        #expect(formatMinutes(2.04) == "2")
        #expect(formatMinutes(2.06) == "2,1")
        // Floating-point sums of halves stay exact, so this stays clean.
        #expect(formatMinutes(2.5 + 2.5 + 2.5) == "7,5")
    }
}

@Suite("Line colour parsing")
struct LineColourTests {

    @Test("Valid hex values parse", arguments: ["#FF0000", "ff0000", "#00A9E0", "00a9e0"])
    func validHex(hex: String) {
        // Parsing must not trap; the concrete Color value is not asserted
        // because SwiftUI does not expose components portably.
        _ = Color(lineHex: hex)
    }

    @Test("Malformed or missing hex falls back instead of crashing",
          arguments: [nil, "", "#12345", "#GGGGGG", "not a colour", "#1234567"])
    func invalidHexFallsBack(hex: String?) {
        _ = Color(lineHex: hex)
    }
}
