import Foundation

// Regression net for the routing layer, asserted against the REAL network
// (Data/source/lines.txt -> EnKisaYolculuk/Data/network.json).
// Run with Tools/verify.sh.

let jsonPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "EnKisaYolculuk/Data/network.json"

var failures = 0
func check(_ condition: Bool, _ label: String) {
    print(condition ? "  PASS  \(label)" : "  FAIL  \(label)")
    if !condition { failures += 1 }
}

do {
    let network = try NetworkLoader.load(contentsOf: URL(fileURLWithPath: jsonPath))
    let graph = LineExpandedGraph(network: network)
    let service = RouteService(network: network)
    print("Loaded: \(network.stations.count) stations, \(network.lines.count) lines, "
          + "\(network.segments.count) segments, penalty \(network.transferPenaltyMinutes)m")
    print("Line-expanded graph: \(graph.nodeCount) nodes, \(graph.edgeCount) directed edges\n")

    /// Do the two stations actually share a walkable transfer edge in the graph?
    /// This is the property that matters — complexId is only how it gets there.
    func linked(_ a: StationID, _ b: StationID) -> Bool {
        let targets = Set(graph.platforms(at: b))
        for platform in graph.platforms(at: a) {
            for edge in graph.adjacency[platform] where edge.isTransfer && targets.contains(edge.to) {
                return true
            }
        }
        return false
    }

    /// The weight of the transfer edge between two specific platforms, or nil
    /// when no such edge exists.
    func transferMinutes(_ a: StationID, _ lineA: LineID,
                         _ b: StationID, _ lineB: LineID) -> Double? {
        guard let from = graph.platforms(at: a).first(where: { graph.node(at: $0).line == lineA }),
              let to = graph.platforms(at: b).first(where: { graph.node(at: $0).line == lineB })
        else { return nil }
        for edge in graph.adjacency[from] where edge.isTransfer && edge.to == to {
            return edge.minutes
        }
        return nil
    }

    func linesServing(_ station: StationID) -> Set<LineID> {
        Set(graph.platforms(at: station).map { graph.node(at: $0).line })
    }

    func sameComplex(_ a: StationID, _ b: StationID) -> Bool {
        guard let sa = network.station(a), let sb = network.station(b) else { return false }
        return sa.transferGroup == sb.transferGroup
    }

    print("=== Shape ===")
    check(network.stations.count == 307, "307 unique stations")
    check(network.segments.count == 329, "329 segments")
    check(network.lines.count == 22, "22 lines (M + T + F + Marmaray + Metrobüs)")
    check(network.transferPenaltyMinutes == 10, "global transfer penalty is 10 min")

    print("\n=== Custom transfer penalties ===")
    check(network.customTransferPenalties.count == 28, "28 overrides declared")
    check(network.customTransferPenalties.allSatisfy { $0.minutes == 15 },
          "every override is 15 dk")
    // The declared 15 min walk must actually be the edge weight…
    check(transferMinutes("bakirkoy", "Marmaray", "ozgurluk_meydani", "M3") == 15,
          "Bakırköy(Marmaray) ↔ Özgürlük Meydanı(M3) = 15 dk")
    check(transferMinutes("ozgurluk_meydani", "M3", "bakirkoy", "Marmaray") == 15,
          "…and 15 dk in the reverse direction too")
    // …and it must move the answer, not just sit in the file.
    let walk = try service.routes(from: "yesilkoy", to: "haznedar")[0]
    check(walk.totalMinutes == 28, "Yeşilköy → Haznedar = 9 + 15 + 4 = 28 dk")

    print("\n=== Default penalty still applies elsewhere ===")
    for (label, station, lineA, lineB) in [
        ("Ayrılık Çeşmesi M4 ↔ Marmaray", "ayrilik_cesmesi", "M4", "Marmaray"),
        ("Üsküdar M5 ↔ Marmaray", "uskudar", "M5", "Marmaray"),
        ("Ataköy M9 ↔ Marmaray", "atakoy", "M9", "Marmaray"),
        ("Bostancı M8 ↔ Marmaray", "bostanci", "M8", "Marmaray"),
        ("Halkalı M11 ↔ Marmaray", "halkali", "M11", "Marmaray"),
        ("Sirkeci T1 ↔ Marmaray", "sirkeci", "T1", "Marmaray"),
        ("Kazlıçeşme T6 ↔ Marmaray", "kazlicesme", "T6", "Marmaray"),
        ("Zeytinburnu M1A ↔ Marmaray", "zeytinburnu", "M1A", "Marmaray"),
        ("Yenikapı M2 ↔ Marmaray", "yenikapi", "M2", "Marmaray"),
    ] {
        check(transferMinutes(station, lineA, station, lineB) == 10, "\(label) = 10 dk")
    }

    print("\n=== Metrobüs rail transfers are all 15 dk walks ===")
    let metrobusTransfers: [(String, StationID, StationID, LineID)] = [
        ("Şirinevler → M1A Ataköy-Şirinevler", "sirinevler", "atakoy_sirinevler", "M1A"),
        ("İncirli → M1A Bakırköy-İncirli", "incirli_metrobus", "bakirkoy_incirli", "M1A"),
        ("İncirli → M3 İncirli", "incirli_metrobus", "incirli", "M3"),
        ("Bahçelievler → M1A", "bahcelievler_metrobus", "bahcelievler", "M1A"),
        ("Merter → M1A", "merter_metrobus", "merter", "M1A"),
        ("Yenibosna → M1A", "yenibosna_metrobus", "yenibosna", "M1A"),
        ("Yenibosna → M9", "yenibosna_metrobus", "yenibosna", "M9"),
        ("Zeytinburnu → M1A", "zeytinburnu_metrobus", "zeytinburnu", "M1A"),
        ("Zeytinburnu → T1", "zeytinburnu_metrobus", "zeytinburnu", "T1"),
        ("Cevizlibağ → T1 Cevizlibağ-AÖY", "cevizlibag", "cevizlibag_aoy", "T1"),
        ("Topkapı-Şehit M.C. → T1 Topkapı", "topkapi_sehit_mustafa_cambaz", "topkapi", "T1"),
        ("Topkapı-Şehit M.C. → T4 Topkapı", "topkapi_sehit_mustafa_cambaz", "topkapi", "T4"),
        ("Edirnekapı → T4", "edirnekapi_metrobus", "edirnekapi", "T4"),
        ("Ayvansaray-Eyüpsultan → T5 Ayvansaray", "ayvansaray_eyupsultan", "ayvansaray", "T5"),
        ("Çağlayan → M7", "caglayan_metrobus", "caglayan", "M7"),
        ("Mecidiyeköy → M2 Şişli-Mecidiyeköy", "mecidiyekoy_metrobus", "sisli_mecidiyekoy", "M2"),
        ("Mecidiyeköy → M7 Mecidiyeköy", "mecidiyekoy_metrobus", "mecidiyekoy", "M7"),
        ("Zincirlikuyu → M2 Gayrettepe", "zincirlikuyu", "gayrettepe", "M2"),
        ("Zincirlikuyu → M11 Gayrettepe", "zincirlikuyu", "gayrettepe", "M11"),
        ("Altunizade → M5", "altunizade_metrobus", "altunizade", "M5"),
        ("Uzunçayır → M4 Ünalan", "uzuncayir", "unalan", "M4"),
        ("Küçükçekmece → Marmaray", "kucukcekmece_metrobus", "kucukcekmece", "Marmaray"),
        ("Söğütlüçeşme → Marmaray", "sogutlucesme_metrobus", "sogutlucesme", "Marmaray"),
        ("Bayrampaşa-Maltepe → M1A", "bayrampasa_maltepe_metrobus", "bayrampasa_maltepe", "M1A"),
        ("Bayrampaşa-Maltepe → M1B", "bayrampasa_maltepe_metrobus", "bayrampasa_maltepe", "M1B"),
        ("Florya → Marmaray", "florya_metrobus", "florya", "Marmaray"),
    ]
    for (label, metrobus, rail, line) in metrobusTransfers {
        check(transferMinutes(metrobus, "Metrobüs", rail, line) == 15, "\(label) = 15 dk")
    }

    print("\n=== Metrobüs look-alikes with NO transfer ===")
    for (label, metrobusID, otherID, otherLine) in [
        ("Cumhuriyet Mahallesi (T4)", "cumhuriyet_mahallesi_metrobus", "cumhuriyet_mahallesi", "T4"),
        ("Acıbadem (M4)", "acibadem_metrobus", "acibadem", "M4"),
    ] {
        check(linesServing(metrobusID) == ["Metrobüs"], "Metrobüs \(label) is Metrobüs-only")
        check(transferMinutes(metrobusID, "Metrobüs", otherID, otherLine) == nil,
              "…and has NO transfer to \(label)")
    }

    print("\n=== Marmaray look-alikes stay separate ===")
    // Same official name as a metro station, different physical place.
    for (label, marmarayID, metroID, metroLine) in [
        ("Göztepe", "goztepe_marmaray", "goztepe", "M4"),
        ("Maltepe", "maltepe_marmaray", "maltepe", "M4"),
        ("Kartal", "kartal_marmaray", "kartal", "M4"),
        ("Pendik", "pendik_marmaray", "pendik", "M4"),
        ("Küçükyalı", "kucukyali_marmaray", "kucukyali", "M4"),
        ("Yenimahalle", "yenimahalle_marmaray", "yenimahalle", "M3"),
    ] {
        check(linesServing(marmarayID) == ["Marmaray"], "Marmaray \(label) is Marmaray-only")
        check(network.station(marmarayID)?.name == network.station(metroID)?.name,
              "…keeps the official name '\(label)'")
        check(transferMinutes(marmarayID, "Marmaray", metroID, metroLine) == nil,
              "…and has NO transfer to \(metroLine) \(label)")
    }

    print("\n=== Double travel times ===")
    // Tram hops are 2.5 min; the schema must keep the halves exactly.
    let tramHop = network.segments.first { $0.line == "T1" }!
    check(tramHop.minutes == 2.5, "T1 hop is exactly 2.5 min (not rounded)")
    let tram = try service.routes(from: "gulhane", to: "sultanahmet")[0]
    check(tram.totalMinutes == 2.5, "Gülhane → Sultanahmet = 2,5 dk")
    check(formatMinutes(2.5) == "2,5" && formatMinutes(72) == "72", "minute formatting")
    // Existing metro times must be unchanged by the widening.
    let m4 = try service.routes(from: "kurtkoy", to: "sabiha_gokcen_havalimani")[0]
    check(m4.totalMinutes == 4, "M4 Kurtköy → Sabiha Gökçen still 4 dk")

    print("\n=== VERIFIED SAME complex (must be linked) ===")
    let same: [(String, StationID, StationID)] = [
        ("Mecidiyeköy / Şişli-Mecidiyeköy", "mecidiyekoy", "sisli_mecidiyekoy"),
        ("İncirli / Bakırköy-İncirli", "incirli", "bakirkoy_incirli"),
        ("Kayaşehir / Kayaşehir Merkez", "kayasehir", "kayasehir_merkez"),
        ("Olimpiyat / Olimpiyatköy", "olimpiyat", "olimpiyatkoy"),
    ]
    for (label, a, b) in same {
        check(sameComplex(a, b) && linked(a, b), "\(label) — same complex AND linked")
        // The modelling rule: linked, but NOT merged into one station.
        check(network.station(a)!.name != network.station(b)!.name,
              "\(label) — both official names preserved")
    }

    print("\n=== VERIFIED DISTINCT (must NOT be linked) ===")
    let distinct: [(String, StationID, StationID)] = [
        ("Halkalı / Halkalı Caddesi", "halkali", "halkali_caddesi"),
        ("Ataköy / Ataköy-Şirinevler", "atakoy", "atakoy_sirinevler"),
        ("Levent / 4.Levent", "levent", "4_levent"),
        ("Maltepe / Bayrampaşa-Maltepe", "maltepe", "bayrampasa_maltepe"),
        ("Göztepe / Göztepe Mahallesi", "goztepe", "goztepe_mahallesi"),
        ("Veysel Karani / V.K.-Akşemsettin", "veysel_karani", "veysel_karani_aksemsettin"),
        ("Çakmak / Fevzi Çakmak-Hastane", "cakmak", "fevzi_cakmak_hastane"),
        ("Halkalı / Halkalı Stadı", "halkali", "halkali_stadi"),
        ("Sancaktepe / Sancaktepe Ş.H.", "sancaktepe", "sancaktepe_sehir_hastanesi"),
        ("Şehir Hastanesi / Sancaktepe Ş.H.", "sehir_hastanesi", "sancaktepe_sehir_hastanesi"),
        ("Topkapı / Topkapı-Ulubatlı", "topkapi", "topkapi_ulubatli"),
        ("Karadeniz / Karadeniz Mahallesi", "karadeniz", "karadeniz_mahallesi"),
        ("Soğanlı / Soğanlık", "soganli", "soganlik"),
    ]
    for (label, a, b) in distinct {
        check(!sameComplex(a, b) && !linked(a, b), "\(label) — separate AND not linked")
    }

    print("\n=== The two misleading cases ===")
    // M9 meets M1A at Yenibosna, never at Ataköy.
    check(linked("yenibosna", "yenibosna"), "M9 ↔ M1A linked at Yenibosna")
    // M9's Ataköy meets Marmaray, never M1A's Ataköy-Şirinevler.
    check(linesServing("atakoy") == ["M9", "Marmaray"], "Ataköy serves M9 + Marmaray only")
    check(transferMinutes("atakoy", "M9", "atakoy_sirinevler", "M1A") == nil,
          "…and no edge to M1A Ataköy-Şirinevler")
    // Halkalı meets Marmaray, never M9's Halkalı Caddesi.
    check(linesServing("halkali") == ["M11", "Marmaray"], "Halkalı serves M11 + Marmaray only")
    check(transferMinutes("halkali", "M11", "halkali_caddesi", "M9") == nil,
          "…and no edge to M9 Halkalı Caddesi")

    print("\n=== F3 Seyrantepe is standalone ===")
    let seyrantepeLines = Set(graph.platforms(at: "seyrantepe").map { graph.node(at: $0).line })
    check(seyrantepeLines == ["F3"], "Seyrantepe serves only F3")
    check(network.station("seyrantepe")?.complexId == nil, "Seyrantepe has no complex")
    do {
        _ = try service.routes(from: "seyrantepe", to: "taksim")
        check(false, "Seyrantepe → metro must be unreachable")
    } catch { check(true, "Seyrantepe → Taksim unreachable (no metro transfer)") }

    print("\n=== M11 data notes ===")
    check(network.station("arnavutkoy_hastane") != nil, "Arnavutköy Hastane is ONE station")
    check(network.station("arnavutkoy") == nil && network.station("hastane") == nil,
          "not split into Arnavutköy + Hastane")
    check(!network.stations.contains { $0.name.localizedCaseInsensitiveContains("Terminal 2") },
          "Terminal 2 not added (not an active stop)")

    print("\n=== Complex routing actually works ===")
    // M7 → M2 is only possible through the Mecidiyeköy complex.
    let crossComplex = try service.routes(from: "yildiz", to: "osmanbey")
        .first { $0.criteria.contains(.fastest) }!
    check(crossComplex.legs.map(\.line.id) == ["M7", "M2"], "Yıldız → Osmanbey rides M7 then M2")
    check(crossComplex.transferCount == 1, "…with exactly 1 transfer")
    check(crossComplex.legs[0].alighting.id == "mecidiyekoy"
          && crossComplex.legs[1].boarding.id == "sisli_mecidiyekoy",
          "…changing Mecidiyeköy → Şişli-Mecidiyeköy (names kept distinct)")

    print("\n=== M1A / M1B shared trunk (unchanged) ===")
    let trunk = try service.routes(from: "yenikapi", to: "otogar")[0]
    check(trunk.transferCount == 0, "Yenikapı → Otogar = 0 aktarma")
    let fork = try service.routes(from: "terazidere", to: "esenler")[0]
    check(fork.transferCount == 1 && fork.totalMinutes == 14, "Terazidere → Esenler = 1 aktarma / 14 dk")

    print("\n=== Walk-in / walk-out journeys ===")
    // Starting at a Metrobüs stop means walking to the rail station first;
    // that walk is priced, so it must also be visible.
    let walkIn = try service.routes(from: "zincirlikuyu", to: "osmanbey")[0]
    check(walkIn.origin.id == "zincirlikuyu", "origin stays Zincirlikuyu")
    check(walkIn.legs.first?.boarding.id == "gayrettepe", "boarding is Gayrettepe")
    check(walkIn.leadingWalkMinutes == 15, "15 dk leading walk reported")
    check(walkIn.totalMinutes == 19, "total 15 + 4 = 19 dk")
    let walkOut = try service.routes(from: "osmanbey", to: "zincirlikuyu")[0]
    check(walkOut.trailingWalkMinutes == 15, "15 dk trailing walk reported")
    check(walkOut.destination.id == "zincirlikuyu", "destination stays Zincirlikuyu")
    // A plain journey has neither.
    let plain = try service.routes(from: "yenikapi", to: "otogar")[0]
    check(!plain.startsWithWalk && !plain.endsWithWalk, "ordinary route has no walk legs")

    print("\n=== Marmaray joins the two sides ===")
    let crossing = try service.routes(from: "kadikoy", to: "taksim")
        .first { $0.criteria.contains(.fastest) }!
    check(crossing.legs.map(\.line.id) == ["M4", "Marmaray", "M2"],
          "Kadıköy → Taksim rides M4 → Marmaray → M2")
    check(crossing.totalMinutes == 39 && crossing.transferCount == 2,
          "Kadıköy → Taksim = 39 dk / 2 aktarma")
    // F3 is the only thing left that nothing can reach.
    do {
        _ = try service.routes(from: "seyrantepe", to: "kadikoy")
        check(false, "F3 must still be unreachable")
    } catch { check(true, "F3 still isolated (deliberate)") }

    print("")
    if failures == 0 {
        print("ALL CHECKS PASSED")
    } else {
        print("\(failures) CHECK(S) FAILED")
        exit(1)
    }
} catch {
    print("FATAL: \(error.localizedDescription)")
    exit(1)
}
