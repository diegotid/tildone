//
//  TildoneiOSUITests.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import XCTest

final class TildoneiOSUITests: XCTestCase {
    func testLaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_UI_TESTING"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["No Notes Yet"].waitForExistence(timeout: 5))
        app.buttons["Create note"].tap()
        XCTAssertTrue(app.textFields["Note title"].waitForExistence(timeout: 3))

        let backButton = app.navigationBars.buttons["Notes"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 3))
        backButton.tap()

        let existingNote = app.staticTexts["Untitled Note"].firstMatch
        XCTAssertTrue(existingNote.waitForExistence(timeout: 3))
        existingNote.tap()
        XCTAssertTrue(app.textFields["Note title"].waitForExistence(timeout: 3))
    }
}
