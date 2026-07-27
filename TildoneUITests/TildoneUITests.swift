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

    func testDraggingTaskHandleReordersVisibleRows() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_TEST_USE_IN_MEMORY_LEGACY"] = "1"
        app.launchArguments.append("--tildone-ui-test")
        app.launch()

        let topic = app.textFields["Topic"]
        XCTAssertTrue(topic.waitForExistence(timeout: 5))
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

        let handles = app.images.matching(identifier: "Reorder task")
        XCTAssertEqual(handles.count, 2)
        let firstHandle = try XCTUnwrap(
            handles.allElementsBoundByIndex.min {
                abs($0.frame.midY - first.frame.midY) < abs($1.frame.midY - first.frame.midY)
            }
        )
        let source = firstHandle
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        source.press(forDuration: 0.5, thenDragTo: destination)

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
