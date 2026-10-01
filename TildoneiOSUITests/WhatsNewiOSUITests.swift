import XCTest

final class WhatsNewiOSUITests: XCTestCase {
    func testWelcomeReplayMacDownloadAndStartingWithoutAPaywall() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_UI_TESTING"] = "1"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let status = app.buttons["Sync is disabled"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        status.tap()
        app.buttons["Welcome to Tildone"].tap()
        XCTAssertTrue(app.buttons["welcome-next"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pro-purchase"].exists)
        XCTAssertFalse(app.buttons["welcome-get-mac"].exists)
        attachScreen(app, name: "iPhone welcome")
        app.buttons["welcome-next"].tap()
        let getMac = app.buttons["welcome-get-mac"]
        if !getMac.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(getMac.waitForExistence(timeout: 5))
        attachScreen(app, name: "iPhone iCloud and Mac companion")
        getMac.tap()
        XCTAssertTrue(app.buttons["get-mac-share"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["get-mac-download"].firstMatch.exists)
        attachScreen(app, name: "Get Tildone for Mac")
        app.buttons["get-mac-close"].tap()
        attachScreen(app, name: "iPhone iCloud devices")
        app.buttons["welcome-back"].tap()
        XCTAssertTrue(app.buttons["welcome-next"].waitForExistence(timeout: 5))
        app.buttons["welcome-next"].tap()
        app.buttons["welcome-next"].tap()
        let feature = app.buttons["welcome-pro-singleMemo"]
        XCTAssertTrue(feature.waitForExistence(timeout: 5))
        feature.tap()
        XCTAssertTrue(app.buttons["pro-purchase"].waitForExistence(timeout: 5))
        let discover = app.buttons["pro-discover-all"]
        if !discover.isHittable { app.scrollViews.firstMatch.swipeUp() }
        discover.tap()
        XCTAssertTrue(app.navigationBars["Pro features"].waitForExistence(timeout: 5))
        attachScreen(app, name: "Pro features navigation")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["welcome-start"].waitForExistence(timeout: 5))
        attachScreen(app, name: "iPhone Pro features")
        app.buttons["welcome-start"].tap()
        status.tap()
        XCTAssertTrue(app.buttons["Welcome to Tildone"].waitForExistence(timeout: 5))
        app.buttons["Welcome to Tildone"].tap()
        XCTAssertTrue(app.buttons["welcome-next"].waitForExistence(timeout: 5))
        app.buttons["welcome-skip"].tap()
        status.tap()
        app.buttons["About Tildone"].tap()
        XCTAssertTrue(app.buttons["Welcome to Tildone"].waitForExistence(timeout: 5))
        app.buttons["Restore Purchases"].tap()
        XCTAssertTrue(app.navigationBars["Restore Purchases"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["about-pro-close"].exists)
        attachScreen(app, name: "Restore Purchases navigation")
        app.buttons["about-pro-close"].tap()
        app.buttons["Get Tildone for Mac"].tap()
        XCTAssertTrue(app.buttons["get-mac-share"].waitForExistence(timeout: 5))
        app.buttons["get-mac-close"].tap()
    }

    private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
