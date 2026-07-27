//
//  TildoneTests.swift
//  TildoneTests
//

import CloudKit
import SwiftUI
import XCTest
import TildoneDomain
import TildonePersistence
import TildoneSync
@testable import Tildone

final class TildoneTests: XCTestCase {
    func testCheckboxDoesNotRetainParentOwnedCompletionAsLocalState() {
        let storedPropertyNames = Set(
            Mirror(reflecting: Checkbox(checked: false)).children.compactMap(\.label)
        )

        XCTAssertTrue(
            storedPropertyNames.contains("checked"),
            "Completion must remain an ordinary parent-owned view input."
        )
        XCTAssertFalse(
            storedPropertyNames.contains("_checked"),
            "Duplicating completion in @State prevents remote parent updates from redrawing the checkbox."
        )
    }

    @MainActor
    func testPrimarySceneUsesSingleUniqueCoordinatorWindow() {
        let scene = TildonePrimaryScene { EmptyView() }
        let bodyType = String(reflecting: type(of: scene.body))

        XCTAssertTrue(
            bodyType.contains("SwiftUI.Window<"),
            "The process-wide note-window coordinator must use SwiftUI.Window."
        )
        XCTAssertFalse(
            bodyType.contains("SwiftUI.WindowGroup<"),
            "WindowGroup permits multiple coordinator instances on macOS."
        )
    }

