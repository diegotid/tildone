//
//  TildoneUITests.swift
//  TildoneUITests
//
//  Created by Diego Rivera on 5/11/23.
//

import XCTest

final class TildoneUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_TEST_USE_IN_MEMORY_LEGACY"] = "1"
        app.launchArguments.append("--tildone-ui-test")
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testProFeatureIndexNavigation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_TEST_USE_IN_MEMORY_LEGACY"] = "1"
        app.launchArguments += ["--tildone-ui-test", "-showDockIcon", "YES"]
        app.launch()
        app.menuBars.menuBarItems["Tildone"].click()
        app.menuItems["Tildone Pro"].click()
        let memo = app.buttons["pro-feature-singleMemo"]
        XCTAssertTrue(memo.waitForExistence(timeout: 5))
        let window = app.windows["Tildone Pro"]
        XCTAssertTrue(window.exists)
        for button in [app.buttons["pro-purchase"], app.buttons["Restore Purchases"]] {
            XCTAssertTrue(button.exists)
            XCTAssertGreaterThan(button.frame.height, 0)
            XCTAssertLessThanOrEqual(button.frame.maxY, window.frame.maxY)
            XCTAssertGreaterThanOrEqual(button.frame.minY, window.frame.minY)
        }
        func assertBottomPadding() {
            let status = app.staticTexts["pro-status"]
            let lastControl = status.exists ? status : app.buttons["Restore Purchases"]
            let bottom = window.frame.maxY - lastControl.frame.maxY
            let side = lastControl.frame.minX - window.frame.minX
            XCTAssertEqual(bottom, 24, accuracy: 2)
            if !status.exists { XCTAssertEqual(bottom, side, accuracy: 2) }
        }
        assertBottomPadding()
        let initialSize = window.frame.size
        for feature in ["singleMemo", "textStyling", "subtasks", "blur", "background", "dimming", "gathering"] {
            let row = app.buttons["pro-feature-\(feature)"]
            XCTAssertTrue(row.exists)
            row.click()
            let discover = app.buttons["pro-discover-all"]
            XCTAssertTrue(discover.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["pro-feature-index-back"].exists)
            XCTAssertEqual(window.frame.size, initialSize)
            XCTAssertEqual(window.scrollViews.count, 0)
            assertBottomPadding()
            for button in [discover, app.buttons["pro-purchase"], app.buttons["Restore Purchases"]] {
                XCTAssertTrue(button.exists)
                XCTAssertGreaterThan(button.frame.height, 0)
                XCTAssertLessThanOrEqual(button.frame.maxY, window.frame.maxY)
                XCTAssertGreaterThanOrEqual(button.frame.minY, window.frame.minY)
            }
            discover.click()
            XCTAssertTrue(memo.waitForExistence(timeout: 5))
            XCTAssertEqual(window.frame.size, initialSize)
        }
    }

    func testGeneralSettingsOpensProDiscoveryIndex() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_TEST_USE_IN_MEMORY_LEGACY"] = "1"
        app.launchArguments += ["--tildone-ui-test", "-showDockIcon", "YES"]
        app.launch()
        app.menuBars.menuBarItems["Tildone"].click()
        app.menuItems["Settings…"].firstMatch.click()
        let discover = app.buttons["settings-discover-pro"]
        XCTAssertTrue(discover.waitForExistence(timeout: 5))
        let purchase = app.buttons["settings-purchase-pro"]
        XCTAssertTrue(purchase.exists, "Purchase and discovery must be separate actions")
        XCTAssertLessThan(purchase.frame.maxY, discover.frame.minY)
        let settingsWindow = app.windows.containing(.button, identifier: "settings-discover-pro").firstMatch
        XCTAssertGreaterThan(discover.frame.height, 0)
        XCTAssertLessThanOrEqual(discover.frame.maxY, settingsWindow.frame.maxY)
        func assertMatchingBottomPadding(_ element: XCUIElement) {
            let window = app.windows.containing(.any, identifier: element.identifier).firstMatch
            let bottom = window.frame.maxY - element.frame.maxY
            let right = window.frame.maxX - element.frame.maxX
            XCTAssertEqual(bottom, 28, accuracy: 2)
            XCTAssertEqual(bottom, right, accuracy: 2)
        }
        assertMatchingBottomPadding(discover)
        app.descendants(matching: .any)["Positioning"].firstMatch.click()
        let gatherPreview = app.descendants(matching: .any)["settings-gather-preview"].firstMatch
        XCTAssertTrue(gatherPreview.waitForExistence(timeout: 5))
        assertMatchingBottomPadding(gatherPreview)
        app.descendants(matching: .any)["General"].firstMatch.click()
        XCTAssertTrue(discover.waitForExistence(timeout: 5))
        discover.click()
        XCTAssertTrue(app.buttons["pro-feature-singleMemo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pro-feature-gathering"].exists)
        XCTAssertFalse(app.buttons["pro-discover-all"].exists, "Settings must start at the index")
    }

    func testDockModeExposesStandardAppMenus() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_TEST_USE_IN_MEMORY_LEGACY"] = "1"
        app.launchArguments += ["--tildone-ui-test", "-showDockIcon", "YES"]
        app.launch()

        for title in ["Tildone", "File", "Edit", "View", "Window", "Help"] {
            XCTAssertTrue(
                app.menuBars.menuBarItems[title].waitForExistence(timeout: 5),
                "Expected the \(title) app menu when Dock mode is enabled."
            )
        }

        app.menuBars.menuBarItems["Tildone"].click()
        for title in ["About Tildone", "Settings…", "Hide Tildone", "Quit Tildone"] {
            XCTAssertTrue(app.menuItems[title].exists)
        }

        app.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(app.menuItems["New Note"].exists)
        XCTAssertTrue(
            app.menuItems["Close Window"].exists || app.menuItems["Discard Empty Note"].exists
        )

        app.menuBars.menuBarItems["Edit"].click()
        for title in ["Undo", "Redo", "Cut", "Copy", "Copy Note Contents", "Paste", "Select All"] {
            XCTAssertTrue(app.menuItems[title].exists)
        }

        app.menuBars.menuBarItems["View"].click()
        XCTAssertTrue(app.menuItems["Visible Note Colors"].exists)

        app.menuBars.menuBarItems["Window"].click()
        for title in ["Minimize All", "Bring All Up", "Line Up Notes"] {
            XCTAssertTrue(app.menuItems[title].exists)
        }

        app.menuBars.menuBarItems["Help"].click()
        let helpMenu = app.menuBars.menuBarItems["Help"].menus.firstMatch
        XCTAssertTrue(helpMenu.menuItems["Keyboard Shortcuts…"].exists)
        XCTAssertTrue(helpMenu.menuItems["Scroll Gestures…"].exists)
        XCTAssertTrue(helpMenu.menuItems["How to Use Focus Filters…"].exists)

        helpMenu.menuItems["Scroll Gestures…"].click()
        XCTAssertTrue(
            app.staticTexts[
                "Use a mouse wheel or trackpad scroll gesture to dim notes or bring them together without interrupting your work."
            ].waitForExistence(timeout: 5),
            "Expected the Scroll Gestures guide to open from the Help menu."
        )
        XCTAssertTrue(
            app.windows["Scroll Gestures"].buttons["Open Settings"].exists,
            "Expected the Scroll Gestures guide to offer a Settings CTA."
        )

        app.typeKey("/", modifierFlags: .command)
        XCTAssertTrue(
            app.staticTexts[
                "A quick reference for Tildone commands and gestures. Customizable shortcuts reflect your current Settings."
            ].waitForExistence(timeout: 5),
            "Expected Command-Slash to open the keyboard-shortcut cheat sheet."
        )
        XCTAssertTrue(
            app.windows["Keyboard Shortcuts"].buttons["Open Settings"].exists,
            "Expected the keyboard-shortcut cheat sheet to offer a Settings CTA."
        )

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(
            app.checkBoxes["Show Dock Icon and App Menus"].waitForExistence(timeout: 5),
            "Expected Command-Comma to open the Settings window."
        )
    }

    func testMenuBarOnlyModeKeepsSettingsShortcut() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_TEST_USE_IN_MEMORY_LEGACY"] = "1"
        app.launchArguments += ["--tildone-ui-test", "-showDockIcon", "NO"]
        app.launch()

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(
            app.checkBoxes["Show Dock Icon and App Menus"].waitForExistence(timeout: 5),
            "Expected Command-Comma to open Settings in menu-bar-only mode."
        )
    }

    func testDraggingTaskHandleReordersVisibleRows() throws {
        try exerciseTaskReorderUI(multiline: false, dropIntoGap: false)
    }

    func testMultilineTaskShowsUsableDragHandle() throws {
        try exerciseTaskReorderUI(multiline: true, checkHandleOnly: true)
    }

    func testDraggingTaskHandleIntoGapReordersRows() throws {
        try exerciseTaskReorderUI(multiline: false, dropIntoGap: true)
    }

    private func exerciseTaskReorderUI(
        multiline: Bool,
        dropIntoGap: Bool = false,
        checkHandleOnly: Bool = false
    ) throws {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_TEST_USE_IN_MEMORY_LEGACY"] = "1"
        app.launchArguments.append("--tildone-ui-test")
        app.launch()

        let topic = app.textFields["Topic"]
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
        app.typeKey(",", modifierFlags: .command)
        let appearanceTab = app.buttons["Appearance"].firstMatch
        XCTAssertTrue(appearanceTab.waitForExistence(timeout: 5))
        appearanceTab.click()
        let wrappingOption = app.radioButtons[
            multiline ? "Wrap to multiple lines" : "Single line (ellipsis)"
        ]
        XCTAssertTrue(wrappingOption.waitForExistence(timeout: 5))
        wrappingOption.click()
        topic.click()
        topic.typeText("Drag test")
        topic.typeKey(.return, modifierFlags: [])

        app.typeText("First")
        app.typeKey(.return, modifierFlags: [])
        let first = app.textFields.matching(NSPredicate(format: "value == %@", "First")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))

        app.typeText("Second")
        app.typeKey(.return, modifierFlags: [])
        let second = app.textFields.matching(NSPredicate(format: "value == %@", "Second")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        let initialRowDistance = second.frame.minY - first.frame.minY

        first.hover()
        let handles = app.images.matching(identifier: "Reorder task")
        let firstHandle = try XCTUnwrap(handles.allElementsBoundByIndex.min {
            abs($0.frame.midY - first.frame.midY) < abs($1.frame.midY - first.frame.midY)
        })
        let firstFrame = first.frame
        let handleFrame = firstHandle.frame
        XCTAssertLessThan(abs(handleFrame.midY - firstFrame.midY), 12)
        XCTAssertGreaterThan(handleFrame.width, 10)
        if checkHandleOnly { return }
        let source = first.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
            dx: handleFrame.midX - firstFrame.minX,
            dy: handleFrame.midY - firstFrame.minY
        ))
        source.hover()
        let destination = second.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: dropIntoGap ? 1.12 : 0.9)
        )
        source.click(forDuration: 0.5, thenDragTo: destination)

        let reordered = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in second.frame.minY < first.frame.minY },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 5), .completed)

        let spacingRestored = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                abs((first.frame.minY - second.frame.minY) - initialRowDistance) < 3
            },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [spacingRestored], timeout: 5), .completed)
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                let app = XCUIApplication()
                app.launchEnvironment["TILDONE_TEST_USE_IN_MEMORY_LEGACY"] = "1"
                app.launchArguments.append("--tildone-ui-test")
                app.launch()
            }
        }
    }
}
