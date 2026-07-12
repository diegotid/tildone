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
        app.launch()
        XCTAssertTrue(app.staticTexts["Tildone for iPhone"].exists)
    }
}
