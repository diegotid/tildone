//
//  TildoneiOSTests.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import XCTest
import CloudKit
import Combine
import SwiftUI
import UIKit
import TildoneDomain
import TildonePersistence
import TildoneSync
@testable import Tildone

@MainActor
final class TildoneiOSTests: XCTestCase {
    func testIPhoneTransportIsDisabledUnderTests() {
        XCTAssertFalse(TildoneiOSSyncBootstrapper.featureEnabled)
    }

    func testContentAndSyncPublicationsDoNotInvalidateApplicationShell() async throws {
        let model = try await makeModel()
        var shellPublicationCount = 0
        var overviewPublicationCount = 0
        var syncPublicationCount = 0
        let shellSubscription = model.objectWillChange.sink { shellPublicationCount += 1 }
        let overviewSubscription = model.overviewPresentation.objectWillChange.sink {
            overviewPublicationCount += 1
        }
        let syncSubscription = model.syncPresentation.objectWillChange.sink {
            syncPublicationCount += 1
        }

        _ = try await model.createNote(title: "Isolated")
        model.present(status: SyncStatus(availability: .available, activity: .syncing))

        XCTAssertEqual(shellPublicationCount, 0)
        XCTAssertGreaterThan(overviewPublicationCount, 0)
        XCTAssertGreaterThan(syncPublicationCount, 0)
        withExtendedLifetime([shellSubscription, overviewSubscription, syncSubscription]) {}
    }

