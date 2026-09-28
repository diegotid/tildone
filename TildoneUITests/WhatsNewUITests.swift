import XCTest

final class WhatsNewUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testHighlightsNavigationPreviewAndReopening() {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_TEST_USE_IN_MEMORY_LEGACY"] = "1"
        app.launchArguments = ["--tildone-ui-test", "-showDockIcon", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        func openHighlights() {
            let help = app.menuBars.menuBarItems["Help"]
            help.click()
            help.menus.menuItems["What’s New…"].click()
            XCTAssertTrue(app.buttons["whats-new-next"].waitForExistence(timeout: 5))
        }
        openHighlights()
        let window = app.windows.containing(.button, identifier: "whats-new-close").firstMatch
        XCTAssertTrue(window.exists)
        XCTAssertEqual(app.buttons["whats-new-close"].label, "Close")
        XCTAssertEqual(app.descendants(matching: .any)["whats-new-suppress"].firstMatch.label, "Don't show until next version")
        XCTAssertLessThanOrEqual(window.staticTexts.matching(identifier: "What’s New").count, 1)
        XCTAssertFalse(app.buttons["whats-new-back"].exists)
        XCTAssertTrue(app.staticTexts["Included for everyone"].exists)
        attachScreenshot(window, name: "Everyday improvements")
        app.buttons["whats-new-next"].click()
        XCTAssertTrue(app.buttons["whats-new-feature-singleMemo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["whats-new-feature-textStyling"].exists)
        attachScreenshot(window, name: "Memos and styling")
        app.buttons["whats-new-feature-singleMemo"].click()
        XCTAssertTrue(app.buttons["pro-discover-all"].waitForExistence(timeout: 5))
        // Visiting a feature must retain the update flow's current step.
        window.click()
        XCTAssertTrue(app.buttons["whats-new-feature-singleMemo"].exists)
        app.buttons["whats-new-next"].click()
        XCTAssertTrue(app.buttons["whats-new-feature-subtasks"].waitForExistence(timeout: 5))
        attachScreenshot(window, name: "Subtasks")
        app.buttons["whats-new-back"].click()
        XCTAssertTrue(app.buttons["whats-new-feature-singleMemo"].waitForExistence(timeout: 5))
        app.buttons["whats-new-next"].click()
        app.buttons["whats-new-next"].click()
        XCTAssertTrue(app.buttons["whats-new-done"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["whats-new-done"].label, "Let’s get started")
        XCTAssertTrue(app.descendants(matching: .any)["whats-new-suppress"].firstMatch.exists)
        attachScreenshot(window, name: "Desktop focus")
        app.buttons["whats-new-done"].click()
        XCTAssertFalse(window.exists)
        openHighlights()
        XCTAssertFalse(app.buttons["whats-new-back"].exists)
        app.buttons["whats-new-close"].click()
        XCTAssertFalse(window.exists)
        openHighlights()
        app.descendants(matching: .any)["whats-new-suppress"].firstMatch.click()
        XCTAssertFalse(window.exists)
        openHighlights()
        window.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertFalse(window.exists)
    }

    private func attachScreenshot(_ element: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
