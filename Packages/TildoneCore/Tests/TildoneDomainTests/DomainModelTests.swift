//
//  DomainModelTests.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
import Foundation
import XCTest
@testable import TildoneDomain

final class DomainModelTests: XCTestCase {
    func testOrdinaryNoteEditDoesNotResurrectTombstone() throws {
        var note = Fixtures.note()
        try note.delete(version: Fixtures.stamp(2))
        try note.rename(
            to: "Edited while deleted",
            version: Fixtures.stamp(3),
            editedAt: Date(timeIntervalSince1970: 30),
            meaningfulEditVersion: Fixtures.stamp(4)
        )

        XCTAssertEqual(note.lifecycle, .deleted)
        XCTAssertEqual(note.lifecycleVersion, Fixtures.stamp(2))
        XCTAssertEqual(note.title, "Edited while deleted")
    }

    func testRestoreMustBeExplicitAndNewerThanDeletion() throws {
        var note = Fixtures.note()
        try note.delete(version: Fixtures.stamp(3))

        XCTAssertThrowsError(try note.restore(version: Fixtures.stamp(2)))
        XCTAssertEqual(note.lifecycle, .deleted)
        try note.restore(version: Fixtures.stamp(4))
        XCTAssertEqual(note.lifecycle, .active)
    }

    func testCompletionPayloadKeepsBooleanAndDateTogether() throws {
        var task = try Fixtures.task()
        let completionDate = Date(timeIntervalSince1970: 100)

        try task.setCompletion(.completed(at: completionDate), version: Fixtures.stamp(2))
        XCTAssertTrue(task.isCompleted)
        XCTAssertEqual(task.completedAt, completionDate)

        try task.setCompletion(.incomplete, version: Fixtures.stamp(3))
        XCTAssertFalse(task.isCompleted)
        XCTAssertNil(task.completedAt)
    }

    func testCompletionAndUncompletionDoNotModifyTextOrOrderVersions() throws {
        var task = try Fixtures.task()
        let textVersion = task.textVersion
        let orderVersion = task.orderVersion

        try task.setCompletion(.completed(at: .distantPast), version: Fixtures.stamp(2))
        try task.setCompletion(.incomplete, version: Fixtures.stamp(3))

        XCTAssertEqual(task.textVersion, textVersion)
        XCTAssertEqual(task.orderVersion, orderVersion)
    }

    func testTaskOwnershipAndCreationMetadataAreImmutable() throws {
        let task = try Fixtures.task()
        let roundTrip = try JSONDecoder().decode(Task.self, from: JSONEncoder().encode(task))

        XCTAssertEqual(roundTrip, task)
        XCTAssertEqual(roundTrip.noteID, Fixtures.noteID)
        XCTAssertEqual(roundTrip.createdAt, Fixtures.createdAt)
    }

    func testNoteTaskSummaryIgnoresDeletedAndForeignTasks() throws {
        var deleted = try Fixtures.task(id: Fixtures.taskID(2))
        try deleted.delete(version: Fixtures.stamp(2))
        var completed = try Fixtures.task(id: Fixtures.taskID(3))
        try completed.setCompletion(.completed(at: .distantPast), version: Fixtures.stamp(2))
        let foreign = try Fixtures.task(id: Fixtures.taskID(4), noteID: Fixtures.otherNoteID)

        let summary = NoteTaskSummary(
            noteID: Fixtures.noteID,
            tasks: [try Fixtures.task(), deleted, completed, foreign]
        )

        XCTAssertEqual(summary.totalCount, 2)
        XCTAssertEqual(summary.completedCount, 1)
        XCTAssertEqual(summary.pendingCount, 1)
        XCTAssertFalse(summary.isEmpty)
        XCTAssertFalse(summary.isComplete)
    }

    func testEmptyAndCompleteSummaryRules() throws {
        let empty = NoteTaskSummary(noteID: Fixtures.noteID, tasks: [Task]())
        var completed = try Fixtures.task()
        try completed.setCompletion(.completed(at: .distantPast), version: Fixtures.stamp(2))
        let complete = NoteTaskSummary(noteID: Fixtures.noteID, tasks: [completed])

        XCTAssertTrue(empty.isEmpty)
        XCTAssertFalse(empty.isComplete)
        XCTAssertTrue(complete.isComplete)
    }
}