    func testMacSharedStoreRoutesCRUDThroughDomainRepository() async throws {
        let repository = try TildoneRepository(
            descriptor: .inMemory(),
            replicaID: ReplicaID(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!),
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let store = await MainActor.run { MacSharedStore(repository: repository) }

        let note = try await store.createNote(createdAt: Date(timeIntervalSince1970: 100))
        try await store.renameNote(note.id, to: "Title")
        let last = try await store.addTask(to: note.id, text: "Last")
        let first = try await store.addTask(to: note.id, text: "First", insertingAt: 0)
        try await store.setTaskCompletion(first.id, completed: true)
        try await store.editTask(last.id, text: "Changed")

        let loadedSnapshot = await MainActor.run { store.note(note.id) }
        let snapshot = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(snapshot.title, "Title")
        XCTAssertEqual(snapshot.tasks.map(\.text), ["First", "Changed"])
        XCTAssertEqual(snapshot.pendingTasks.map(\.id), [last.id])

        try await store.deleteTask(first.id)
        try await store.deleteTask(last.id)
        try await store.renameNote(note.id, to: nil)
        let loadedEmpty = await MainActor.run { store.note(note.id) }
        let empty = try XCTUnwrap(loadedEmpty)
        XCTAssertTrue(empty.isDeletable)
        try await store.deleteNote(note.id)
        let remaining = try await repository.visibleNotes()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testMacSharedStoreReordersBeginningMiddleAndEndWithoutChangingTaskContent() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TildoneMacReorder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: baseDirectory)
        }
        let descriptor = PersistenceStoreDescriptor.persistent(
            baseDirectory: baseDirectory,
            workspace: .localOnly
        )
        let replica = ReplicaID(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
        let noteID: NoteID
        let taskIDs: [TaskID]
        var expectedContent: [TaskID: TildoneDomain.Task] = [:]

        do {
            let repository = try TildoneRepository(
                descriptor: descriptor,
                replicaID: replica,
                now: { Date(timeIntervalSince1970: 4_000) }
            )
            let store = await MainActor.run { MacSharedStore(repository: repository) }
            let note = try await store.createNote(createdAt: Date(timeIntervalSince1970: 100))
            noteID = note.id

            let first = try await store.addTask(
                to: note.id, text: "First", createdAt: Date(timeIntervalSince1970: 101)
            )
            let second = try await store.addTask(
                to: note.id, text: "Second", createdAt: Date(timeIntervalSince1970: 102)
            )
            let third = try await store.addTask(
                to: note.id, text: "Third", createdAt: Date(timeIntervalSince1970: 103)
            )
            let fourth = try await store.addTask(
                to: note.id, text: "Fourth", createdAt: Date(timeIntervalSince1970: 104)
            )
            try await store.setTaskCompletion(second.id, completed: true)
            taskIDs = [first.id, second.id, third.id, fourth.id]
            expectedContent = Dictionary(
                uniqueKeysWithValues: try await repository.orderedTasks(in: note.id).map { ($0.id, $0) }
            )
            try await repository.acknowledgeMutations(
                ids: Set(try await repository.pendingMutations().map(\.id))
            )

            let movedToBeginning = try await store.moveTask(fourth.id, in: note.id, to: 0)
            let beginningIDs = await MainActor.run { store.note(note.id)?.tasks.map(\.id) }
            XCTAssertTrue(movedToBeginning)
            XCTAssertEqual(beginningIDs, [fourth.id, first.id, second.id, third.id])

            let movedToMiddle = try await store.moveTask(fourth.id, in: note.id, to: 3)
            let middleIDs = await MainActor.run { store.note(note.id)?.tasks.map(\.id) }
            XCTAssertTrue(movedToMiddle)
            XCTAssertEqual(middleIDs, [first.id, second.id, fourth.id, third.id])

            let movedToEnd = try await store.moveTask(first.id, in: note.id, to: 4)
            let endIDs = await MainActor.run { store.note(note.id)?.tasks.map(\.id) }
            XCTAssertTrue(movedToEnd)
            XCTAssertEqual(endIDs, [second.id, fourth.id, third.id, first.id])

            let pendingBeforeNoOp = try await repository.pendingMutations()
            let noOpMoved = try await store.moveTask(fourth.id, in: note.id, to: 1)
            let pendingAfterNoOp = try await repository.pendingMutations()
            XCTAssertFalse(noOpMoved)
            XCTAssertEqual(pendingAfterNoOp, pendingBeforeNoOp)

            let finalTasks = try await repository.orderedTasks(in: note.id)
            XCTAssertEqual(finalTasks.map(\.id), [second.id, fourth.id, third.id, first.id])
            XCTAssertEqual(Set(finalTasks.map(\.id)), Set(taskIDs))
            XCTAssertEqual(finalTasks.count, taskIDs.count)
            for task in finalTasks {
                let original = try XCTUnwrap(expectedContent[task.id])
                XCTAssertEqual(task.noteID, original.noteID)
                XCTAssertEqual(task.createdAt, original.createdAt)
                XCTAssertEqual(task.text, original.text)
                XCTAssertEqual(task.textVersion, original.textVersion)
                XCTAssertEqual(task.completion, original.completion)
                XCTAssertEqual(task.completionVersion, original.completionVersion)
                XCTAssertEqual(task.lifecycle, original.lifecycle)
                XCTAssertEqual(task.lifecycleVersion, original.lifecycleVersion)
            }
            XCTAssertEqual(
                finalTasks.first(where: { $0.id == second.id })?.orderToken,
                expectedContent[second.id]?.orderToken
            )
            XCTAssertEqual(
                finalTasks.first(where: { $0.id == third.id })?.orderToken,
                expectedContent[third.id]?.orderToken
            )

            let pending = try await repository.pendingMutations()
            XCTAssertEqual(pending.count, 3)
            XCTAssertEqual(Set(pending.map(\.targetKind)), [.note, .task])
            XCTAssertEqual(
                Set(pending.map(\.targetStableID)),
                [note.id.stringValue, first.id.stringValue, fourth.id.stringValue]
            )
        }

        let reopened = try TildoneRepository(descriptor: descriptor, replicaID: ReplicaID())
        let persisted = try await reopened.orderedTasks(in: noteID)
        XCTAssertEqual(persisted.map(\.id), [taskIDs[1], taskIDs[3], taskIDs[2], taskIDs[0]])
        XCTAssertEqual(Set(persisted.map(\.id)), Set(taskIDs))
        XCTAssertEqual(persisted.count, taskIDs.count)
        for task in persisted {
            let original = try XCTUnwrap(expectedContent[task.id])
            XCTAssertEqual(task.noteID, original.noteID)
            XCTAssertEqual(task.createdAt, original.createdAt)
            XCTAssertEqual(task.text, original.text)
            XCTAssertEqual(task.completion, original.completion)
            XCTAssertEqual(task.lifecycle, original.lifecycle)
        }
        let durablePending = try await reopened.pendingMutations()
        XCTAssertEqual(
            Set(durablePending.map(\.targetStableID)),
            [noteID.stringValue, taskIDs[0].stringValue, taskIDs[3].stringValue]
        )
    }

