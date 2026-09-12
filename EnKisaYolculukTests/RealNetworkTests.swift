import Foundation
import Testing
@testable import EnKisaYolculuk

/// End-to-end checks against the **shipped** `network.json`.
///
/// Unlike the fixture suites, these assert the data the app actually loads:
/// every number below was derived by hand from `Data/source/lines.txt`.
@Suite("Shipped network")
struct RealNetworkTests {

    let network: MetroNetwork
    let graph: LineExpandedGraph
    let service: RouteService

    init() throws {
        network = try NetworkLoader.load()
        graph = LineExpandedGraph(network: network)
        service = RouteService(network: network)
    }

    private func transferMinutes(
        _ a: StationID, _ lineA: LineID, _ b: StationID, _ lineB: LineID
    ) -> Double? {
        guard let from = graph.platforms(at: a).first(where: { graph.node(at: $0).line == lineA }),
              let to = graph.platforms(at: b).first(where: { graph.node(at: $0).line == lineB })
        else { return nil }
        return graph.adjacency[from].first { $0.isTransfer && $0.to == to }?.minutes
    }

    private func linesServing(_ station: StationID) -> Set<LineID> {
        Set(graph.platforms(at: station).map { graph.node(at: $0).line })
    }

    private func fastest(_ from: StationID, _ to: StationID) throws -> Route {
        try #require(try service.routes(from: from, to: to)
            .first { $0.criteria.contains(.fastest) })
    }

    // MARK: - Shape

    @Test("The shipped data is the size we expect")
    func shape() {
        #expect(network.stations.count == 307)
        #expect(network.segments.count == 329)
        #expect(network.lines.count == 22)
        #expect(network.transferPenaltyMinutes == 10)
        #expect(network.customTransferPenalties.count == 28)
    }

    @Test("The shipped data validates")
    func validates() throws {
        try network.validate()
    }

    @Test("Every line in the data actually has segments")
    func noEmptyLines() {
        let used = Set(network.segments.map(\.line))
        for line in network.lines {
            #expect(used.contains(line.id), "line '\(line.id)' has no segments")
        }
    }

    @Test("Every station is served by at least one line")
    func noOrphanStations() {
        for station in network.stations {
            #expect(!linesServing(station.id).isEmpty, "'\(station.name)' is on no line")
        }
    }

    @Test("No station id appears twice and no segment is degenerate")
    func structuralSanity() {
        #expect(Set(network.stations.map(\.id)).count == network.stations.count)
        #expect(Set(network.lines.map(\.id)).count == network.lines.count)
        #expect(network.segments.allSatisfy { $0.from != $0.to })
        #expect(network.segments.allSatisfy { $0.minutes >= 0 })
    }

    // MARK: - Travel times

    @Test("Fractional tram times survive as halves")
    func tramHalfMinutes() throws {
        let route = try fastest("gulhane", "sultanahmet")
        #expect(route.totalMinutes == 2.5)
        #expect(route.totalMinutesText == "2,5")
    }

    @Test("Per-line exceptional hop times are applied", arguments: [
        ("levent", "bogazici_universitesi_hisarustu", 7.0, 3),      // M6, 3 min final hop
        ("gayrettepe", "istanbul_havalimani", 26.0, 6),             // M11, 6 min airport hop
        ("kurtkoy", "sabiha_gokcen_havalimani", 4.0, 1),            // M4, 4 min final hop
    ])
    func specialHopTimes(from: StationID, to: StationID, minutes: Double, stops: Int) throws {
        let route = try fastest(from, to)
        #expect(route.totalMinutes == minutes)
        #expect(route.stopCount == stops)
    }

    // MARK: - Transfer penalties

    @Test("Ordinary interchanges cost the global penalty", arguments: [
        ("ayrilik_cesmesi", "M4", "Marmaray"),
        ("uskudar", "M5", "Marmaray"),
        ("bostanci", "M8", "Marmaray"),
        ("halkali", "M11", "Marmaray"),
        ("sirkeci", "T1", "Marmaray"),
        ("yenikapi", "M2", "Marmaray"),
        ("levent", "M2", "M6"),
        ("kozyatagi", "M4", "M8"),
    ])
    func defaultPenalty(station: StationID, lineA: LineID, lineB: LineID) {
        #expect(transferMinutes(station, lineA, station, lineB) == 10)
    }

    @Test("Declared walking transfers cost 15 minutes", arguments: [
        ("bakirkoy", "Marmaray", "ozgurluk_meydani", "M3"),
        ("zincirlikuyu", "Metrobüs", "gayrettepe", "M2"),
        ("zincirlikuyu", "Metrobüs", "gayrettepe", "M11"),
        ("uzuncayir", "Metrobüs", "unalan", "M4"),
        ("mecidiyekoy_metrobus", "Metrobüs", "sisli_mecidiyekoy", "M2"),
        ("mecidiyekoy_metrobus", "Metrobüs", "mecidiyekoy", "M7"),
        ("cevizlibag", "Metrobüs", "cevizlibag_aoy", "T1"),
        ("sirinevler", "Metrobüs", "atakoy_sirinevler", "M1A"),
        ("florya_metrobus", "Metrobüs", "florya", "Marmaray"),
        ("sogutlucesme_metrobus", "Metrobüs", "sogutlucesme", "Marmaray"),
    ])
    func walkingPenalty(a: StationID, lineA: LineID, b: StationID, lineB: LineID) {
        #expect(transferMinutes(a, lineA, b, lineB) == 15)
        #expect(transferMinutes(b, lineB, a, lineA) == 15, "asymmetric penalty")
    }

    @Test("Every declared override is 15 minutes and resolves to a real edge")
    func overridesAreRealised() throws {
        for override in network.customTransferPenalties {
            #expect(override.minutes == 15)
            let (from, to) = try #require(override.endpoints)
            #expect(transferMinutes(from.station, from.line, to.station, to.line) == 15,
                    "override \(from) ↔ \(to) did not reach the graph")
        }
    }

    // MARK: - Same name, different place

    @Test("Look-alike stations are not linked", arguments: [
        ("goztepe_marmaray", "Marmaray", "goztepe", "M4"),
        ("maltepe_marmaray", "Marmaray", "maltepe", "M4"),
        ("kartal_marmaray", "Marmaray", "kartal", "M4"),
        ("pendik_marmaray", "Marmaray", "pendik", "M4"),
        ("kucukyali_marmaray", "Marmaray", "kucukyali", "M4"),
        ("yenimahalle_marmaray", "Marmaray", "yenimahalle", "M3"),
        ("cumhuriyet_mahallesi_metrobus", "Metrobüs", "cumhuriyet_mahallesi", "T4"),
        ("acibadem_metrobus", "Metrobüs", "acibadem", "M4"),
    ])
    func lookAlikesStaySeparate(a: StationID, lineA: LineID, b: StationID, lineB: LineID) {
        #expect(transferMinutes(a, lineA, b, lineB) == nil)
        #expect(linesServing(a) == [lineA], "\(a) should serve only \(lineA)")
    }

    @Test("Split stations keep their official name")
    func splitStationsKeepNames() throws {
        for (split, original) in [
            ("goztepe_marmaray", "goztepe"), ("maltepe_marmaray", "maltepe"),
            ("acibadem_metrobus", "acibadem"), ("mecidiyekoy_metrobus", "mecidiyekoy"),
        ] {
            let a = try #require(network.station(split))
            let b = try #require(network.station(original))
            #expect(a.name == b.name, "split station was renamed")
            #expect(a.id != b.id)
        }
    }

    @Test("M9 Ataköy meets Marmaray, never M1A Ataköy-Şirinevler")
    func atakoyIsNotSirinevler() {
        #expect(linesServing("atakoy") == ["M9", "Marmaray"])
        #expect(transferMinutes("atakoy", "M9", "atakoy_sirinevler", "M1A") == nil)
    }

    @Test("Halkalı meets Marmaray, never M9 Halkalı Caddesi")
    func halkaliIsNotHalkaliCaddesi() {
        #expect(linesServing("halkali") == ["M11", "Marmaray"])
        #expect(transferMinutes("halkali", "M11", "halkali_caddesi", "M9") == nil)
    }

    @Test("Names shared by two stations are disambiguated in the picker")
    func ambiguousNamesAreQualified() {
        let duplicated = Dictionary(grouping: network.stations, by: \.name)
            .filter { $0.value.count > 1 }
        #expect(!duplicated.isEmpty, "the real data does contain shared names")
        let labels = network.pickerEntries.map(\.label)
        #expect(Set(labels).count == labels.count, "two picker rows read identically")
    }

    // MARK: - Complexes

    @Test("Interchanges split across two names are linked", arguments: [
        ("mecidiyekoy", "sisli_mecidiyekoy"),
        ("incirli", "bakirkoy_incirli"),
        ("kayasehir", "kayasehir_merkez"),
        ("olimpiyat", "olimpiyatkoy"),
        ("bakirkoy", "ozgurluk_meydani"),
    ])
    func complexesAreLinked(a: StationID, b: StationID) throws {
        let sa = try #require(network.station(a))
        let sb = try #require(network.station(b))
        #expect(sa.transferGroup == sb.transferGroup)
        #expect(sa.name != sb.name, "both official names must be preserved")
    }

    // MARK: - Known journeys

    @Test("Marmaray joins the two sides of the city")
    func crossBosphorus() throws {
        let route = try fastest("kadikoy", "taksim")
        #expect(route.legs.map(\.line.id) == ["M4", "Marmaray", "M2"])
        #expect(route.totalMinutes == 39)
        #expect(route.transferCount == 2)
    }

    @Test("The M1A/M1B trunk is free but a real branch change is not")
    func trunkAndBranch() throws {
        #expect(try fastest("yenikapi", "otogar").transferCount == 0)
        let fork = try fastest("terazidere", "esenler")
        #expect(fork.transferCount == 1)
        #expect(fork.totalMinutes == 14)
    }

    @Test("The 15-minute walk is what makes Yeşilköy → Haznedar cost 28")
    func walkChangesTheAnswer() throws {
        let route = try fastest("yesilkoy", "haznedar")
        #expect(route.totalMinutes == 28)   // 9 ride + 15 walk + 4 ride
    }

    @Test("A journey starting at a Metrobüs stop reports the walk in")
    func metrobusWalkIn() throws {
        let route = try fastest("zincirlikuyu", "osmanbey")
        #expect(route.origin.id == "zincirlikuyu")
        #expect(route.legs.first?.boarding.id == "gayrettepe")
        #expect(route.leadingWalkMinutes == 15)
        #expect(route.totalMinutes == 19)
    }

    @Test("A walk endpoint is labelled with its OWN lines, not the line ridden")
    func walkEndpointKeepsItsOwnLines() throws {
        // Zincirlikuyu is a Metrobüs stop; Gayrettepe next door is M2/M11.
        // Labelling the origin with the boarded line put a Metrobüs stop on M2.
        let route = try fastest("zincirlikuyu", "osmanbey")
        #expect(route.origin.id == "zincirlikuyu")
        #expect(route.originLines.map(\.id) == ["Metrobüs"])
        #expect(route.legs.first?.line.id == "M2")
        #expect(!route.originLines.contains { $0.id == "M2" },
                "the origin must not claim the line it only reaches by walking")

        let back = try fastest("osmanbey", "zincirlikuyu")
        #expect(back.destination.id == "zincirlikuyu")
        #expect(back.destinationLines.map(\.id) == ["Metrobüs"])
    }

    @Test("Gayrettepe and Zincirlikuyu are one interchange but two stations")
    func gayrettepeAndZincirlikuyuStaySeparate() throws {
        let gayrettepe = try #require(network.station("gayrettepe"))
        let zincirlikuyu = try #require(network.station("zincirlikuyu"))
        // Linked, so you can change between them…
        #expect(gayrettepe.transferGroup == zincirlikuyu.transferGroup)
        #expect(transferMinutes("zincirlikuyu", "Metrobüs", "gayrettepe", "M2") == 15)
        // …but they are different places on different lines.
        #expect(gayrettepe.id != zincirlikuyu.id)
        #expect(linesServing("zincirlikuyu") == ["Metrobüs"])
        #expect(linesServing("gayrettepe") == ["M11", "M2"])
    }

    @Test("…and the reverse reports the walk out")
    func metrobusWalkOut() throws {
        let route = try fastest("osmanbey", "zincirlikuyu")
        #expect(route.destination.id == "zincirlikuyu")
        #expect(route.trailingWalkMinutes == 15)
    }

    @Test("Direction is named on every leg of a long cross-city trip")
    func directionsAreNamed() throws {
        // Since Marmaray opened, the quickest way across is M1A → Marmaray at
        // Zeytinburnu → M2 at Yenikapı: 12 + 10 + 6 + 10 + 28 = 66, beating the
        // 72 of staying on M1A all the way to Yenikapı.
        let route = try fastest("ataturk_havalimani", "haciosman")
        #expect(route.legs.map(\.line.id) == ["M1A", "Marmaray", "M2"])
        #expect(route.totalMinutes == 66)
        #expect(route.legs[0].direction?.id == "yenikapi")
        #expect(route.legs[2].direction?.id == "haciosman")
        #expect(route.legs.allSatisfy { $0.direction != nil }, "a leg lost its direction")
    }

    @Test("Staying on one line is still the fewest-transfers answer there")
    func fewestTransfersAlternative() throws {
        let route = try #require(try service.routes(from: "ataturk_havalimani", to: "haciosman")
            .first { $0.criteria.contains(.fewestTransfers) })
        #expect(route.legs.map(\.line.id) == ["M1A", "M2"])
        #expect(route.totalMinutes == 72)
        #expect(route.transferCount == 1)
    }

    @Test("F3 is deliberately isolated from everything else")
    func f3IsIsolated() {
        #expect(linesServing("seyrantepe") == ["F3"])
        #expect(network.station("seyrantepe")?.complexId == nil)
        #expect(throws: RouteService.RoutingError.self) {
            _ = try service.routes(from: "seyrantepe", to: "taksim")
        }
    }

    @Test("M11 data notes hold")
    func m11Notes() {
        #expect(network.station("arnavutkoy_hastane") != nil)
        #expect(network.station("arnavutkoy") == nil)
        #expect(!network.stations.contains { $0.name.localizedCaseInsensitiveContains("Terminal 2") })
    }

    /// KNOWN ISSUE, pinned so it cannot drift unnoticed.
    ///
    /// A walk at the end of a journey is a transfer edge, so the search counts
    /// it in `cost.transfers`; the displayed `transferCount` counts vehicle
    /// changes only (`legs.count - 1`). Where the two routes tie on
    /// `cost.transfers`, the card labelled "En Az Aktarma" can therefore show a
    /// *higher* number than the card beside it.
    ///
    /// Reported to the user 2026-09-12. The fix is a product decision:
    /// either count end-walks as transfers on screen, or re-assign the three
    /// labels from the displayed metrics after the search.
    @Test("Displayed transfer count can disagree with the criterion label")
    func transferCountCanDisagreeWithItsLabel() throws {
        let routes = try service.routes(from: "15_temmuz", to: "cevizlibag_aoy")
        let labelled = try #require(routes.first { $0.criteria.contains(.fewestTransfers) })
        let other = try #require(routes.first { !$0.criteria.contains(.fewestTransfers) })

        // Both cost the same number of transfer edges to the search…
        #expect(labelled.cost.transfers == other.cost.transfers)
        // …but the other one ends with a walk, which the display does not
        // count, so it shows fewer transfers than the "fewest transfers" card.
        #expect(other.endsWithWalk)
        #expect(other.transferCount < labelled.transferCount)
    }

    // MARK: - Network-wide invariants

    @Test("Everything except F3 is mutually reachable")
    func connectivity() throws {
        let isolated: Set<StationID> = ["seyrantepe", "vadistanbul"]
        let hub = "yenikapi"
        for station in network.stations where !isolated.contains(station.id) && station.id != hub {
            #expect(throws: Never.self) {
                _ = try service.routes(from: hub, to: station.id)
            }
        }
    }

    @Test("Totals stay self-consistent across a broad sample of journeys")
    func sampledInvariants() throws {
        // Every 17th station against every 23rd — a spread of the network
        // without the cost of all 307².
        let origins = stride(from: 0, to: network.stations.count, by: 17).map { network.stations[$0] }
        let destinations = stride(from: 3, to: network.stations.count, by: 23).map { network.stations[$0] }
        var checked = 0
        for origin in origins {
            for destination in destinations where origin.id != destination.id {
                guard let routes = try? service.routes(from: origin.id, to: destination.id)
                else { continue }
                checked += 1
                #expect(!routes.isEmpty)
                #expect(routes.count <= RouteCriterion.allCases.count)
                #expect(Set(routes.flatMap(\.criteria)).count == routes.flatMap(\.criteria).count,
                        "a criterion was listed twice")
                for route in routes {
                    #expect(route.transferCount == route.legs.count - 1)
                    #expect(route.stopCount == route.legs.reduce(0) { $0 + $1.stopCount })
                    #expect(route.totalMinutes > 0)
                    #expect(route.origin.id == origin.id)
                    #expect(route.destination.id == destination.id)
                }
                // The fastest route must not be slower than any alternative.
                if let quickest = routes.first(where: { $0.criteria.contains(.fastest) }) {
                    #expect(routes.allSatisfy { $0.totalMinutes >= quickest.totalMinutes })
                }
                // The fewest-transfers route must be minimal under the cost the
                // search actually optimised. NOTE: this is `cost.transfers`,
                // not the displayed `transferCount` — see
                // `transferCountCanDisagreeWithItsLabel` below.
                if let fewest = routes.first(where: { $0.criteria.contains(.fewestTransfers) }) {
                    #expect(routes.allSatisfy { $0.cost.transfers >= fewest.cost.transfers })
                }
            }
        }
        #expect(checked > 100, "sample was too small to mean anything")
    }
}
