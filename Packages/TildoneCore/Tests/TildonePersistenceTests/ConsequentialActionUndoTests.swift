//
//  ConsequentialActionUndoTests.swift
//  Tildone
//

import XCTest
import TildoneDomain
@testable import TildonePersistence

@MainActor
final class ConsequentialActionUndoTests: XCTestCase {
    private let createdAt = Date(timeIntervalSince1970: 10_000)
    private let replica = ReplicaID(UUID(uuidString: "70000000-0000-0000-0000-000000000001")!)

    func testUndoDeleteNoteExplicitlyRestoresContentCompletionOrderAndAdvancesOutbox() async throws {
        let repository = try makeRepository()
        let (note, tasks) = try await makeNoteWithThreeTasks(in: repository)
        _ = try await repository.setNoteColor(id: note.id, color: .purple)
        _ = try await repository.setTaskCompletion(
            id: tasks[1].id,
            completion: .completed(at: createdAt.addingTimeInterval(20))
        )
        let originalNote = try await repository.note(id: note.id)
        let originalTasks = try await repository.orderedTasks(in: note.id)
        try await clearOutbox(repository)
        let controller = ConsequentialActionUndoController(repository: repository)

        try await repository.deleteNote(id: note.id)
        let deletedNote = try await repository.note(id: note.id, includingDeleted: true)
        let deletedTasks = try await allTasks(originalTasks, in: repository)
        for mutation in try await repository.pendingMutations() {
            try await repository.recordMutationAttempt(
                id: mutation.id,
                at: createdAt.addingTimeInterval(25)
            )
        }
        controller.recordNoteDeletion(note: originalNote, tasks: originalTasks)

        XCTAssertEqual(controller.availableAction, .deleteNote)
        _ = try await controller.undo()

        let restoredNote = try await repository.note(id: note.id)
        let restoredTasks = try await repository.orderedTasks(in: note.id)
        XCTAssertEqual(restoredNote.title, originalNote.title)
        XCTAssertEqual(restoredNote.color, .purple)
        XCTAssertEqual(restoredTasks.map(\.text), originalTasks.map(\.text))
        XCTAssertEqual(restoredTasks.map(\.completion), originalTasks.map(\.completion))
        XCTAssertEqual(restoredTasks.map(\.orderToken), originalTasks.map(\.orderToken))
        XCTAssertGreaterThan(restoredNote.lifecycleVersion, deletedNote.lifecycleVersion)
        for restored in restoredTasks {
            let deleted = try XCTUnwrap(deletedTasks.first { $0.id == restored.id })
            XCTAssertGreaterThan(restored.lifecycleVersion, deleted.lifecycleVersion)
        }

        let activeOutbox = try await repository.pendingMutations()
        let completeOutbox = try await repository.pendingMutations(includeSuperseded: true)
        XCTAssertEqual(Set(activeOutbox.map {
            $0.targetKind.rawValue + ":" + $0.targetStableID
        }).count, 4)
        XCTAssertTrue(completeOutbox.contains { $0.supersededBy != nil })
        XCTAssertNil(controller.availableAction)
    }

    func testUndoDeleteTaskRestoresEntireSubtreeWithoutChangingItsValues() async throws {
        let repository = try makeRepository()
        let (note, tasks) = try await makeNoteWithThreeTasks(in: repository, indentation: [0, 1, 0])
        _ = try await repository.setTaskCompletion(
            id: tasks[1].id,
            completion: .completed(at: createdAt.addingTimeInterval(30))
        )
        let original = Array(try await repository.orderedTasks(in: note.id).prefix(2))
        let controller = ConsequentialActionUndoController(repository: repository)

        _ = try await repository.deleteTasks(Set(original.map(\.id)), in: note.id)
        controller.recordTaskDeletion(noteID: note.id, tasks: original)
        _ = try await controller.undo()

        let restored = try await repository.orderedTasks(in: note.id)
        XCTAssertEqual(Array(restored.prefix(2)).map(\.id), original.map(\.id))
        XCTAssertEqual(Array(restored.prefix(2)).map(\.text), original.map(\.text))
        XCTAssertEqual(Array(restored.prefix(2)).map(\.completion), original.map(\.completion))
        XCTAssertEqual(Array(restored.prefix(2)).map(\.indentLevel), [0, 1])
        XCTAssertEqual(Array(restored.prefix(2)).map(\.orderToken), original.map(\.orderToken))
    }