    func testNotesArePresentedInMeaningfulEditOrderWithUntitledFallback() async throws {
        let workspace = UUID()
        let repository = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspace)))
        let model = try await makeModel(repository: repository)
        let older = try await repository.createNote(
            id: NoteID(), createdAt: Date(timeIntervalSince1970: 100), title: nil
        )
        let newer = try await repository.createNote(
            id: NoteID(), createdAt: Date(timeIntervalSince1970: 200), title: "Later"
        )
        try await model.reloadNotes()

        XCTAssertEqual(model.notes.map(\.id), [newer.id, older.id])
        XCTAssertEqual(SyncStatusPresentation.title(for: .disabled), "Sync is disabled")
        XCTAssertEqual(older.title, nil)
    }

    func testCreateRenameAndDeleteNoteUsesRepositoryLifecycle() async throws {
        let model = try await makeModel()
        let note = try await model.createNote()
        try await model.rename(noteID: note.id, title: "  Groceries  ")
        XCTAssertEqual(model.notes.first?.title, "Groceries")

        try await model.setColor(noteID: note.id, color: .blue)
        XCTAssertEqual(model.notes.first?.color, .blue)

        try await model.delete(noteID: note.id)
        XCTAssertTrue(model.notes.isEmpty)
    }

    func testCreateButtonPublishesNoteBeforeBackgroundCommitFinishes() async throws {
        let workspace = UUID()
        let repository = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(workspace))
        )
        let model = try await makeModel(repository: repository)

        let noteID = model.createNoteAndPresent(title: "Immediate")

        XCTAssertEqual(model.notes.first?.id, noteID)
        XCTAssertEqual(model.presentation(for: noteID).snapshot.note?.title, "Immediate")

        var persisted: Note?
        for _ in 0..<100 where persisted == nil {
            persisted = try? await repository.note(id: noteID)
            if persisted == nil { await Swift.Task.yield() }
        }
        XCTAssertEqual(try XCTUnwrap(persisted).id, noteID)
    }

    func testOptimisticTaskCompletionReconcilesWithPersistence() async throws {
        let workspace = UUID()
        let repository = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(workspace))
        )
        let model = try await makeModel(repository: repository)
        let note = try await model.createNote(title: "Responsive")
        let createdTask = try await model.addTask(noteID: note.id, text: "Tap", after: [])
        let task = try XCTUnwrap(createdTask)

        let completion = Swift.Task {
            try await model.setCompletion(taskID: task.id, completed: true)
        }
        await Swift.Task.yield()
        XCTAssertTrue(model.presentation(for: note.id).snapshot.tasks[0].isCompleted)
        try await completion.value
        let persistedTask = try await repository.task(id: task.id)
        XCTAssertTrue(persistedTask.isCompleted)
    }

    func testTaskEditingCompletionDeletionAndOrderingUseDomainCommands() async throws {
        let model = try await makeModel()
        let note = try await model.createNote(title: "Checklist")
        let createdFirst = try await model.addTask(noteID: note.id, text: "First", after: [])
        let first = try XCTUnwrap(createdFirst)
        let createdSecond = try await model.addTask(noteID: note.id, text: "Second", after: [first])
        let second = try XCTUnwrap(createdSecond)

        try await model.edit(taskID: second.id, text: "Changed")
        try await model.setCompletion(taskID: first.id, completed: true)
        XCTAssertEqual(model.taskSummaries[note.id]?.completedCount, 1)
        XCTAssertEqual(model.taskSummaries[note.id]?.totalCount, 2)
        XCTAssertEqual(model.taskListTexts[note.id], "First, Changed")
        try await model.move(taskID: second.id, in: [first, second], from: IndexSet(integer: 1), to: 0)
        let reordered = try await model.tasks(in: note.id)
        XCTAssertEqual(reordered.map(\.id), [second.id, first.id])
        XCTAssertEqual(reordered.first?.text, "Changed")
        XCTAssertTrue(reordered.last?.isCompleted == true)

        try await model.delete(taskID: first.id)
        let remaining = try await model.tasks(in: note.id)
        XCTAssertEqual(remaining.map(\.id), [second.id])
    }

    func testIPhoneUndoControlReplacesOneLevelAndClearsForAttentionAndWorkspaceChange() async throws {
        let model = try await makeModel()
        let note = try await model.createNote(title: "Undo")
        let createdTask = try await model.addTask(noteID: note.id, text: "Task", after: [])
        let task = try XCTUnwrap(createdTask)
        XCTAssertNil(model.undoPresentation.action)

        try await model.setColor(noteID: note.id, color: .blue)
        XCTAssertEqual(model.undoPresentation.action, .changeNoteColor)
        XCTAssertFalse(model.undoPresentation.isControlVisible)

        try await model.setCompletion(taskID: task.id, completed: true)
        XCTAssertEqual(model.undoPresentation.action, .completeTask)
        try await model.undoLatestAction()
        let restoredTasks = try await model.tasks(in: note.id)
        XCTAssertFalse(restoredTasks[0].isCompleted)
        XCTAssertEqual(model.notes.first?.color, .blue)
        XCTAssertNil(model.undoPresentation.action)

        try await model.setColor(noteID: note.id, color: .pink)
        model.present(status: SyncStatus(
            availability: .incompatibleRemoteData,
            activity: .attentionNeeded,
            issue: .futureSchema
        ))
        XCTAssertNil(model.undoPresentation.action)

        try await model.setColor(noteID: note.id, color: .green)
        XCTAssertNil(model.undoPresentation.action)

        model.present(status: .disabled)
        try await model.setColor(noteID: note.id, color: .purple)
        XCTAssertEqual(model.undoPresentation.action, .changeNoteColor)
        model.present(status: SyncStatus(
            availability: .accountChanged,
            activity: .attentionNeeded,
            issue: .accountChanged
        ))
        XCTAssertNil(model.undoPresentation.action)

        try await model.openForTesting(workspaceID: UUID())
        try await model.setColor(noteID: note.id, color: .yellow)
        XCTAssertEqual(model.undoPresentation.action, .changeNoteColor)
        try await model.openForTesting(workspaceID: UUID())
        XCTAssertNil(model.undoPresentation.action)
    }

    func testIPhoneUndoCoversEveryScopedActionAndOnlyDeletionShowsThePill() async throws {
        let model = try await makeModel()
        let note = try await model.createNote(title: "Every inverse")
        let createdFirst = try await model.addTask(noteID: note.id, text: "First", after: [])
        let first = try XCTUnwrap(createdFirst)
        let createdSecond = try await model.addTask(noteID: note.id, text: "Second", after: [first])
        let second = try XCTUnwrap(createdSecond)
        let createdThird = try await model.addTask(
            noteID: note.id,
            text: "Third",
            after: [first, second]
        )
        let third = try XCTUnwrap(createdThird)

        try await model.setColor(noteID: note.id, color: .blue)
        assertUndoPresentation(model, action: .changeNoteColor, showsPill: false)
        try await model.undoLatestAction()
        XCTAssertEqual(model.notes.first?.color, note.color)

        try await model.setCompletion(taskID: first.id, completed: true)
        assertUndoPresentation(model, action: .completeTask, showsPill: false)
        try await model.undoLatestAction()
        let afterCompletionUndo = try await model.tasks(in: note.id)
        XCTAssertFalse(try XCTUnwrap(afterCompletionUndo.first).isCompleted)

        try await model.setCompletion(taskID: first.id, completed: true)
        try await model.setCompletion(taskID: first.id, completed: false)
        assertUndoPresentation(model, action: .uncompleteTask, showsPill: false)
        try await model.undoLatestAction()
        let afterUncompletionUndo = try await model.tasks(in: note.id)
        XCTAssertTrue(
            try XCTUnwrap(
                afterUncompletionUndo.first(where: { $0.id == first.id })
            ).isCompleted
        )
        try await model.setCompletion(taskID: first.id, completed: false)

        let beforeMove = try await model.tasks(in: note.id)
        let movedTask = try XCTUnwrap(beforeMove.last)
        let didMove = try await model.move(
            taskID: movedTask.id,
            in: beforeMove,
            from: IndexSet(integer: beforeMove.count - 1),
            to: 0
        )
        XCTAssertTrue(didMove)
        assertUndoPresentation(model, action: .reorderTask, showsPill: false)
        try await model.undoLatestAction()
        let restoredMove = try await model.tasks(in: note.id)
        XCTAssertEqual(restoredMove.map(\.id), beforeMove.map(\.id))
        XCTAssertEqual(restoredMove.map(\.orderToken), beforeMove.map(\.orderToken))

        var beforeIndent = try await model.tasks(in: note.id)
        let indentationTarget = beforeIndent[1]
        let didIndent = try await model.changeIndentation(
            taskID: indentationTarget.id,
            in: beforeIndent,
            outdent: false
        )
        XCTAssertTrue(didIndent)
        assertUndoPresentation(model, action: .indentTask, showsPill: false)
        try await model.undoLatestAction()
        let afterIndentUndo = try await model.tasks(in: note.id)
        XCTAssertEqual(
            try XCTUnwrap(
                afterIndentUndo.first(where: { $0.id == indentationTarget.id })
            ).indentLevel,
            indentationTarget.indentLevel
        )

        beforeIndent = try await model.tasks(in: note.id)
        let didPrepareOutdent = try await model.changeIndentation(
            taskID: indentationTarget.id,
            in: beforeIndent,
            outdent: false
        )
        XCTAssertTrue(didPrepareOutdent)
        let beforeOutdent = try await model.tasks(in: note.id)
        let didOutdent = try await model.changeIndentation(
            taskID: indentationTarget.id,
            in: beforeOutdent,
            outdent: true
        )
        XCTAssertTrue(didOutdent)
        assertUndoPresentation(model, action: .outdentTask, showsPill: false)
        try await model.undoLatestAction()
        let afterOutdentUndo = try await model.tasks(in: note.id)
        XCTAssertEqual(
            try XCTUnwrap(
                afterOutdentUndo.first(where: { $0.id == indentationTarget.id })
            ).indentLevel,
            1
        )

        try await model.delete(taskID: indentationTarget.id)
        assertUndoPresentation(model, action: .deleteTask, showsPill: true)
        try await model.undoLatestAction()
        let afterTaskDeletionUndo = try await model.tasks(in: note.id)
        XCTAssertNotNil(afterTaskDeletionUndo.first(where: { $0.id == indentationTarget.id }))

        try await model.delete(noteID: note.id)
        assertUndoPresentation(model, action: .deleteNote, showsPill: true)
        try await model.undoLatestAction()
        XCTAssertEqual(model.notes.map(\.id), [note.id])
        let afterNoteDeletionUndo = try await model.tasks(in: note.id)
        XCTAssertEqual(Set(afterNoteDeletionUndo.map(\.id)), [first.id, second.id, third.id])
    }

    func testIPhoneUndoLabelsAndDeletionPresentationAreActionSpecific() {
        let presentation = TildoneiOSUndoPresentation()
        let actions: [ConsequentialActionKind] = [
            .deleteNote, .deleteTask, .completeTask, .uncompleteTask,
            .reorderTask, .indentTask, .outdentTask, .changeNoteColor,
        ]

        for action in actions {
            presentation.present(action)
            XCTAssertFalse(action.localizedUndoTitle.isEmpty)
            XCTAssertFalse(action.localizedUndoActionName.isEmpty)
            XCTAssertEqual(
                presentation.isControlVisible,
                action == .deleteNote || action == .deleteTask
            )
        }
    }

    func testIPhoneShakeResponderBecomesFirstResponderAndInvokesUndo() async throws {
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let presentation = TildoneiOSUndoPresentation()
        presentation.present(.completeTask)
        var undoInvocationCount = 0
        let hostingController = UIHostingController(rootView: TildoneiOSUndoOverlay(
            presentation: presentation
        ) {
            undoInvocationCount += 1
        })
        let window = UIWindow(windowScene: scene)
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()

        for _ in 0..<10 { await Swift.Task.yield() }
        let responder = try XCTUnwrap(
            descendantViewControllers(of: hostingController)
                .compactMap { $0 as? TildoneiOSShakeUndoResponder.Controller }
                .first
        )
        XCTAssertTrue(responder.isFirstResponder)

        responder.motionEnded(.motionShake, with: nil)
        for _ in 0..<10 where undoInvocationCount == 0 { await Swift.Task.yield() }
        XCTAssertEqual(undoInvocationCount, 1)
    }

    func testIPhoneHierarchyUsesRecursiveLeafProgressAndInheritsIndentation() async throws {
        let model = try await makeModel()
        let note = try await model.createNote(title: "Hierarchy")
        let createdParent = try await model.addTask(noteID: note.id, text: "Parent", after: [])
        let parent = try XCTUnwrap(createdParent)
        let createdNestedParent = try await model.addTask(
            noteID: note.id,
            text: "Nested parent",
            after: [parent],
            indentLevel: 1
        )
        let nestedParent = try XCTUnwrap(createdNestedParent)
        let createdGrandchild = try await model.addTask(
            noteID: note.id,
            text: "Grandchild",
            after: [parent, nestedParent],
            indentLevel: 2
        )
        let grandchild = try XCTUnwrap(createdGrandchild)
        let createdSibling = try await model.addTask(
            noteID: note.id,
            text: "Sibling",
            after: [parent, nestedParent, grandchild],
            indentLevel: 1
        )
        let sibling = try XCTUnwrap(createdSibling)
        let createdInheritedSibling = try await model.addTask(
            noteID: note.id,
            text: "Inherited sibling",
            after: [parent, nestedParent, grandchild, sibling]
        )
        let inheritedSibling = try XCTUnwrap(createdInheritedSibling)

        XCTAssertEqual(inheritedSibling.indentLevel, 1)
        try await model.setCompletion(taskID: grandchild.id, completed: true)
        try await model.setCompletion(taskID: sibling.id, completed: true)
        try await model.setCompletion(taskID: inheritedSibling.id, completed: true)

        let tasks = try await model.tasks(in: note.id)
        XCTAssertEqual(
            TaskHierarchy.subtaskProgress(at: 0, in: tasks),
            TaskSubtaskProgress(completedCount: 3, totalCount: 3)
        )
        XCTAssertEqual(
            TaskHierarchy.subtaskProgress(at: 1, in: tasks),
            TaskSubtaskProgress(completedCount: 1, totalCount: 1)
        )
        let previews = try XCTUnwrap(model.taskPreviews[note.id])
        XCTAssertEqual(
            previews.first(where: { $0.id == parent.id })?.subtaskProgress,
            TaskSubtaskProgress(completedCount: 3, totalCount: 3)
        )
        XCTAssertEqual(
            previews.first(where: { $0.id == nestedParent.id })?.subtaskProgress,
            TaskSubtaskProgress(completedCount: 1, totalCount: 1)
        )
        XCTAssertEqual(model.taskSummaries[note.id]?.completedCount, 3)
        XCTAssertEqual(model.taskSummaries[note.id]?.totalCount, 3)
    }

    func testGridAndDeckTaskPreviewsPreserveHierarchyOrderAndIndentation() async throws {
        let model = try await makeModel()
        let note = try await model.createNote(title: "Hierarchy preview")
        let createdParent = try await model.addTask(noteID: note.id, text: "Parent", after: [])
        let parent = try XCTUnwrap(createdParent)
        let createdChild = try await model.addTask(
            noteID: note.id,
            text: "Child",
            after: [parent],
            indentLevel: 1
        )
        let child = try XCTUnwrap(createdChild)
        let createdSibling = try await model.addTask(
            noteID: note.id,
            text: "Sibling",
            after: [parent, child]
        )
        let sibling = try XCTUnwrap(createdSibling)

        let didMoveSibling = try await model.move(
            taskID: sibling.id,
            in: [parent, child, sibling],
            from: IndexSet(integer: 2),
            to: 1
        )
        XCTAssertTrue(didMoveSibling)

        let previews = try XCTUnwrap(model.taskPreviews[note.id])
        XCTAssertEqual(previews.map(\.id), [parent.id, sibling.id, child.id])
        XCTAssertEqual(previews.map(\.indentLevel), [0, 1, 1])
    }

    func testCollapsingTaskRowsHidesTheEntireRecursiveSubtree() async throws {
        let model = try await makeModel()
        let note = try await model.createNote(title: "Foldable hierarchy")
        let createdRoot = try await model.addTask(noteID: note.id, text: "Root", after: [])
        let root = try XCTUnwrap(createdRoot)
        let createdChild = try await model.addTask(
            noteID: note.id,
            text: "Child",
            after: [root],
            indentLevel: 1
        )
        let child = try XCTUnwrap(createdChild)
        let createdGrandchild = try await model.addTask(
            noteID: note.id,
            text: "Grandchild",
            after: [root, child],
            indentLevel: 2
        )
        let grandchild = try XCTUnwrap(createdGrandchild)
        let createdSiblingRoot = try await model.addTask(
            noteID: note.id,
            text: "Sibling root",
            after: [root, child, grandchild],
            indentLevel: 0
        )
        let siblingRoot = try XCTUnwrap(createdSiblingRoot)
        let tasks = try await model.tasks(in: note.id)

        XCTAssertEqual(
            ChecklistView.visibleTaskIndices(in: tasks, collapsedTaskIDs: [child.id]),
            [0, 1, 3]
        )
        XCTAssertEqual(
            ChecklistView.visibleTaskIndices(
                in: tasks,
                collapsedTaskIDs: [root.id, child.id]
            ),
            [0, 3]
        )
        XCTAssertEqual(tasks[3].id, siblingRoot.id)
    }

    func testAddingTaskAbovePreservesTheTargetsParentAndIndentation() async throws {
        let model = try await makeModel()
        let note = try await model.createNote(title: "Insert above")
        let createdRoot = try await model.addTask(noteID: note.id, text: "Root", after: [])
        let root = try XCTUnwrap(createdRoot)
        let createdParent = try await model.addTask(
            noteID: note.id,
            text: "Nested parent",
            after: [root],
            indentLevel: 1
        )
        let parent = try XCTUnwrap(createdParent)
        let createdTarget = try await model.addTask(
            noteID: note.id,
            text: "Target",
            after: [root, parent],
            indentLevel: 2
        )
        let target = try XCTUnwrap(createdTarget)

        let createdInserted = try await model.addTask(
            noteID: note.id,
            text: "Inserted",
            before: target.id
        )
        let inserted = try XCTUnwrap(createdInserted)
        let tasks = try await model.tasks(in: note.id)

        XCTAssertEqual(tasks.map(\.id), [root.id, parent.id, inserted.id, target.id])
        XCTAssertEqual(inserted.indentLevel, target.indentLevel)
        XCTAssertEqual(TaskHierarchy.parentID(at: 2, in: tasks), parent.id)
        XCTAssertTrue(TaskHierarchy.isValidPreorder(tasks))
    }

    func testIPhoneIndentationAndReorderingAlwaysMoveAnIntactSubtree() async throws {
        let model = try await makeModel()
        let note = try await model.createNote(title: "Hierarchy")
        let createdFirstRoot = try await model.addTask(
            noteID: note.id,
            text: "First root",
            after: []
        )
        let firstRoot = try XCTUnwrap(createdFirstRoot)
        let createdChild = try await model.addTask(
            noteID: note.id,
            text: "Child",
            after: [firstRoot]
        )
        let child = try XCTUnwrap(createdChild)
        let createdGrandchild = try await model.addTask(
            noteID: note.id,
            text: "Grandchild",
            after: [firstRoot, child]
        )
        let grandchild = try XCTUnwrap(createdGrandchild)
        let createdSecondRoot = try await model.addTask(
            noteID: note.id,
            text: "Second root",
            after: [firstRoot, child, grandchild]
        )
        let secondRoot = try XCTUnwrap(createdSecondRoot)

        var tasks = try await model.tasks(in: note.id)
        let didIndentChild = try await model.changeIndentation(
            taskID: child.id,
            in: tasks,
            outdent: false
        )
        XCTAssertTrue(didIndentChild)
        tasks = try await model.tasks(in: note.id)
        let didIndentGrandchild = try await model.changeIndentation(
            taskID: grandchild.id,
            in: tasks,
            outdent: false
        )
        XCTAssertTrue(didIndentGrandchild)
        tasks = try await model.tasks(in: note.id)
        XCTAssertEqual(tasks.map(\.indentLevel), [0, 1, 1, 0])
        let didIndentGrandchildAgain = try await model.changeIndentation(
            taskID: grandchild.id,
            in: tasks,
            outdent: false
        )
        XCTAssertTrue(didIndentGrandchildAgain)
        tasks = try await model.tasks(in: note.id)
        XCTAssertEqual(tasks.map(\.indentLevel), [0, 1, 2, 0])

        let didMoveRoot = try await model.move(
            taskID: firstRoot.id,
            in: tasks,
            from: IndexSet(integer: 0),
            to: tasks.count
        )
        XCTAssertTrue(didMoveRoot)
        tasks = try await model.tasks(in: note.id)
        XCTAssertEqual(tasks.map(\.id), [secondRoot.id, firstRoot.id, child.id, grandchild.id])
        XCTAssertEqual(tasks.map(\.indentLevel), [0, 0, 1, 2])
        XCTAssertEqual(TaskHierarchy.parentID(at: 2, in: tasks), firstRoot.id)
        XCTAssertEqual(TaskHierarchy.parentID(at: 3, in: tasks), child.id)

        let didDetachChild = try await model.move(
            taskID: child.id,
            in: tasks,
            from: IndexSet(integer: 2),
            to: 0
        )
        XCTAssertFalse(didDetachChild)
        let preservedTasks = try await model.tasks(in: note.id)
        XCTAssertEqual(
            preservedTasks.map(\.id),
            [secondRoot.id, firstRoot.id, child.id, grandchild.id]
        )

        let didOutdentChild = try await model.changeIndentation(
            taskID: child.id,
            in: tasks,
            outdent: true
        )
        XCTAssertTrue(didOutdentChild)
        let outdented = try await model.tasks(in: note.id)
        XCTAssertEqual(outdented.map(\.indentLevel), [0, 0, 0, 1])
        XCTAssertEqual(TaskHierarchy.parentID(at: 3, in: outdented), child.id)

        try await model.delete(taskID: child.id)
        let afterDeletingParent = try await model.tasks(in: note.id)
        XCTAssertEqual(afterDeletingParent.map(\.id), [secondRoot.id, firstRoot.id])
        XCTAssertTrue(TaskHierarchy.isValidPreorder(afterDeletingParent))
    }

    func testIPhoneIndentationChangesOnlyOneLevelPerAction() async throws {
        let model = try await makeModel()
        let note = try await model.createNote(title: "One level at a time")
        let createdRoot = try await model.addTask(noteID: note.id, text: "Root", after: [])
        let root = try XCTUnwrap(createdRoot)
        let createdParent = try await model.addTask(
            noteID: note.id,
            text: "Parent",
            after: [root],
            indentLevel: 1
        )
        let parent = try XCTUnwrap(createdParent)
        let createdGrandchild = try await model.addTask(
            noteID: note.id,
            text: "Grandchild",
            after: [root, parent],
            indentLevel: 2
        )
        let grandchild = try XCTUnwrap(createdGrandchild)
        let createdTarget = try await model.addTask(
            noteID: note.id,
            text: "Target",
            after: [root, parent, grandchild],
            indentLevel: 0
        )
        let target = try XCTUnwrap(createdTarget)

        var tasks = try await model.tasks(in: note.id)
        let didIndent = try await model.changeIndentation(taskID: target.id, in: tasks, outdent: false)
        XCTAssertTrue(didIndent)
        tasks = try await model.tasks(in: note.id)
        XCTAssertEqual(tasks.map(\.indentLevel), [0, 1, 2, 1])

        let didOutdent = try await model.changeIndentation(taskID: target.id, in: tasks, outdent: true)
        XCTAssertTrue(didOutdent)
        tasks = try await model.tasks(in: note.id)
        XCTAssertEqual(tasks.map(\.indentLevel), [0, 1, 2, 0])
    }

    func testRemoteStyleRefreshDoesNotDuplicateRowsAndHidesTombstones() async throws {
        let workspace = UUID()
        let repository = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspace)))
        let model = try await makeModel(repository: repository)
        try await model.openForTesting(workspaceID: workspace)
        let note = try await repository.createNote(id: NoteID(), createdAt: Date(), title: "From Mac")

        try await model.reloadNotes()
        try await model.reloadNotes() // Redelivery/reload is idempotent for presentation.
        XCTAssertEqual(model.notes.map(\.id), [note.id])

        try await repository.deleteNote(id: note.id)
        try await model.reloadNotes()
        XCTAssertTrue(model.notes.isEmpty)
    }

    func testTaskOnlyRemoteDeliveryAdvancesContentRevision() async throws {
        let workspace = UUID()
        let repository = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspace)))
        let model = try await makeModel(repository: repository)
        let note = try await repository.createNote(id: NoteID(), createdAt: Date(), title: "Remote")
        try await model.reloadNotes()
        let notesBeforeTask = model.notes
        let revisionBeforeTask = model.contentRevision

        let stamp = VersionStamp(logicalCounter: 100, replicaID: ReplicaID())
        let remoteTask = TildoneDomain.Task(
            id: TaskID(),
            noteID: note.id,
            createdAt: Date(),
            text: "Arrived separately",
            textVersion: stamp,
            completionVersion: stamp,
            orderToken: try OrderToken(rawValue: "m"),
            orderVersion: stamp,
            lifecycleVersion: stamp
        )
        _ = try await repository.mergeRemoteTask(remoteTask, at: Date())
        try await model.reloadNotes()

        XCTAssertEqual(model.notes, notesBeforeTask)
        XCTAssertGreaterThan(model.contentRevision, revisionBeforeTask)
        let tasks = try await model.tasks(in: note.id)
        XCTAssertEqual(tasks.map(\.id), [remoteTask.id])
    }

    func testOfflineAndAttentionStatesRemainUnderstandable() async throws {
        let model = try await makeModel()
        let note = try await model.createNote()
        _ = try await model.addTask(noteID: note.id, text: "Works offline", after: [])
        let tasks = try await model.tasks(in: note.id)
        XCTAssertEqual(tasks.count, 1)

        for availability in [SyncAvailability.noAccount, .restricted, .adoptionRequired, .zoneResetRequired, .incompatibleRemoteData] {
            let status = SyncStatus(availability: availability, activity: .attentionNeeded)
            XCTAssertFalse(SyncStatusPresentation.title(for: status).isEmpty)
            XCTAssertNotNil(SyncStatusPresentation.detail(for: status))
        }

        let malformed = SyncStatus(
            availability: .available,
            activity: .attentionNeeded,
            issue: .malformedRemoteRecord
        )
        XCTAssertEqual(SyncStatusPresentation.title(for: malformed), "iCloud needs attention")
        XCTAssertEqual(
            SyncStatusPresentation.detail(for: malformed),
            "Some notes from iCloud could not be read. You can keep editing."
        )

        let paused = SyncStatus(availability: .available, activity: .paused)
        XCTAssertEqual(SyncStatusPresentation.title(for: paused), "Sync is paused")
        XCTAssertEqual(SyncStatusPresentation.symbol(for: paused), "pause.circle")
        let pausedDetail = try XCTUnwrap(SyncStatusPresentation.detail(for: paused))
        XCTAssertFalse(pausedDetail.localizedCaseInsensitiveContains("workspace"))

        let available = SyncStatus(
            availability: .available,
            activity: .idle,
            activeDeviceSummary: SyncDeviceSummary(
                currentPlatform: .iPhone,
                otherMacCount: 2
            )
        )
        XCTAssertEqual(available.activeDeviceCount, 3)
        XCTAssertEqual(
            SyncDeviceSummaryPresentation.title(
                for: try XCTUnwrap(available.activeDeviceSummary),
                locale: Locale(identifier: "en_US")
            ),
            "This iPhone and 2 Macs"
        )
        XCTAssertFalse(SyncDeviceSummaryPresentation.shouldShowMacUpgradeGuidance(
            for: try XCTUnwrap(available.activeDeviceSummary)
        ))

        let noMac = SyncDeviceSummary(currentPlatform: .iPhone)
        XCTAssertTrue(SyncDeviceSummaryPresentation.shouldShowMacUpgradeGuidance(for: noMac))
        XCTAssertEqual(
            SyncDeviceSummaryPresentation.macUpgradeGuidance(
                locale: Locale(identifier: "en_US")
            ),
            "To see existing Mac notes here, update Tildone on your Mac to version 2.0 or later. Both devices must use the same iCloud account."
        )
    }

    func testAccountChangeDropsOldWorkspaceImmediately() async throws {
        let workspaceA = UUID()
        let workspaceB = UUID()
        let repositoryA = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceA)))
        let repositoryB = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceB)))
        let model = TildoneiOSApplicationModel(repositoryFactory: { workspace in
            switch workspace {
            case let .account(id) where id == workspaceA: return repositoryA
            case let .account(id) where id == workspaceB: return repositoryB
            default: throw PersistenceError.workspaceMismatch
            }
        }, synchronizationEnabled: false)
        try await model.openForTesting(workspaceID: workspaceA)
        _ = try await model.createNote(title: "Account A")
        XCTAssertFalse(model.notes.isEmpty)

        model.present(status: SyncStatus(availability: .accountChanged, activity: .attentionNeeded))
        XCTAssertFalse(model.hasWorkspace)
        XCTAssertTrue(model.notes.isEmpty)

        try await model.openForTesting(workspaceID: workspaceB)
        XCTAssertTrue(model.notes.isEmpty)
    }

    func testPausedTransportKeepsWorkspaceCRUDAndIsolatesAccountPreference() async throws {
        let suiteName = "TildoneiOSTransportTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let transportStore = SyncTransportStateStore(defaults: defaults)
        let workspaceA = UUID()
        let workspaceB = UUID()
        let repositoryA = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(workspaceA))
        )
        let repositoryB = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(workspaceB))
        )
        let model = TildoneiOSApplicationModel(
            repositoryFactory: { workspace in
                switch workspace {
                case let .account(id) where id == workspaceA: return repositoryA
                case let .account(id) where id == workspaceB: return repositoryB
                default: throw PersistenceError.workspaceMismatch
                }
            },
            synchronizationEnabled: true,
            transportStateStore: transportStore
        )

        try await model.openForTesting(workspaceID: workspaceA)
        model.pauseTransport()
        XCTAssertEqual(model.transportState, .paused)
        XCTAssertEqual(model.syncStatus.activity, .paused)
        XCTAssertTrue(model.hasWorkspace)
        _ = try await model.createNote(title: "Stays local while paused")
        let pendingA = try await repositoryA.pendingMutations()
        XCTAssertEqual(model.notes.count, 1)
        XCTAssertFalse(pendingA.isEmpty)

        try await model.openForTesting(workspaceID: workspaceB)
        XCTAssertEqual(model.transportState, .active)
        XCTAssertTrue(model.notes.isEmpty)

        try await model.openForTesting(workspaceID: workspaceA)
        XCTAssertEqual(model.transportState, .paused)
        XCTAssertEqual(model.notes.count, 1)
    }

    func testWorkspaceResolutionRevalidatesAccountIdentity() async throws {
        let workspaceA = UUID()
        let workspaceB = UUID()
        let repositoryA = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceA)))
        let repositoryB = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceB)))
        var account = CloudAccountSnapshot(state: .available, workspaceID: workspaceA)
        let model = TildoneiOSApplicationModel(
            repositoryFactory: { workspace in
                switch workspace {
                case let .account(id) where id == workspaceA: return repositoryA
                case let .account(id) where id == workspaceB: return repositoryB
                default: throw PersistenceError.workspaceMismatch
                }
            },
            accountResolver: { account },
            synchronizationEnabled: false
        )

        await model.resolveAndOpenCurrentWorkspace()
        _ = try await model.createNote(title: "Private to A")
        XCTAssertEqual(model.notes.count, 1)

        account = CloudAccountSnapshot(state: .available, workspaceID: workspaceB)
        await model.resolveAndOpenCurrentWorkspace()
        XCTAssertTrue(model.hasWorkspace)
        XCTAssertTrue(model.notes.isEmpty)
    }

    func testNotesListReentersExistingNotesWithoutTypedPathNavigation() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TildoneiOS/Views/Notes/Overview/NotesListView.swift")
        let listSource = try String(contentsOf: sourceURL, encoding: .utf8)
        let noteRowURL = sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent("NoteListRow.swift")
        let noteRowSource = try String(contentsOf: noteRowURL, encoding: .utf8)
        let gaugeURL = sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent("NoteCompletionGauge.swift")
        let gaugeSource = try String(contentsOf: gaugeURL, encoding: .utf8)

        XCTAssertTrue(listSource.contains("NavigationLink {"))
        XCTAssertTrue(listSource.contains(".navigationDestination(item: $presentedNoteID)"))
        XCTAssertFalse(listSource.contains("NavigationStack(path: $path)"))
        XCTAssertFalse(listSource.contains(".navigationDestination(for: NoteID.self)"))
        XCTAssertTrue(noteRowSource.contains("NoteCompletionGauge"))
        XCTAssertFalse(noteRowSource.contains("lastMeaningfulEditAt, style: .relative"))
        XCTAssertTrue(gaugeSource.contains(".gaugeStyle(.accessoryCircular)"))
    }

    /// Opt-in, read-only Development diagnostic hosted by the signed-in iOS
    /// simulator. Exact record lookup avoids requiring a queryable CloudKit
    /// index and never modifies the frozen Development schema or record data.
    func testDevelopmentCloudKitNoteLookupWhenExplicitlyEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TILDONE_RUN_DEVELOPMENT_CLOUDKIT_LOOKUP"] == "1" else {
            throw XCTSkip("Development CloudKit lookup is explicitly opt-in")
        }
        let recordName = try XCTUnwrap(
            environment["TILDONE_DEVELOPMENT_RECORD_NAME"],
            "Set the exact Development TDNote record name, including its note- prefix"
        )
        let container = CKContainer(identifier: TildoneCloudSchema.containerIdentifier)
        guard try await container.accountStatus() == .available else {
            throw XCTSkip("A Development iCloud account is required")
        }

        let recordID = CKRecord.ID(
            recordName: recordName,
            zoneID: TildoneCloudSchema.zoneID
        )
        let results = try await container.privateCloudDatabase.records(for: [recordID])
        let record = try XCTUnwrap(results[recordID]).get()
        let decoded = try CloudKitRecordMapper().syncRecord(from: record)
        guard case let .note(note) = decoded else {
            return XCTFail("Expected a TDNote record")
        }

        let displayedTitle = note.title ?? "<nil>"
        print(
            "Development TDNote: title=\(displayedTitle) " +
            "color=\(note.color.rawValue) " +
            "titleCounter=\(note.titleVersion.logicalCounter) " +
            "colorCounter=\(note.colorVersion.logicalCounter)"
        )
        if let expectedTitle = environment["TILDONE_DEVELOPMENT_EXPECTED_TITLE"] {
            XCTAssertEqual(note.title, expectedTitle)
        }
        if let expectedColor = environment["TILDONE_DEVELOPMENT_EXPECTED_COLOR"] {
            XCTAssertEqual(note.color.rawValue, expectedColor)
        }
    }

    private func makeModel(repository: TildoneRepository? = nil) async throws -> TildoneiOSApplicationModel {
        let workspace = UUID()
        let repository = try repository ?? TildoneRepository(descriptor: .inMemory(workspace: .account(workspace)))
        let model = TildoneiOSApplicationModel(
            repositoryFactory: { _ in repository },
            synchronizationEnabled: false
        )
        try await model.openForTesting(workspaceID: workspace)
        return model
    }

    private func assertUndoPresentation(
        _ model: TildoneiOSApplicationModel,
        action: ConsequentialActionKind,
        showsPill: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(model.undoPresentation.action, action, file: file, line: line)
        XCTAssertEqual(model.undoPresentation.isControlVisible, showsPill, file: file, line: line)
    }

    private func descendantViewControllers(of root: UIViewController) -> [UIViewController] {
        root.children + root.children.flatMap(descendantViewControllers)
    }
}
