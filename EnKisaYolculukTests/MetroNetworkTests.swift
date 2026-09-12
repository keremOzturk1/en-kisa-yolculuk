import Foundation
import Testing
@testable import EnKisaYolculuk

@Suite("MetroNetwork validation")
struct MetroNetworkValidationTests {

    /// Builds a network JSON with one field swapped out, so each test changes
    /// exactly the thing it is about.
    private func json(
        stations: String = #"{"id":"a","name":"A"},{"id":"b","name":"B"}"#,
        lines: String = #"{"id":"L","name":"L"}"#,
        segments: String = #"{"line":"L","from":"a","to":"b","minutes":2}"#,
        penalty: String = "10",
        overrides: String = "[]"
    ) -> String {
        """
        {"version":1,"transferPenaltyMinutes":\(penalty),
         "stations":[\(stations)],"lines":[\(lines)],"segments":[\(segments)],
         "customTransferPenalties":\(overrides)}
        """
    }

    private func expectValidationFailure(
        _ networkJSON: String,
        _ matches: (MetroNetwork.ValidationError) -> Bool
    ) throws {
        let network = try Fixture.network(networkJSON)
        do {
            try network.validate()
            Issue.record("validate() accepted an invalid network")
        } catch let error as MetroNetwork.ValidationError {
            #expect(matches(error), "unexpected error: \(error)")
            #expect(error.errorDescription?.isEmpty == false, "error has no message")
        }
    }

    @Test("A well-formed network validates")
    func validNetworkPasses() throws {
        try #require(try Fixture.network(json())).validate()
    }

