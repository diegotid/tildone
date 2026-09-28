import XCTest

final class WhatsNewiOSUITests: XCTestCase {
    func testHighlightsFromAboutPreserveProgressAndOmitMacFeatures() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_UI_TESTING"] = "1"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let status = app.buttons["Sync is disabled"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        status.tap()
        app.buttons["About Tildone"].tap()
        app.buttons["What’s New"].tap()
        XCTAssertTrue(app.buttons["whats-new-next"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["whats-new-progress"].label, "Step 1 of 3")
        XCTAssertEqual(app.buttons["whats-new-close"].label, "Close")
        XCTAssertEqual(app.buttons["whats-new-suppress"].label, "Don't show until next version")
        attachScreen(app, name: "iPhone everyday improvements")
        app.buttons["whats-new-next"].tap()
        let memo = app.buttons["whats-new-feature-singleMemo"]
        if !memo.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(memo.waitForExistence(timeout: 5))
        memo.tap()
        XCTAssertTrue(app.buttons["pro-discover-all"].waitForExistence(timeout: 5))
        app.buttons["whats-new-preview-done"].tap()
        XCTAssertTrue(app.buttons["whats-new-next"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["whats-new-progress"].label, "Step 2 of 3")
        app.buttons["whats-new-next"].tap()
        XCTAssertTrue(app.buttons["whats-new-done"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["whats-new-done"].label, "Let’s get started")
        XCTAssertFalse(app.buttons["whats-new-feature-gathering"].exists)
        attachScreen(app, name: "iPhone subtasks")
        app.buttons["whats-new-done"].tap()
        XCTAssertTrue(app.buttons["What’s New"].waitForExistence(timeout: 5))
        app.buttons["What’s New"].tap()
        XCTAssertTrue(app.buttons["whats-new-next"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["whats-new-progress"].label, "Step 1 of 3")
        app.buttons["whats-new-close"].tap()
        XCTAssertTrue(app.buttons["What’s New"].waitForExistence(timeout: 5))
        app.buttons["What’s New"].tap()
        XCTAssertTrue(app.buttons["whats-new-next"].waitForExistence(timeout: 5))
        app.buttons["whats-new-suppress"].tap()
        XCTAssertTrue(app.buttons["What’s New"].waitForExistence(timeout: 5))
    }

    private func attachScreen(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
