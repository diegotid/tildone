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
        app.buttons["About Tildone"].tap()
        XCTAssertFalse(app.buttons["What’s New"].exists)
        app.buttons["Welcome to Tildone"].tap()
        XCTAssertTrue(app.buttons["welcome-next"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["pro-purchase"].exists)
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
        XCTAssertTrue(app.buttons["welcome-start"].waitForExistence(timeout: 5))
        app.buttons["welcome-back"].tap()
        XCTAssertTrue(app.buttons["welcome-next"].waitForExistence(timeout: 5))
        app.buttons["welcome-next"].tap()
        app.buttons["welcome-start"].tap()
        XCTAssertTrue(app.buttons["Welcome to Tildone"].waitForExistence(timeout: 5))
        app.buttons["Welcome to Tildone"].tap()
        XCTAssertTrue(app.buttons["welcome-next"].waitForExistence(timeout: 5))
        app.buttons["welcome-skip"].tap()
        XCTAssertTrue(app.buttons["Welcome to Tildone"].waitForExistence(timeout: 5))
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
