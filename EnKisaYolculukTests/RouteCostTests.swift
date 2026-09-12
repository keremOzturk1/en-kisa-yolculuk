import Foundation
import Testing
@testable import EnKisaYolculuk

@Suite("PathCost")
struct PathCostTests {

    @Test("Zero is the identity")
    func zero() {
        #expect(PathCost.zero.minutes == 0)
        #expect(PathCost.zero.transfers == 0)
        #expect(PathCost.zero.stops == 0)
    }

    @Test("A ride adds minutes and a stop")
    func addingRide() {
        let cost = PathCost.zero.adding(minutes: 2.5, isTransfer: false)
        #expect(cost.minutes == 2.5)
        #expect(cost.stops == 1)
        #expect(cost.transfers == 0)
    }

    @Test("A transfer adds minutes and a transfer, never a stop")
    func addingTransfer() {
        let cost = PathCost.zero.adding(minutes: 10, isTransfer: true)
        #expect(cost.minutes == 10)
        #expect(cost.stops == 0)
        #expect(cost.transfers == 1)
    }

    @Test("Costs accumulate exactly across half-minute hops")
    func halfMinutesStayExact() {
        var cost = PathCost.zero
        for _ in 0..<10 { cost = cost.adding(minutes: 2.5, isTransfer: false) }
        // 25 exactly — no epsilon needed, which is why the comparisons below
        // can rely on ==.
        #expect(cost.minutes == 25)
        #expect(cost.stops == 10)
    }
}

@Suite("RouteCriterion ordering")
struct RouteCriterionTests {

    private func cost(_ minutes: Double, _ transfers: Int, _ stops: Int) -> PathCost {
        PathCost(minutes: minutes, transfers: transfers, stops: stops)
    }

    @Test("fastest ranks by time first")
    func fastestPrefersTime() {
        let quick = cost(10, 3, 9)
        let slow = cost(11, 0, 1)
        #expect(RouteCriterion.fastest.isLower(quick, slow))
        #expect(!RouteCriterion.fastest.isLower(slow, quick))
    }

    @Test("fewestTransfers ranks by transfers first, however slow")
    func fewestTransfersPrefersTransfers() {
        let direct = cost(100, 0, 1)
        let quick = cost(10, 1, 2)
        #expect(RouteCriterion.fewestTransfers.isLower(direct, quick))
        #expect(!RouteCriterion.fewestTransfers.isLower(quick, direct))
    }

    @Test("fewestStops ranks by stops first")
    func fewestStopsPrefersStops() {
        let few = cost(100, 5, 2)
        let many = cost(10, 0, 3)
        #expect(RouteCriterion.fewestStops.isLower(few, many))
    }

    @Test("Ties on the leading key fall through to the next one")
    func tieBreaking() {
        // Same time — fastest then prefers fewer transfers.
        #expect(RouteCriterion.fastest.isLower(cost(10, 1, 5), cost(10, 2, 5)))
        // Same time and transfers — then fewer stops.
        #expect(RouteCriterion.fastest.isLower(cost(10, 1, 4), cost(10, 1, 5)))
        // Same transfers — fewestTransfers then prefers less time.
        #expect(RouteCriterion.fewestTransfers.isLower(cost(9, 2, 9), cost(10, 2, 1)))
    }

    @Test("Identical costs are not lower than each other (irreflexive)")
    func identicalCostsAreEqual() {
        for criterion in RouteCriterion.allCases {
            let same = cost(7, 1, 3)
            #expect(!criterion.isLower(same, same))
        }
    }

    @Test("Ordering is a strict weak order over a sample of costs")
    func orderingIsConsistent() {
        let samples = [
            cost(0, 0, 0), cost(10, 0, 1), cost(10, 1, 1), cost(10, 1, 2),
            cost(12.5, 0, 5), cost(12.5, 2, 1), cost(99, 9, 9),
        ]
        for criterion in RouteCriterion.allCases {
            for a in samples {
                for b in samples {
                    // Antisymmetry: never both directions.
                    #expect(!(criterion.isLower(a, b) && criterion.isLower(b, a)))
                }
            }
            // Transitivity over the sorted order.
            let sorted = samples.sorted { criterion.isLower($0, $1) }
            for i in 0..<(sorted.count - 1) {
                #expect(!criterion.isLower(sorted[i + 1], sorted[i]))
            }
        }
    }

    @Test("Every criterion has a label and an icon")
    func presentationMetadata() {
        for criterion in RouteCriterion.allCases {
            #expect(!criterion.title.isEmpty)
            #expect(!criterion.systemImageName.isEmpty)
            #expect(criterion.id == criterion.rawValue)
        }
        #expect(RouteCriterion.allCases.count == 3)
    }
}

@Suite("TransferPenaltyOverride / table")
struct TransferPenaltyTests {

    private func decode(_ json: String) throws -> TransferPenaltyOverride {
        try JSONDecoder().decode(TransferPenaltyOverride.self, from: Data(json.utf8))
    }

    @Test("stationId is shorthand for both endpoints")
    func stationIDShorthand() throws {
        let override = try decode(#"{"stationId":"x","lineA":"A","lineB":"B","minutes":12}"#)
        let endpoints = try #require(override.endpoints)
        #expect(endpoints.0 == PlatformNode(station: "x", line: "A"))
        #expect(endpoints.1 == PlatformNode(station: "x", line: "B"))
    }

    @Test("stationA / stationB describe a transfer spanning two stations")
    func twoStationForm() throws {
        let override = try decode(
            #"{"stationA":"p","lineA":"A","stationB":"q","lineB":"B","minutes":15}"#
        )
        let endpoints = try #require(override.endpoints)
        #expect(endpoints.0 == PlatformNode(station: "p", line: "A"))
        #expect(endpoints.1 == PlatformNode(station: "q", line: "B"))
    }

    @Test("An entry naming no station has no endpoints")
    func noStation() throws {
        let override = try decode(#"{"lineA":"A","lineB":"B","minutes":15}"#)
        #expect(override.endpoints == nil)
    }

    @Test("Lookup is direction-independent")
    func lookupIgnoresDirection() throws {
        let table = TransferPenaltyTable([
            try decode(#"{"stationA":"p","lineA":"A","stationB":"q","lineB":"B","minutes":15}"#)
        ])
        let p = PlatformNode(station: "p", line: "A")
        let q = PlatformNode(station: "q", line: "B")
        #expect(table.minutes(from: p, to: q) == 15)
        #expect(table.minutes(from: q, to: p) == 15)
    }

    @Test("Unrelated pairs fall through to the default")
    func missingPairReturnsNil() throws {
        let table = TransferPenaltyTable([
            try decode(#"{"stationId":"x","lineA":"A","lineB":"B","minutes":15}"#)
        ])
        #expect(table.minutes(from: PlatformNode(station: "x", line: "A"),
                              to: PlatformNode(station: "x", line: "C")) == nil)
        #expect(table.minutes(from: PlatformNode(station: "y", line: "A"),
                              to: PlatformNode(station: "y", line: "B")) == nil)
    }

    @Test("An empty table reports itself empty")
    func emptyTable() {
        let table = TransferPenaltyTable([])
        #expect(table.isEmpty)
        #expect(table.count == 0)
    }

    @Test("Entries with no endpoints are skipped rather than crashing")
    func entriesWithoutEndpointsAreIgnored() throws {
        let table = TransferPenaltyTable([
            try decode(#"{"lineA":"A","lineB":"B","minutes":15}"#)
        ])
        #expect(table.isEmpty)
    }
}
