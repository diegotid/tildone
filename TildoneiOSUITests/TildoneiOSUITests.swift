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

    func testRenamedNoteShowsLargeTitleBelowToolbar() {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_UI_TESTING"] = "1"
        app.launch()
        app.buttons["Create note"].tap()

        let titleField = app.textFields["Note title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.typeText("A longer note title")
        app.navigationBars.buttons["Done"].tap()

        let navigationBar = app.navigationBars.firstMatch
        let title = navigationBar.staticTexts["A longer note title"]
        let renameButton = navigationBar.buttons["Rename Note"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertTrue(renameButton.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(title.frame.minY, renameButton.frame.minY)

        renameButton.tap()
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        navigationBar.buttons["Done"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(title.frame.minY, renameButton.frame.minY)
    }

    func testTappingExistingTaskTextEntersEditing() {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_UI_TESTING"] = "1"
        app.launch()
        app.buttons["Create note"].tap()

        let titleField = app.textFields["Note title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.typeText("Tap to edit")
        app.navigationBars.buttons["Done"].tap()

        let newTaskField = app.textFields["New task"]
        XCTAssertTrue(newTaskField.waitForExistence(timeout: 3))
        newTaskField.tap()
        newTaskField.typeText("Existing task")
        newTaskField.typeText("\n")

        let taskText = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Existing")
        ).firstMatch
        XCTAssertTrue(taskText.waitForExistence(timeout: 3))
        taskText.tap()

        XCTAssertTrue(app.textViews["Task"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3))
    }
}
