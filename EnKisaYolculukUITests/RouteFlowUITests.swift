import XCTest

/// The journey a real user makes: pick two stations, search, compare the
/// alternatives, open one.
final class RouteFlowUITests: AppUITestCase {

    /// A cross-Bosphorus pair, so the route is guaranteed to involve transfers.
    private let origin = "Kadıköy"
    private let destination = "Taksim"

    private func search(from: String, to: String) {
        waitForPicker()
        choose(from, in: "originPicker")
        choose(to, in: "destinationPicker")
        tapFindRoutes()
    }

    func testSearchProducesAtLeastOneAlternative() {
        search(from: origin, to: destination)
        XCTAssertGreaterThan(routeCards.count, 0, "no route cards were listed")
        XCTAssertLessThanOrEqual(routeCards.count, 3, "more than three alternatives shown")

        // Each card states its minutes, transfers and stops.
        let card = routeCards.firstMatch.label
        XCTAssertTrue(card.contains("dk"), "no duration on the card: \(card)")
        XCTAssertTrue(card.contains("aktarma"), "no transfer count on the card: \(card)")
        XCTAssertTrue(card.contains("durak"), "no stop count on the card: \(card)")
    }

    func testEveryCardCarriesACriterionLabel() {
        search(from: origin, to: destination)
        let criteria = ["En Hızlı", "En Az Aktarma", "En Az Durak"]
        for index in 0..<routeCards.count {
            let label = routeCards.element(boundBy: index).label
            XCTAssertTrue(criteria.contains { label.contains($0) },
                          "card \(index) has no criterion: \(label)")
        }
    }

    func testOpeningARouteShowsItsSteps() {
        search(from: origin, to: destination)
        routeCards.firstMatch.tap()

        // The detail screen leads with the three headline numbers.
        XCTAssertTrue(app.staticTexts["dakika"].waitForExistence(timeout: Self.uiTimeout),
                      "the detail summary is missing")
        XCTAssertTrue(app.staticTexts["aktarma"].exists)
        XCTAssertTrue(app.staticTexts["durak"].exists)

        // …and names both ends of the journey.
        XCTAssertTrue(app.staticTexts[origin].exists, "origin missing from the steps")
        XCTAssertTrue(app.staticTexts[destination].exists, "destination missing from the steps")

        // Each ride states the terminus it heads towards.
        let direction = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'yönü'")
        ).firstMatch
        XCTAssertTrue(direction.exists, "no direction shown on any leg")
    }

    func testDetailScreenNamesBothLinesAtATransfer() {
        search(from: origin, to: destination)
        routeCards.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["dakika"].waitForExistence(timeout: Self.uiTimeout))

        // Kadıköy → Taksim needs M4 → Marmaray → M2, so a transfer must appear,
        // rendered as "(X → Y)".
        let transfer = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '→'")
        ).firstMatch
        XCTAssertTrue(transfer.exists, "the transfer does not name both lines")
    }

    func testSwapReversesTheJourney() {
        waitForPicker()
        choose(origin, in: "originPicker")
        choose(destination, in: "destinationPicker")

        app.buttons["swapEndpoints"].tap()

        let originRow = app.buttons.matching(identifier: "originPicker").firstMatch
        XCTAssertTrue(originRow.waitForExistence(timeout: Self.uiTimeout))
        XCTAssertTrue(originRow.label.contains(destination),
                      "origin did not become \(destination): \(originRow.label)")

        tapFindRoutes()
        XCTAssertGreaterThan(routeCards.count, 0)
    }

    func testCanGoBackAndSearchAgain() {
        search(from: origin, to: destination)
        app.navigationBars["Alternatifler"].buttons.firstMatch.tap()

        XCTAssertTrue(app.buttons["findRoutes"].waitForExistence(timeout: Self.uiTimeout),
                      "did not return to the picker")

        choose("Üsküdar", in: "destinationPicker")
        tapFindRoutes()
        XCTAssertGreaterThan(routeCards.count, 0, "the second search produced nothing")
    }

    /// F3 (Seyrantepe–Vadistanbul) is deliberately cut off from the rest of the
    /// network, so this pair must fail visibly rather than showing an empty
    /// results screen.
    func testUnreachablePairReportsAnErrorAndStaysPut() {
        waitForPicker()
        choose("Vadistanbul", in: "originPicker")
        choose(destination, in: "destinationPicker")

        app.buttons["findRoutes"].tap()

        let error = app.staticTexts["routingError"]
        XCTAssertTrue(error.waitForExistence(timeout: Self.uiTimeout),
                      "no error shown for an unreachable pair")
        XCTAssertTrue(error.label.contains("bulunamadı"), "unexpected message: \(error.label)")
        XCTAssertFalse(app.navigationBars["Alternatifler"].exists,
                       "navigated to results despite having none")
    }

    /// Two stations that share a name must be distinguishable in the list.
    func testAmbiguousStationNamesAreQualified() {
        waitForPicker()
        openStationList("originPicker")

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.uiTimeout))
        search.tap()
        // "Göztepe" is a stop on both M4 and Marmaray, and they are different
        // places, so the rows must name their lines rather than read alike.
        search.typeText("Göztepe")

        let rows = app.buttons.matching(identifier: "stationOption")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.uiTimeout),
                      "search found nothing for Göztepe")

        let labels = (0..<rows.count).map { rows.element(boundBy: $0).label }
        let plain = labels.filter { $0.hasPrefix("Göztepe") }
        XCTAssertGreaterThanOrEqual(plain.count, 2, "expected both Göztepe stations: \(labels)")
        XCTAssertEqual(Set(plain).count, plain.count, "two rows read identically: \(plain)")
        XCTAssertTrue(plain.contains { $0.contains("(M4)") }, "M4 Göztepe not qualified: \(plain)")
        XCTAssertTrue(plain.contains { $0.contains("(Marmaray)") },
                      "Marmaray Göztepe not qualified: \(plain)")
    }

    /// Searching must be diacritic-insensitive, or Turkish names are painful
    /// to find on an English keyboard.
    func testSearchIgnoresDiacritics() {
        waitForPicker()
        openStationList("originPicker")

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.uiTimeout))
        search.tap()
        search.typeText("uskudar")

        let match = app.buttons.matching(identifier: "stationOption")
            .containing(NSPredicate(format: "label BEGINSWITH 'Üsküdar'")).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: Self.uiTimeout),
                      "'uskudar' did not find 'Üsküdar'")
    }
}
