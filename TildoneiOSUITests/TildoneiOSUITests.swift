//
//  TildoneiOSUITests.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
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
    }
}