    @Test("Duplicate station ids are rejected")
    func duplicateStation() throws {
        try expectValidationFailure(
            json(stations: #"{"id":"a","name":"A"},{"id":"a","name":"A again"}"#)
        ) { if case .duplicateStationID("a") = $0 { true } else { false } }
    }

    @Test("Duplicate line ids are rejected")
    func duplicateLine() throws {
        try expectValidationFailure(
            json(lines: #"{"id":"L","name":"L"},{"id":"L","name":"L2"}"#)
        ) { if case .duplicateLineID("L") = $0 { true } else { false } }
    }

    @Test("A segment naming an unknown station is rejected")
    func unknownStation() throws {
        try expectValidationFailure(
            json(segments: #"{"line":"L","from":"a","to":"ghost","minutes":2}"#)
        ) { if case .unknownStation("ghost", _) = $0 { true } else { false } }
    }

    @Test("A segment naming an unknown line is rejected")
    func unknownLine() throws {
        try expectValidationFailure(
            json(segments: #"{"line":"Nope","from":"a","to":"b","minutes":2}"#)
        ) { if case .unknownLine("Nope") = $0 { true } else { false } }
    }

    @Test("Negative travel time is rejected — Dijkstra requires non-negative weights")
    func negativeTravelTime() throws {
        try expectValidationFailure(
            json(segments: #"{"line":"L","from":"a","to":"b","minutes":-1}"#)
        ) { if case .negativeTravelTime = $0 { true } else { false } }
    }

    @Test("A segment from a station to itself is rejected")
    func selfLoop() throws {
        try expectValidationFailure(
            json(segments: #"{"line":"L","from":"a","to":"a","minutes":2}"#)
        ) { if case .selfLoop = $0 { true } else { false } }
    }

    @Test("A negative global penalty is rejected")
    func negativePenalty() throws {
        try expectValidationFailure(json(penalty: "-5")) {
            if case .negativeTransferPenalty = $0 { true } else { false }
        }
    }

    @Test("Zero travel time is allowed")
    func zeroTravelTimeIsFine() throws {
        try #require(try Fixture.network(
            json(segments: #"{"line":"L","from":"a","to":"b","minutes":0}"#)
        )).validate()
    }

    // MARK: - Override validation

    @Test("An override naming no station is rejected")
    func overrideWithoutStation() throws {
        try expectValidationFailure(
            json(overrides: #"[{"lineA":"L","lineB":"L","minutes":5}]"#)
        ) { if case .overrideNamesNoStation = $0 { true } else { false } }
    }

    @Test("An override naming an unknown station is rejected")
    func overrideUnknownStation() throws {
        try expectValidationFailure(
            json(overrides: #"[{"stationId":"ghost","lineA":"L","lineB":"L","minutes":5}]"#)
        ) { if case .overrideUnknownStation("ghost") = $0 { true } else { false } }
    }

    @Test("An override naming an unknown line is rejected")
    func overrideUnknownLine() throws {
        try expectValidationFailure(
            json(overrides: #"[{"stationId":"a","lineA":"Nope","lineB":"L","minutes":5}]"#)
        ) { if case .overrideUnknownLine("Nope") = $0 { true } else { false } }
    }

    @Test("An override with negative minutes is rejected")
    func overrideNegative() throws {
        try expectValidationFailure(
            json(overrides: #"[{"stationId":"a","lineA":"L","lineB":"L","minutes":-3}]"#)
        ) { if case .overrideNegativeMinutes = $0 { true } else { false } }
    }

    @Test("customTransferPenalties may be absent entirely")
    func overridesAreOptional() throws {
        let network = try Fixture.network("""
        {"version":1,"transferPenaltyMinutes":10,
         "stations":[{"id":"a","name":"A"},{"id":"b","name":"B"}],
         "lines":[{"id":"L","name":"L"}],
         "segments":[{"line":"L","from":"a","to":"b","minutes":2}]}
        """)
        try network.validate()
        #expect(network.customTransferPenalties.isEmpty)
    }
}

@Suite("MetroNetwork lookups")
struct MetroNetworkLookupTests {

    @Test("Stations and lines are indexed by id")
    func indexes() throws {
        let network = try Fixture.network(Fixture.linear)
        #expect(network.station("b")?.name == "B")
        #expect(network.line("L1")?.name == "Line One")
        #expect(network.station("nope") == nil)
        #expect(network.line("nope") == nil)
    }

    @Test("Lines serving each station are derived from the segments")
    func lineIDsByStation() throws {
        let network = try Fixture.network(Fixture.divergingCriteria)
        #expect(network.lineIDs(at: "p") == ["X", "Z"])
        #expect(network.lineIDs(at: "q") == ["X", "Y"])
        #expect(network.lineIDs(at: "r") == ["Y", "Z"])
        #expect(network.lineIDs(at: "ghost").isEmpty)
    }

    @Test("Unambiguous names are shown bare")
    func displayNameLeavesUniqueNamesAlone() throws {
        let network = try Fixture.network(Fixture.ambiguousNames)
        let solo = try #require(network.station("solo"))
        #expect(network.displayName(solo) == "Solo")
    }

    @Test("A name shared by two stations is qualified with its lines")
    func displayNameDisambiguates() throws {
        let network = try Fixture.network(Fixture.ambiguousNames)
        let one = try #require(network.station("dup_one"))
        let two = try #require(network.station("dup_two"))
        #expect(network.displayName(one) == "Dup (AA)")
        #expect(network.displayName(two) == "Dup (BB)")
    }

    @Test("Picker entries cover every station and are uniquely labelled")
    func pickerEntriesAreUnique() throws {
        let network = try Fixture.network(Fixture.ambiguousNames)
        let entries = network.pickerEntries
        #expect(entries.count == network.stations.count)
        #expect(Set(entries.map(\.label)).count == entries.count)
    }

    @Test("Stations sort with Turkish-aware collation")
    func turkishSorting() throws {
        let network = try Fixture.network("""
        {"version":1,"transferPenaltyMinutes":10,
         "stations":[{"id":"z","name":"Zeytinburnu"},{"id":"c","name":"Çağlayan"},
                     {"id":"i","name":"İncirli"},{"id":"a","name":"Ataköy"}],
         "lines":[{"id":"L","name":"L"}],
         "segments":[{"line":"L","from":"a","to":"c","minutes":1},
                     {"line":"L","from":"c","to":"i","minutes":1},
                     {"line":"L","from":"i","to":"z","minutes":1}]}
        """)
        #expect(network.stationsSortedByName.map(\.name)
                == ["Ataköy", "Çağlayan", "İncirli", "Zeytinburnu"])
    }
}
