//
//  TildoneiOSUITests.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import XCTest

final class TildoneiOSUITests: XCTestCase {
    func testProFeaturePaywallStartsAtTriggerAndReturnsToIndex() {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_UI_TESTING"] = "1"
        app.launch()
        app.buttons["Create note"].tap()
        XCTAssertTrue(app.textFields["Note title"].waitForExistence(timeout: 5))
        app.textFields["Note title"].typeText("Pro navigation\n")
        app.buttons["Note type"].tap()
        app.buttons["Single memo"].tap()
        let discover = app.buttons["pro-discover-all"]
        XCTAssertTrue(discover.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Single memos"].exists)
        discover.tap()
        let styling = app.buttons["pro-feature-textStyling"]
        XCTAssertTrue(styling.waitForExistence(timeout: 5))
        styling.tap()
        XCTAssertTrue(discover.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars.buttons["Pro features"].exists)
        discover.tap()
        XCTAssertTrue(styling.waitForExistence(timeout: 5))
    }

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

    func testSwitchingTaskRowsKeepsOnlyOneEditorAndSavesEachDraft() {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_UI_TESTING"] = "1"
        app.launch()
        app.buttons["Create note"].tap()
        let titleField = app.textFields["Note title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.typeText("Focus regression")
        app.navigationBars.buttons["Done"].tap()

        let newTaskField = app.textFields["New task"]
        XCTAssertTrue(newTaskField.waitForExistence(timeout: 3))
        newTaskField.tap()
        newTaskField.typeText("First row\n")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "First"))
            .firstMatch.waitForExistence(timeout: 3))
        newTaskField.tap()
        newTaskField.typeText("Second row\n")

        func taskButton(_ text: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        }
        func assertOnlyEditor(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
            let editors = app.textViews.matching(identifier: "Task")
            let matches = NSPredicate { _, _ in
                editors.count == 1 && editors.firstMatch.value as? String == text
            }
            XCTAssertTrue(
                XCTWaiter.wait(for: [expectation(for: matches, evaluatedWith: app)], timeout: 3) == .completed,
                "Expected one editor with \(text); found \(editors.allElementsBoundByIndex.map { $0.value as? String ?? "" }).",
                file: file, line: line
            )
        }

        XCTAssertTrue(taskButton("First").waitForExistence(timeout: 3))
        taskButton("First").tap()
        assertOnlyEditor("First row")
        app.textViews["Task"].typeText(" edited")
        let firstDraft = app.textViews["Task"].value as? String ?? ""
        XCTAssertTrue(firstDraft.localizedCaseInsensitiveContains("edited"))

        taskButton("Second").tap()
        assertOnlyEditor("Second row")
        XCTAssertTrue(taskButton("First").waitForExistence(timeout: 3))
        app.textViews["Task"].typeText(" edited")
        let secondDraft = app.textViews["Task"].value as? String ?? ""
        XCTAssertTrue(secondDraft.localizedCaseInsensitiveContains("edited"))

        taskButton("First").tap()
        assertOnlyEditor(firstDraft)
        XCTAssertTrue(taskButton("Second").waitForExistence(timeout: 3))

        newTaskField.tap()
        let noEditors = NSPredicate { _, _ in app.textViews.matching(identifier: "Task").count == 0 }
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: noEditors, evaluatedWith: app)], timeout: 3) == .completed)
        newTaskField.typeText("Third row\n")
        XCTAssertTrue(taskButton("Third").waitForExistence(timeout: 3))
        taskButton("First").tap()
        assertOnlyEditor(firstDraft)
        app.textViews["Task"].typeText("\n")
        assertOnlyEditor(secondDraft)
        app.textViews["Task"].typeText("\n")
        assertOnlyEditor("Third row")
        app.textViews["Task"].typeText("\n")
        XCTAssertTrue(XCTWaiter.wait(for: [expectation(for: noEditors, evaluatedWith: app)], timeout: 3) == .completed)
        newTaskField.typeText("Fourth row\n")
        XCTAssertTrue(taskButton("Fourth").waitForExistence(timeout: 3))
    }

    func testFinalTaskShowsDoneThenFadesFromNotesWithUndo() {
        let app = XCUIApplication()
        app.launchEnvironment["TILDONE_UI_TESTING"] = "1"
        app.launch()
        app.buttons["Create note"].tap()

        let titleField = app.textFields["Note title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.typeText("Finish me")
        app.navigationBars.buttons["Done"].tap()

        let newTaskField = app.textFields["New task"]
        XCTAssertTrue(newTaskField.waitForExistence(timeout: 3))
        newTaskField.tap()
        newTaskField.typeText("Last task\n")
        XCTAssertTrue(app.buttons["Complete task"].waitForExistence(timeout: 3))
        app.buttons["Complete task"].tap()

        XCTAssertTrue(app.staticTexts["Done!"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["No Notes Yet"].waitForExistence(timeout: 8))
        let undo = app.buttons["Undo Complete Task"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.tap()
        XCTAssertTrue(app.staticTexts["Finish me"].waitForExistence(timeout: 5))
    }
}
