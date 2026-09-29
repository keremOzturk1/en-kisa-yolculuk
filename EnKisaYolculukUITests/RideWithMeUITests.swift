import XCTest

/// The personal card pinned above the alternatives.
///
/// It is presentation only (CONTEXT §7.3.12), so what needs pinning is not a
/// computation but three placement facts: it is first, it is *not* one of the
/// route cards, and it opens its own screen instead of a step-by-step one.
final class RideWithMeUITests: AppUITestCase {

    private func search() {
        waitForPicker()
        choose("Kadıköy", in: "originPicker")
        choose("Taksim", in: "destinationPicker")
        tapFindRoutes()
    }

    private var rideWithMeCard: XCUIElement {
        app.buttons.matching(identifier: "rideWithMeCard").firstMatch
    }

    func testCardIsPresentAndSitsAboveEveryAlternative() {
        search()

        XCTAssertTrue(rideWithMeCard.waitForExistence(timeout: Self.uiTimeout),
                      "the ride-with-me card was not listed")

        // Above every route card, which is the whole point of it.
        for index in 0..<routeCards.count {
            XCTAssertLessThan(rideWithMeCard.frame.minY,
                              routeCards.element(boundBy: index).frame.minY,
                              "a route card sits above the ride-with-me card")
        }
    }

    /// The identifiers must stay apart: `RouteFlowUITests` counts `routeCard`
    /// and expects at most three, and taps `firstMatch` to reach a route's
    /// steps. Reusing the identifier here breaks both silently.
    func testCardIsNotCountedAsARouteAlternative() {
        search()
        XCTAssertTrue(rideWithMeCard.waitForExistence(timeout: Self.uiTimeout))

        XCTAssertLessThanOrEqual(routeCards.count, 3,
                                 "the ride-with-me card leaked into the route cards")

        // It claims no journey metrics, unlike every route card beside it.
        let label = rideWithMeCard.label
        XCTAssertFalse(label.contains("dk"), "the card states a duration: \(label)")
        XCTAssertFalse(label.contains("aktarma"), "the card states transfers: \(label)")
        XCTAssertFalse(label.contains("durak"), "the card states stops: \(label)")
    }

    func testCardOpensItsOwnScreenWithBothEndpoints() {
        search()
        XCTAssertTrue(rideWithMeCard.waitForExistence(timeout: Self.uiTimeout))
        waitUntilHittable(rideWithMeCard)
        rideWithMeCard.tap()

        XCTAssertTrue(app.staticTexts["Kadıköy"].waitForExistence(timeout: Self.uiTimeout),
                      "the drive screen does not name the origin")
        XCTAssertTrue(app.staticTexts["Taksim"].exists,
                      "the drive screen does not name the destination")

        // Not the route detail screen — that one leads with the three numbers.
        XCTAssertFalse(app.staticTexts["dakika"].exists,
                       "the route detail summary appeared on the drive screen")

        for button in ["Beni ara", "Mesaj at", "Konumunu paylaş"] {
            XCTAssertTrue(app.buttons[button].exists, "'\(button)' is missing")
        }
    }

    /// The buttons are disabled when `Chauffeur.phoneNumber` is nil, so this is
    /// a live check that `contact.json` was found in the bundle — the one thing
    /// that silently breaks every button on this screen.
    ///
    /// Expected to fail on a fresh clone: `contact.json` is gitignored (this
    /// repo is public) and must be created from `contact.example.json`.
    func testThePhoneNumberIsConfigured() {
        search()
        let card = rideWithMeCard
        XCTAssertTrue(card.waitForExistence(timeout: Self.uiTimeout))
        waitUntilHittable(card)
        card.tap()

        let call = app.buttons["Beni ara"]
        XCTAssertTrue(call.waitForExistence(timeout: Self.uiTimeout))
        XCTAssertTrue(call.isEnabled,
                      "the buttons are inert — EnKisaYolculuk/Data/contact.json is missing "
                      + "or malformed; copy contact.example.json and put the real number in it")
    }
}
