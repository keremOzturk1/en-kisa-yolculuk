import XCTest

/// The splash screen and the state the app settles into.
final class LaunchUITests: AppUITestCase {

    func testSplashShowsTheWordmark() {
        // The splash holds ~1.7s, so both lines should still be on screen.
        XCTAssertTrue(app.staticTexts["Kalbimden Kalbine"].waitForExistence(timeout: 5)
                      || app.otherElements["splash"].exists,
                      "the splash never appeared")
    }

    func testSplashGivesWayToThePicker() {
        waitForPicker()
        XCTAssertFalse(app.otherElements["splash"].exists, "the splash never went away")
        XCTAssertTrue(app.navigationBars["En Kısa Yolculuk"].exists)
    }

    func testSearchIsDisabledUntilTwoStationsAreChosen() {
        waitForPicker()
        XCTAssertFalse(app.buttons["findRoutes"].isEnabled,
                       "search should be disabled with nothing chosen")

        choose("Kadıköy", in: "originPicker")
        XCTAssertFalse(app.buttons["findRoutes"].isEnabled,
                       "search should stay disabled with only an origin")

        choose("Taksim", in: "destinationPicker")
        XCTAssertTrue(app.buttons["findRoutes"].isEnabled,
                      "search should be enabled once both are chosen")
    }

    func testDataSummaryReportsTheLoadedNetwork() {
        waitForPicker()
        let summary = app.staticTexts["dataSummary"]
        XCTAssertTrue(summary.waitForExistence(timeout: Self.uiTimeout),
                      "the data summary is missing")
        // Not hard-coded, so adding lines does not break the test.
        XCTAssertTrue(summary.label.contains("istasyon"))
        XCTAssertTrue(summary.label.contains("hat"))
        XCTAssertTrue(summary.label.contains("aktarma cezası"))
        // The placeholder-data notice was removed once the real network landed.
        XCTAssertFalse(summary.label.contains("örnek veri"))
    }
}
