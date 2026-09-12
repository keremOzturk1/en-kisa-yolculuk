import XCTest

/// Shared helpers for driving the app end to end.
///
/// Everything addresses elements by accessibility identifier rather than by
/// visible text, so wording changes do not break the flow tests.
class AppUITestCase: XCTestCase {

    var app: XCUIApplication!

    /// The splash holds ~1.7s and then fades.
    static let splashTimeout: TimeInterval = 20
    static let uiTimeout: TimeInterval = 15

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    /// Waits for the splash to go away, which is what actually hands the screen
    /// over — the picker is mounted underneath it from the first frame.
    func waitForPicker() {
        let splash = app.otherElements["splash"]
        if splash.exists {
            let gone = NSPredicate(format: "exists == false")
            expectation(for: gone, evaluatedWith: splash)
            waitForExpectations(timeout: Self.splashTimeout)
        }
        // Existence is not enough: for a beat after the splash's fade the
        // rows are on screen but not yet taking touches, and taps sent then
        // are silently dropped.
        let row = app.buttons.matching(identifier: "originPicker").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.uiTimeout),
                      "the picker never appeared")
        waitUntilHittable(row)
    }

    /// Waits for an element to actually accept touches.
    func waitUntilHittable(_ element: XCUIElement) {
        expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
        waitForExpectations(timeout: Self.uiTimeout)
    }

    /// Opens one of the two station rows and picks a station by typing its
    /// name into the search field — the list is 300+ rows long, so searching
    /// is the only practical way in, for a test as much as for a person.
    func choose(_ station: String, in row: String) {
        openStationList(row)

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.uiTimeout), "no search field")
        search.tap()
        search.typeText(station)

        let option = app.buttons.matching(identifier: "stationOption")
            .containing(NSPredicate(format: "label BEGINSWITH %@", station)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: Self.uiTimeout),
                      "'\(station)' was not offered")
        option.tap()

        XCTAssertTrue(app.buttons["findRoutes"].waitForExistence(timeout: Self.uiTimeout),
                      "the station list did not pop back to the picker")
    }

    func openStationList(_ row: String) {
        let button = app.buttons.matching(identifier: row).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: Self.uiTimeout), "no '\(row)' row")
        waitUntilHittable(button)
        button.tap()
        XCTAssertTrue(app.buttons.matching(identifier: "stationOption").firstMatch
                        .waitForExistence(timeout: Self.uiTimeout),
                      "the station list never opened")
    }

    func tapFindRoutes(expectingResults: Bool = true) {
        let button = app.buttons["findRoutes"]
        XCTAssertTrue(button.waitForExistence(timeout: Self.uiTimeout))
        waitUntilHittable(button)
        button.tap()
        if expectingResults {
            XCTAssertTrue(app.navigationBars["Alternatifler"].waitForExistence(timeout: Self.uiTimeout),
                          "the results screen never opened")
        }
    }

    var routeCards: XCUIElementQuery { app.buttons.matching(identifier: "routeCard") }
}

final class SmokeUITests: AppUITestCase {

    func testAppLaunchesAndSettles() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        waitForPicker()
    }
}