    func testMacTaskDragPayloadRejectsCrossNoteAndMalformedDrops() throws {
        let noteID = NoteID()
        let taskID = TaskID()
        let payload = MacTaskDragPayload(noteID: noteID, taskID: taskID)

        XCTAssertTrue(payload.isValid(for: noteID, taskIDs: [taskID]))
        XCTAssertFalse(payload.isValid(for: NoteID(), taskIDs: [taskID]))
        XCTAssertFalse(payload.isValid(for: noteID, taskIDs: [TaskID()]))
        XCTAssertThrowsError(try JSONDecoder().decode(
            MacTaskDragPayload.self,
            from: Data(#"{"noteID":"invalid","taskID":"invalid"}"#.utf8)
        ))
    }

    func testMacTaskRowsExposeDedicatedDragHandlesAndDropTargets() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tildone/Views/Note.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("TaskReorderHandle("))
        XCTAssertTrue(source.contains(".draggable(payload)"))
        XCTAssertTrue(source.contains("CodableRepresentation(contentType: .json)"))
        XCTAssertTrue(source.contains("TaskReorderPreview("))
        XCTAssertTrue(source.contains("Checkbox(checked: isCompleted)"))
        XCTAssertTrue(source.contains("Text(taskText.isEmpty ? \"Untitled task\" : taskText)"))
        XCTAssertTrue(source.contains(".padding(.top, dropPlacement == .before"))
        XCTAssertTrue(source.contains(".padding(.bottom, dropPlacement == .after"))
        XCTAssertTrue(source.contains("? TaskReorderFeedback.expandedHeight"))
        XCTAssertTrue(source.contains("TaskReorderInsertionLine()"))
        XCTAssertTrue(source.contains(".onChange(of: feedbackResetToken)"))
        XCTAssertTrue(source.contains(".padding(.trailing, 8)"))
        XCTAssertFalse(source.contains(".stroke(Color.accentColor"))
        XCTAssertTrue(source.contains(".dropDestination(for: MacTaskDragPayload.self)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Reorder task\")"))
    }

    /// Opt-in smoke test hosted by the signed development Mac app so the test
    /// inherits the real CloudKit entitlement. The normal suite is fully local.
    func testDevelopmentCloudKitRoundTripWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["TILDONE_RUN_DEVELOPMENT_CLOUDKIT_TESTS"] == "1" else {
            throw XCTSkip("Development CloudKit integration is explicitly opt-in")
        }
        let container = CKContainer(identifier: TildoneCloudSchema.containerIdentifier)
        guard try await container.accountStatus() == .available else {
            throw XCTSkip("A development iCloud account is required")
        }

        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneID: TildoneCloudSchema.zoneID)
        let zoneResults = try await database.modifyRecordZones(saving: [zone], deleting: [])
        _ = try zoneResults.saveResults[TildoneCloudSchema.zoneID]?.get()

        let timestamp = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let stamp = VersionStamp(logicalCounter: 1, replicaID: ReplicaID())
        let note = Note(
            id: NoteID(),
            createdAt: timestamp,
            title: "Stage 8 synthetic integration record",
            titleVersion: stamp,
            lifecycleVersion: stamp,
            lastMeaningfulEditAt: timestamp,
            lastMeaningfulEditVersion: stamp
        )
        let mapper = CloudKitRecordMapper()
        let record = mapper.record(from: .note(note))
        do {
            let saved = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )
            _ = try saved.saveResults[record.recordID]?.get()
            let fetched = try await database.records(for: [record.recordID])
            let fetchedRecord = try XCTUnwrap(fetched[record.recordID]).get()
            XCTAssertEqual(try mapper.syncRecord(from: fetchedRecord), .note(note))
            _ = try await database.modifyRecords(saving: [], deleting: [record.recordID])
        } catch {
            _ = try? await database.modifyRecords(saving: [], deleting: [record.recordID])
            throw error
        }
    }
}