    func testUndoCompletionAndUncompletionRestoreStateAndExactOriginalOrder() async throws {
        let repository = try makeRepository()
        let (note, tasks) = try await makeNoteWithThreeTasks(in: repository)
        let controller = ConsequentialActionUndoController(repository: repository)

        let beforeCompletion = try await repository.orderedTasks(in: note.id)
        _ = try await repository.setTaskCompletion(
            id: tasks[0].id,
            completion: .completed(at: createdAt.addingTimeInterval(40))
        )
        _ = try await repository.moveTask(
            id: tasks[0].id,
            to: OrderToken.after(tasks[2].orderToken)
        )
        let afterCompletion = try await repository.orderedTasks(in: note.id)
        controller.recordTaskCompletion(
            before: beforeCompletion,
            after: afterCompletion,
            taskID: tasks[0].id
        )
        XCTAssertEqual(controller.availableAction, .completeTask)
        _ = try await controller.undo()
        var restored = try await repository.orderedTasks(in: note.id)
        XCTAssertEqual(restored.map(\.id), beforeCompletion.map(\.id))
        XCTAssertEqual(restored.map(\.orderToken), beforeCompletion.map(\.orderToken))
        XCTAssertFalse(restored[0].isCompleted)

        _ = try await repository.setTaskCompletion(
            id: tasks[0].id,
            completion: .completed(at: createdAt.addingTimeInterval(50))
        )
        _ = try await repository.moveTask(
            id: tasks[0].id,
            to: OrderToken.after(restored[2].orderToken)
        )
        let beforeUncompletion = try await repository.orderedTasks(in: note.id)
        _ = try await repository.setTaskCompletion(id: tasks[0].id, completion: .incomplete)
        _ = try await repository.moveTask(id: tasks[0].id, to: restored[0].orderToken)
        let afterUncompletion = try await repository.orderedTasks(in: note.id)
        controller.recordTaskCompletion(
            before: beforeUncompletion,
            after: afterUncompletion,
            taskID: tasks[0].id
        )
        XCTAssertEqual(controller.availableAction, .uncompleteTask)
        _ = try await controller.undo()
        restored = try await repository.orderedTasks(in: note.id)
        XCTAssertEqual(restored.map(\.id), beforeUncompletion.map(\.id))
        XCTAssertEqual(restored.map(\.orderToken), beforeUncompletion.map(\.orderToken))
        XCTAssertTrue(try XCTUnwrap(restored.first { $0.id == tasks[0].id }).isCompleted)
    }

    func testUndoCompletionIgnoresAnUnrelatedTaskCleanedDuringTheAction() async throws {
        let repository = try makeRepository()
        let (note, tasks) = try await makeNoteWithThreeTasks(in: repository)
        let before = try await repository.orderedTasks(in: note.id)
        let controller = ConsequentialActionUndoController(repository: repository)

        _ = try await repository.setTaskCompletion(
            id: tasks[0].id,
            completion: .completed(at: createdAt.addingTimeInterval(55))
        )
        _ = try await repository.moveTask(
            id: tasks[0].id,
            to: OrderToken.after(tasks[2].orderToken)
        )
        try await repository.deleteTask(id: tasks[1].id)
        controller.recordTaskCompletion(
            before: before,
            after: try await repository.orderedTasks(in: note.id),
            taskID: tasks[0].id
        )

        _ = try await controller.undo()

        let restored = try await repository.orderedTasks(in: note.id)
        let cleaned = try await repository.task(id: tasks[1].id, includingDeleted: true)
        XCTAssertEqual(restored.map(\.id), [tasks[0].id, tasks[2].id])
        XCTAssertEqual(restored[0].orderToken, before[0].orderToken)
        XCTAssertFalse(restored[0].isCompleted)
        XCTAssertEqual(cleaned.lifecycle, .deleted)
    }

