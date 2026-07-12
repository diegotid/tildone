//
//  DomainMergeTests.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
import Foundation
import XCTest
@testable import TildoneDomain

final class DomainMergeTests: XCTestCase {
    func testTaskPropertiesMergeIndependently() throws {
        let base = try Fixtures.task()
        var textEdit = base
        var completionEdit = base
        var orderEdit = base
        try textEdit.editText("new text", version: Fixtures.stamp(2))
        try completionEdit.setCompletion(.completed(at: Date(timeIntervalSince1970: 20)), version: Fixtures.stamp(3))
        try orderEdit.move(to: OrderToken.after(base.orderToken), version: Fixtures.stamp(4))

        let merged = try textEdit.merged(with: completionEdit).merged(with: orderEdit)

        XCTAssertEqual(merged.text, "new text")
        XCTAssertTrue(merged.isCompleted)
        XCTAssertEqual(merged.completedAt, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(merged.orderToken, orderEdit.orderToken)
    }

    func testWinningCompletionBooleanAndDateTravelTogether() throws {
        var earlier = try Fixtures.task()
        var later = earlier
        try earlier.setCompletion(.completed(at: Date(timeIntervalSince1970: 20)), version: Fixtures.stamp(2))
        try later.setCompletion(.incomplete, version: Fixtures.stamp(3))

        let merged = try earlier.merged(with: later)

        XCTAssertFalse(merged.isCompleted)
        XCTAssertNil(merged.completedAt)
        XCTAssertEqual(merged.completionVersion, Fixtures.stamp(3))
    }

    func testDeleteWinsAgainstNewerOrdinaryEditsButNewerExplicitRestoreWins() throws {
        let base = try Fixtures.task()
        var deleted = base
        var edited = base
        try deleted.delete(version: Fixtures.stamp(5))
        try edited.editText("offline edit", version: Fixtures.stamp(9))

        let tombstone = try deleted.merged(with: edited)
        XCTAssertEqual(tombstone.lifecycle, .deleted)
        XCTAssertEqual(tombstone.text, "offline edit")

        var restored = tombstone
        try restored.restore(version: Fixtures.stamp(10))
        XCTAssertEqual(try tombstone.merged(with: restored).lifecycle, .active)
    }

    func testMergeIsCommutativeAssociativeAndIdempotent() throws {
        let base = try Fixtures.task()
        var a = base
        var b = base
        var c = base
        try a.editText("a", version: Fixtures.stamp(2))
        try b.setCompletion(.completed(at: Date(timeIntervalSince1970: 50)), version: Fixtures.stamp(3))
        try c.move(to: OrderToken.after(base.orderToken), version: Fixtures.stamp(4))

        XCTAssertEqual(try a.merged(with: b), try b.merged(with: a))
        XCTAssertEqual(try a.merged(with: a), a)
        XCTAssertEqual(
            try a.merged(with: b).merged(with: c),
            try a.merged(with: b.merged(with: c))
        )
    }

    func testAllDeliveryOrdersConverge() throws {
        let base = try Fixtures.task()
        var text = base
        var completion = base
        var deletion = base
        try text.editText("remote", version: Fixtures.stamp(6))
        try completion.setCompletion(.completed(at: Date(timeIntervalSince1970: 80)), version: Fixtures.stamp(7))
        try deletion.delete(version: Fixtures.stamp(8))

        let records = [base, text, completion, deletion]
        let outcomes = try permutations(records).map { records in
            try records.dropFirst().reduce(records[0]) { try $0.merged(with: $1) }
        }

        XCTAssertEqual(Set(outcomes).count, 1)
    }

    func testNoteMergeUsesLogicalVersionsNotDates() throws {
        var logicallyLater = Fixtures.note(lastMeaningfulEditAt: Date(timeIntervalSince1970: 10))
        var clockLater = Fixtures.note(lastMeaningfulEditAt: Date(timeIntervalSince1970: 1_000))
        try logicallyLater.rename(
            to: "logical winner",
            version: Fixtures.stamp(4),
            editedAt: Date(timeIntervalSince1970: 10),
            meaningfulEditVersion: Fixtures.stamp(6)
        )
        try clockLater.rename(
            to: "newer wall clock",
            version: Fixtures.stamp(3),
            editedAt: Date(timeIntervalSince1970: 1_000),
            meaningfulEditVersion: Fixtures.stamp(5)
        )

        let merged = try logicallyLater.merged(with: clockLater)

        XCTAssertEqual(merged.title, "logical winner")
        XCTAssertEqual(merged.lastMeaningfulEditAt, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(merged.lastMeaningfulEditVersion, Fixtures.stamp(6))
    }

    func testInvalidImmutableOrSameVersionDivergenceIsRejectedSymmetrically() throws {
        let task = try Fixtures.task()
        let otherID = try Fixtures.task(id: Fixtures.taskID(2))
        let otherOwner = try Fixtures.task(noteID: Fixtures.otherNoteID)
        let divergent = Task(
            id: task.id,
            noteID: task.noteID,
            createdAt: task.createdAt,
            text: "impossible divergent payload",
            textVersion: task.textVersion,
            completion: task.completion,
            completionVersion: task.completionVersion,
            orderToken: task.orderToken,
            orderVersion: task.orderVersion,
            lifecycle: task.lifecycle,
            lifecycleVersion: task.lifecycleVersion
        )

        XCTAssertThrowsError(try task.merged(with: otherID)) { error in
            XCTAssertEqual(error as? DomainMergeError, .differentIdentifiers)
        }
        XCTAssertThrowsError(try task.merged(with: otherOwner)) { error in
            XCTAssertEqual(error as? DomainMergeError, .immutableFieldMismatch)
        }
        for pair in [(task, divergent), (divergent, task)] {
            XCTAssertThrowsError(try pair.0.merged(with: pair.1)) { error in
                XCTAssertEqual(error as? DomainMergeError, .conflictingPayloadAtSameVersion)
            }
        }
    }
}

private func permutations<Element>(_ elements: [Element]) -> [[Element]] {
    guard elements.count > 1 else { return [elements] }
    return elements.indices.flatMap { index -> [[Element]] in
        var remainder = elements
        let head = remainder.remove(at: index)
        return permutations(remainder).map { [head] + $0 }
    }
}