    func testUndoReorderRestoresEveryMovedTaskTokenExactly() async throws {
        let repository = try makeRepository()
        let (note, tasks) = try await makeNoteWithThreeTasks(in: repository, indentation: [0, 1, 0])
        let before = try await repository.orderedTasks(in: note.id)
        let firstToken = OrderToken.after(tasks[2].orderToken)
        let childToken = OrderToken.after(firstToken)
        _ = try await repository.applyTaskStructureUpdates(
            in: note.id,
            updates: [
                TaskStructureUpdate(id: tasks[0].id, orderToken: firstToken),
                TaskStructureUpdate(id: tasks[1].id, orderToken: childToken),
            ]
        )
        let after = try await repository.orderedTasks(in: note.id)
        let controller = ConsequentialActionUndoController(repository: repository)
        controller.recordTaskReorder(before: before, after: after)

        XCTAssertEqual(controller.availableAction, .reorderTask)
        _ = try await controller.undo()
        let restored = try await repository.orderedTasks(in: note.id)
        XCTAssertEqual(restored.map(\.id), before.map(\.id))
        XCTAssertEqual(restored.map(\.orderToken), before.map(\.orderToken))
    }

    func testUndoIndentAndOutdentRestoreHierarchyOrderAndCompletion() async throws {
        let repository = try makeRepository()
        let (note, tasks) = try await makeNoteWithThreeTasks(in: repository)
        let controller = ConsequentialActionUndoController(repository: repository)

        _ = try await repository.setTaskCompletion(
            id: tasks[0].id,
            completion: .completed(at: createdAt.addingTimeInterval(58))
        )
        let beforeIndent = try await repository.orderedTasks(in: note.id)
        _ = try await repository.applyTaskStructureUpdates(
            in: note.id,
            updates: [
                TaskStructureUpdate(id: tasks[0].id, completion: .incomplete),
                TaskStructureUpdate(id: tasks[1].id, indentLevel: 1),
            ]
        )
        let afterIndent = try await repository.orderedTasks(in: note.id)
        let recordedIndent = controller.recordTaskIndentation(
            before: beforeIndent,
            after: afterIndent,
            performedOutdent: false
        )
        XCTAssertTrue(recordedIndent)
        XCTAssertEqual(controller.availableAction, .indentTask)

        _ = try await controller.undo()
        var restored = try await repository.orderedTasks(in: note.id)
        XCTAssertEqual(restored.map(\.indentLevel), beforeIndent.map(\.indentLevel))
        XCTAssertEqual(restored.map(\.orderToken), beforeIndent.map(\.orderToken))
        XCTAssertEqual(restored.map(\.completion), beforeIndent.map(\.completion))

        _ = try await repository.setTaskIndentLevel(id: tasks[1].id, indentLevel: 1)
        let beforeOutdent = try await repository.orderedTasks(in: note.id)
        _ = try await repository.applyTaskStructureUpdates(
            in: note.id,
            updates: [TaskStructureUpdate(
                id: tasks[1].id,
                orderToken: OrderToken.after(tasks[2].orderToken),
                indentLevel: 0
            )]
        )
        let afterOutdent = try await repository.orderedTasks(in: note.id)
        let recordedOutdent = controller.recordTaskIndentation(
            before: beforeOutdent,
            after: afterOutdent,
            performedOutdent: true
        )
        XCTAssertTrue(recordedOutdent)
        XCTAssertEqual(controller.availableAction, .outdentTask)

        _ = try await controller.undo()
        restored = try await repository.orderedTasks(in: note.id)
        XCTAssertEqual(restored.map(\.id), beforeOutdent.map(\.id))
        XCTAssertEqual(restored.map(\.indentLevel), beforeOutdent.map(\.indentLevel))
        XCTAssertEqual(restored.map(\.orderToken), beforeOutdent.map(\.orderToken))
    }

    func testUndoColorUsesANewerLocalMutation() async throws {
        let repository = try makeRepository()
        let (note, _) = try await makeNoteWithThreeTasks(in: repository)
        let before = try await repository.note(id: note.id)
        let changed = try await repository.setNoteColor(id: note.id, color: .blue)
        let controller = ConsequentialActionUndoController(repository: repository)
        controller.recordNoteColor(noteID: note.id, previousColor: before.color, newColor: .blue)

        _ = try await controller.undo()
        let restored = try await repository.note(id: note.id)
        XCTAssertEqual(restored.color, before.color)
        XCTAssertGreaterThan(restored.colorVersion, changed.colorVersion)
    }

    func testOneLevelReplacementFreshControllerAndExplicitInvalidations() async throws {
        let workspaceA = UUID(uuidString: "80000000-0000-0000-0000-000000000001")!
        let repository = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(workspaceA)),
            replicaID: replica
        )
        let (note, tasks) = try await makeNoteWithThreeTasks(in: repository)
        let controller = ConsequentialActionUndoController(repository: repository)

        _ = try await repository.setNoteColor(id: note.id, color: .blue)
        controller.recordNoteColor(noteID: note.id, previousColor: .yellow, newColor: .blue)
        let beforeCompletion = try await repository.orderedTasks(in: note.id)
        _ = try await repository.setTaskCompletion(
            id: tasks[0].id,
            completion: .completed(at: createdAt.addingTimeInterval(60))
        )
        controller.recordTaskCompletion(
            before: beforeCompletion,
            after: try await repository.orderedTasks(in: note.id),
            taskID: tasks[0].id
        )
        XCTAssertEqual(controller.availableAction, .completeTask)
        _ = try await controller.undo()
        let noteAfterUndo = try await repository.note(id: note.id)
        XCTAssertEqual(noteAfterUndo.color, .blue)

        let relaunchedController = ConsequentialActionUndoController(repository: repository)
        XCTAssertNil(relaunchedController.availableAction)
        let workspaceBRepository = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(UUID())),
            replicaID: replica
        )
        let workspaceBController = ConsequentialActionUndoController(repository: workspaceBRepository)
        XCTAssertNil(workspaceBController.availableAction)

        controller.recordNoteColor(noteID: note.id, previousColor: .yellow, newColor: .blue)
        controller.discard()
        XCTAssertNil(controller.availableAction)
    }

    func testRemoteChangesNeverCreateUndoAndOnlyAffectedReplacementInvalidatesIt() async throws {
        let repository = try makeRepository()
        let (note, tasks) = try await makeNoteWithThreeTasks(in: repository)
        let controller = ConsequentialActionUndoController(repository: repository)
        _ = try await repository.setNoteColor(id: note.id, color: .blue)
        controller.recordNoteColor(noteID: note.id, previousColor: .yellow, newColor: .blue)

        controller.discardIfAffected(by: [.task(tasks[0].id)])
        XCTAssertEqual(controller.availableAction, .changeNoteColor)

        var remote = try await repository.note(id: note.id)
        try remote.setColor(
            .pink,
            version: VersionStamp(
                logicalCounter: remote.colorVersion.logicalCounter + 10,
                replicaID: ReplicaID(UUID(uuidString: "90000000-0000-0000-0000-000000000001")!)
            )
        )
        let result = try await repository.mergeRemoteNote(
            remote,
            at: createdAt.addingTimeInterval(70)
        )
        XCTAssertEqual(result.changedRecords, [.note(note.id)])
        XCTAssertEqual(controller.availableAction, .changeNoteColor)
        controller.discardIfAffected(by: result.changedRecords)
        XCTAssertNil(controller.availableAction)

        let remoteOnlyController = ConsequentialActionUndoController(repository: repository)
        XCTAssertNil(remoteOnlyController.availableAction)
    }
}

private extension ConsequentialActionUndoTests {
    func makeRepository() throws -> TildoneRepository {
        try TildoneRepository(descriptor: .inMemory(), replicaID: replica, now: { self.createdAt })
    }

    func makeNoteWithThreeTasks(
        in repository: TildoneRepository,
        indentation: [Int] = [0, 0, 0]
    ) async throws -> (Note, [Task]) {
        let note = try await repository.createNote(
            id: NoteID(),
            createdAt: createdAt,
            title: "Preserved title",
            color: .yellow
        )
        let tokens = try ["a", "m", "z"].map(OrderToken.init(rawValue:))
        var tasks: [Task] = []
        for index in 0..<3 {
            tasks.append(try await repository.addTask(
                id: TaskID(),
                to: note.id,
                createdAt: createdAt.addingTimeInterval(TimeInterval(index + 1)),
                text: "Task \(index + 1)",
                orderToken: tokens[index],
                indentLevel: indentation[index]
            ))
        }
        return (note, tasks)
    }

    func clearOutbox(_ repository: TildoneRepository) async throws {
        try await repository.acknowledgeMutations(
            ids: Set(try await repository.pendingMutations().map(\.id))
        )
    }

    func allTasks(_ tasks: [Task], in repository: TildoneRepository) async throws -> [Task] {
        var result: [Task] = []
        for task in tasks {
            result.append(try await repository.task(id: task.id, includingDeleted: true))
        }
        return result
    }
}
