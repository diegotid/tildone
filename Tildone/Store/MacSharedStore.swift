//
//  MacSharedStore.swift
//  Tildone
//

import Foundation
import SwiftUI
import TildoneDomain
import TildonePersistence
import TildoneSync

enum MacTaskIndentationUndoDirection: Equatable {
    case indent
    case outdent
}

@MainActor
final class MacSharedStore: ObservableObject {
    @Published private var orderedNoteIDs: [NoteID] = []
    @Published private(set) var undoAction: ConsequentialActionKind?

    var notes: [MacNoteSnapshot] {
        orderedNoteIDs.compactMap { notePresentations[$0]?.snapshot }
    }

    private let repository: TildoneRepository
    private let undoController: ConsequentialActionUndoController
    private var isUndoEnabled = true
    private var indentationPreferenceUndo: (
        taskIDs: Set<TaskID>,
        originalTokens: [TaskID: OrderToken]
    )?
    private var syncCoordinator: TildoneSyncCoordinator?
    private var nextReloadRevision: UInt64 = 0
    private var latestFullReloadRevision: UInt64 = 0
    private var latestNoteReloadRevisions: [NoteID: UInt64] = [:]
    private var nextPresentationEditRevision: UInt64 = 0
    private var pendingTaskTextEdits: [TaskID: PendingTaskTextEdit] = [:]
    private var taskTextEditWorkers: [TaskID: Swift.Task<Void, Never>] = [:]
    private var stagedTaskInsertions: [TaskID: StagedTaskInsertion] = [:]
    private var inFlightTaskTextEdits: [TaskID: Swift.Task<Task, Error>] = [:]
    private var stagedTaskInsertionWaiters: [TaskID: [CheckedContinuation<Void, Never>]] = [:]
    private var pendingNoteTitleEdits: [NoteID: PendingNoteTitleEdit] = [:]
    private var noteTitleEditWorkers: [NoteID: Swift.Task<Void, Never>] = [:]
    private var stagedNoteCreations: [NoteID: MacNoteSnapshot] = [:]
    private var noteCreationWorkers: [NoteID: Swift.Task<Void, Error>] = [:]
    private var notePresentations: [NoteID: MacNotePresentation] = [:]

    private struct PendingTaskTextEdit {
        let revision: UInt64
        let richText: RichText
        let onFailure: (Error) -> Void
    }

    private struct StagedTaskInsertion {
        let task: Task
        let deletingEmptyTaskIDs: Set<TaskID>
        let preservesExistingDepth: Bool
        let orderUpdates: [TaskStructureUpdate]
        let presentationRevision: UInt64
        var splittingTask: (id: TaskID, head: RichText)? = nil
        var sourceTextWrite: Swift.Task<Task, Error>? = nil
        var retiredSourceEdit: PendingTaskTextEdit? = nil
    }

    private struct PendingNoteTitleEdit {
        let revision: UInt64
        let title: String?
        let onFailure: (Error) -> Void
    }

    init(repository: TildoneRepository) {
        self.repository = repository
        undoController = ConsequentialActionUndoController(repository: repository)
    }

    func attachSyncCoordinator(_ coordinator: TildoneSyncCoordinator?) {
        syncCoordinator = coordinator
    }

    func reload() async throws {
        nextReloadRevision &+= 1
        let reloadRevision = nextReloadRevision
        latestFullReloadRevision = reloadRevision
        let domainNotes = try await repository.visibleNotes()
        var snapshots: [MacNoteSnapshot] = []
        snapshots.reserveCapacity(domainNotes.count)
        for note in domainNotes {
            snapshots.append(MacNoteSnapshot(note: note, tasks: try await repository.orderedTasks(in: note.id)))
        }
        guard reloadRevision == nextReloadRevision else { return }
        let persistedIDs = Set(snapshots.map(\.id))
        snapshots.append(contentsOf: stagedNoteCreations.values.filter { !persistedIDs.contains($0.id) })
        snapshots.sort {
            if $0.note.lastMeaningfulEditAt != $1.note.lastMeaningfulEditAt {
                return $0.note.lastMeaningfulEditAt > $1.note.lastMeaningfulEditAt
            }
            return $0.id < $1.id
        }
        publish(applyingPendingPresentationEdits(to: snapshots))
    }

    func reload(_ noteID: NoteID) async throws {
        if let staged = stagedNoteCreations[noteID] {
            publish(applyingPendingPresentationEdits(to: [staged])[0])
            return
        }
        nextReloadRevision &+= 1
        let reloadRevision = nextReloadRevision
        latestNoteReloadRevisions[noteID] = reloadRevision
        do {
            let note = try await repository.note(id: noteID)
            let tasks = try await repository.orderedTasks(in: noteID)
            guard latestNoteReloadRevisions[noteID] == reloadRevision,
                  latestFullReloadRevision < reloadRevision else { return }
            publish(
                applyingPendingPresentationEdits(
                    to: [MacNoteSnapshot(note: note, tasks: tasks)]
                )[0]
            )
        } catch let error as PersistenceError {
            guard case .missing(.note, _) = error else { throw error }
            guard latestNoteReloadRevisions[noteID] == reloadRevision,
                  latestFullReloadRevision < reloadRevision else { return }
            removePresentation(for: noteID)
        }
    }

    func reloadAfterRemoteChange() async throws {
        for note in try await repository.visibleNotes() {
            // Finish a local insert before interpreting remote order or completion for this note.
            guard !stagedTaskInsertions.values.contains(where: { $0.task.noteID == note.id })
            else { continue }
            guard let previousTasks = self.note(note.id)?.tasks else { continue }
            let currentTasks = try await repository.orderedTasks(in: note.id)
            let previousByID = Dictionary(uniqueKeysWithValues: previousTasks.map { ($0.id, $0) })
            let structureChanged = currentTasks.map(\.id) != previousTasks.map(\.id)
                || currentTasks.contains { task in
                    guard let previous = previousByID[task.id] else { return true }
                    return task.orderToken != previous.orderToken
                        || task.indentLevel != previous.indentLevel
                }
            if structureChanged {
                CompletedTaskOrderPreference.removeOriginalOrderTokens(
                    for: previousTasks.map(\.id)
                )
                // A remote move supplies the order to show, even if it also completes a task.
                continue
            }

            guard UserDefaults.standard.bool(
                forKey: AppAppearance.moveCheckedTasksToEndStorageKey
            ) else { continue }

            for task in currentTasks where previousByID[task.id]?.isCompleted == true
                && !task.isCompleted {
                let ordered = try await repository.orderedTasks(in: note.id)
                try await restoreGroup(topLevelGroup(containing: task.id, in: ordered))
            }
            for task in currentTasks where previousByID[task.id]?.isCompleted == false
                && task.isCompleted {
                let ordered = try await repository.orderedTasks(in: note.id)
                let group = topLevelGroup(containing: task.id, in: ordered)
                if groupIsComplete(group),
                   ordered.suffix(group.count).map(\.id) != group.map(\.id) {
                    try await moveCompletedGroupAfterIncompleteGroups(group)
                }
            }
        }
        try await reload()
    }

    /// Removes empty windows left behind by an interrupted or forced quit before
    /// the desktop reconciles persisted notes. Completed notes are intentionally
    /// retained here so their visible grace period is owned by `Note`.
    func prepareForPresentation() async throws {
        try await reload()
        let emptyNoteIDs = notes.lazy.filter(\.isEmpty).map(\.id)
        guard !emptyNoteIDs.isEmpty else { return }
        for id in emptyNoteIDs {
            try await repository.deleteNote(id: id)
        }
        try await reload()
        scheduleSyncNotification()
    }

    /// Permanently removes expired, fully completed top-level task groups and
    /// returns the next time a retained group becomes eligible for deletion.
    func deleteExpiredCompletedTaskGroups(
        now: Date = Date(),
        retentionDays: Int
    ) async throws -> Date? {
        let interval = CompletedTaskRetention.retentionInterval(days: retentionDays)
        var nextExpiration: Date?
        var didDelete = false

        for note in notes {
            let tasks = note.tasks
            var expiredIDs: Set<TaskID> = []
            for rootIndex in tasks.indices where tasks[rootIndex].indentLevel == 0 {
                let group = Array(tasks[TaskHierarchy.subtreeRange(startingAt: rootIndex, in: tasks)])
                let leaves = TaskHierarchy.leafTasks(in: group)
                guard !leaves.isEmpty,
                      leaves.allSatisfy(\.isCompleted),
                      let completedAt = leaves.compactMap(\.completedAt).max() else { continue }
                let expiration = completedAt.addingTimeInterval(interval)
                if expiration <= now {
                    expiredIDs.formUnion(group.map(\.id))
                } else if nextExpiration == nil || expiration < nextExpiration! {
                    nextExpiration = expiration
                }
            }

            guard !expiredIDs.isEmpty else { continue }
            for id in expiredIDs {
                await waitForPendingTaskTextEdit(for: id)
                CompletedTaskOrderPreference.removeOriginalOrderToken(for: id)
            }
            _ = try await repository.deleteTasks(expiredIDs, in: note.id)
            didDelete = true
        }

        if didDelete {
            undoController.discard()
            refreshUndoAction()
            try await reload()
            scheduleSyncNotification()
        }
        return nextExpiration
    }

    func completedTaskDeletionCount(
        now: Date = Date(),
        retentionDays: Int
    ) -> Int {
        let interval = CompletedTaskRetention.retentionInterval(days: retentionDays)
        return notes.reduce(into: 0) { count, note in
            let tasks = note.tasks
            for rootIndex in tasks.indices where tasks[rootIndex].indentLevel == 0 {
                let group = Array(tasks[TaskHierarchy.subtreeRange(startingAt: rootIndex, in: tasks)])
                let leaves = TaskHierarchy.leafTasks(in: group)
                guard !leaves.isEmpty,
                      leaves.allSatisfy(\.isCompleted),
                      let completedAt = leaves.compactMap(\.completedAt).max(),
                      completedAt.addingTimeInterval(interval) <= now else { continue }
                count += group.count
            }
        }
    }

    func note(_ id: NoteID) -> MacNoteSnapshot? {
        notePresentations[id]?.snapshot
    }

    func presentation(for id: NoteID) -> MacNotePresentation? {
        notePresentations[id]
    }

    func createNote(
        createdAt: Date = Date(),
        color: NoteColor? = nil
    ) async throws -> MacNoteSnapshot {
        let id = NoteID()
        let note = try await repository.createNote(
            id: id,
            createdAt: createdAt,
            title: nil,
            color: color ?? NoteColor.current()
        )
        // Publish from the successful mutation result. A concurrent full reload
        // can supersede reload(id) before it publishes, even though the note was
        // durably created, which previously produced a false domain invariant.
        nextReloadRevision &+= 1
        latestNoteReloadRevisions[id] = nextReloadRevision
        let snapshot = MacNoteSnapshot(note: note, tasks: [])
        publish(snapshot)
        scheduleSyncNotification()
        return snapshot
    }

    /// Publishes the empty note before scheduling storage work, so the shortcut
    /// can open and focus its window in the same main-thread turn.
    func createNoteForImmediatePresentation(
        id: NoteID = NoteID(),
        createdAt: Date = Date(),
        color: NoteColor? = nil,
        onFailure: @escaping (Error) -> Void
    ) throws -> MacNoteSnapshot {
        guard note(id) == nil else { throw PersistenceError.duplicateID(.note, id.stringValue) }
        let stamp = VersionStamp(logicalCounter: 0, replicaID: ReplicaID())
        let note = TildoneDomain.Note(
            id: id, createdAt: createdAt, title: nil, titleVersion: stamp,
            color: color ?? NoteColor.current(), colorVersion: stamp,
            lifecycleVersion: stamp, lastMeaningfulEditAt: createdAt,
            lastMeaningfulEditVersion: stamp
        )
        let snapshot = MacNoteSnapshot(note: note, tasks: [])
        stagedNoteCreations[id] = snapshot
        publish(snapshot)
        noteCreationWorkers[id] = Swift.Task { [weak self] in
            guard let self else { return }
            do {
                let persisted = try await repository.createNote(
                    id: id, createdAt: createdAt, title: nil, color: note.color
                )
                stagedNoteCreations[id] = nil
                nextReloadRevision &+= 1
                latestNoteReloadRevisions[id] = nextReloadRevision
                // Retain title drafts, memo conversion and task rows that the
                // user already started while the note itself was being saved.
                publish(applyingPendingPresentationEdits(to: [
                    MacNoteSnapshot(note: persisted, tasks: [])
                ])[0])
                noteCreationWorkers[id] = nil
                scheduleSyncNotification()
            } catch {
                stagedNoteCreations[id] = nil
                noteCreationWorkers[id] = nil
                removePresentation(for: id)
                onFailure(error)
                throw error
            }
        }
        return snapshot
    }

    func waitForNoteCreation(_ id: NoteID) async throws {
        try await noteCreationWorkers[id]?.value
    }

    func renameNote(_ id: NoteID, to title: String?) async throws {
        try await waitForNoteCreation(id)
        await waitForPendingTitleEdit(for: id)
        _ = try await repository.renameNote(id: id, to: title, editedAt: Date())
        try await reload(id)
        scheduleSyncNotification()
    }

    @discardableResult
    func queueNoteTitleEdit(
        _ id: NoteID,
        title: String?,
        onFailure: @escaping (Error) -> Void
    ) -> Swift.Task<Void, Never> {
        let revision = nextEditRevision()
        pendingNoteTitleEdits[id] = PendingNoteTitleEdit(
            revision: revision,
            title: title,
            onFailure: onFailure
        )
        refreshPresentationEdits(for: id)
        if let worker = noteTitleEditWorkers[id] { return worker }
        let worker = Swift.Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.drainNoteTitleEdits(for: id)
        }
        noteTitleEditWorkers[id] = worker
        return worker
    }

    func setColor(_ color: NoteColor, for id: NoteID) async throws {
        try await waitForNoteCreation(id)
        guard let previousColor = note(id)?.color, previousColor != color else { return }
        _ = try await repository.setNoteColor(id: id, color: color)
        undoController.recordNoteColor(
            noteID: id,
            previousColor: previousColor,
            newColor: color
        )
        refreshUndoAction()
        try await reload(id)
        scheduleSyncNotification()
    }

    func setSingleMemoFont(_ font: SingleMemoFont, for id: NoteID) async throws {
        try await waitForNoteCreation(id)
        guard note(id)?.singleMemoFont != font else { return }
        guard ProEntitlement.shared.require(.textStyling, in: id) else { throw ProAccessError.requiresPro }
        _ = try await repository.setSingleMemoFont(id: id, font: font)
        try await reload(id)
        scheduleSyncNotification()
    }

    func setKind(
        _ kind: NoteKind,
        for id: NoteID,
        memoTask: Task? = nil
    ) async throws {
        guard let original = note(id) else { throw PersistenceError.missing(.note, id.stringValue) }
        if kind == .singleTask && (original.kind != .singleTask || memoTask != nil) {
            guard ProEntitlement.shared.require(.singleMemo, in: id) else {
                try? await reload(id)
                throw ProAccessError.requiresPro
            }
        }
        do {
            try await waitForNoteCreation(id)
            let isStagedMemo = memoTask.map { task in
                original.kind == .singleTask && original.tasks.map(\.id) == [task.id]
            } ?? false
            if kind == .singleTask, original.tasks.isEmpty || isStagedMemo {
                let task: Task
                if let memoTask {
                    task = memoTask
                } else {
                    task = Task(
                        id: TaskID(),
                        noteID: id,
                        createdAt: Date(),
                        text: "",
                        textVersion: original.note.lastMeaningfulEditVersion,
                        completionVersion: original.note.lastMeaningfulEditVersion,
                        orderToken: try OrderToken.between(nil, nil),
                        orderVersion: original.note.lastMeaningfulEditVersion,
                        lifecycleVersion: original.note.lastMeaningfulEditVersion
                    )
                }
                _ = try await repository.convertEmptyNoteToSingleTask(
                    id: id,
                    taskID: task.id,
                    createdAt: task.createdAt,
                    orderToken: task.orderToken
                )
            } else if original.kind != kind {
                _ = try await repository.setNoteKind(id: id, kind: kind)
            }
            try await reload(id)
            scheduleSyncNotification()
        } catch {
            try? await reload(id)
            throw error
        }
    }

    /// Stages an editable memo in presentation state so its editor can receive
    /// focus while the same task is being durably created in the background.
    func stageEmptySingleMemo(for id: NoteID) throws -> Task? {
        guard let snapshot = note(id),
              snapshot.kind == .checklist,
              snapshot.tasks.isEmpty else { return nil }
        let note = snapshot.note
        let stamp = note.lastMeaningfulEditVersion
        let task = Task(
            id: TaskID(),
            noteID: id,
            createdAt: Date(),
            text: "",
            textVersion: stamp,
            completionVersion: stamp,
            orderToken: try OrderToken.between(nil, nil),
            orderVersion: stamp,
            lifecycleVersion: stamp
        )
        let memo = TildoneDomain.Note(
            id: note.id,
            createdAt: note.createdAt,
            title: note.title,
            titleVersion: note.titleVersion,
            color: note.color,
            colorVersion: note.colorVersion,
            kind: .singleTask,
            kindVersion: note.kindVersion,
            singleMemoFont: note.singleMemoFont,
            singleMemoFontVersion: note.singleMemoFontVersion,
            lifecycle: note.lifecycle,
            lifecycleVersion: note.lifecycleVersion,
            lastMeaningfulEditAt: note.lastMeaningfulEditAt,
            lastMeaningfulEditVersion: note.lastMeaningfulEditVersion,
            schemaVersion: note.schemaVersion
        )
        publish(MacNoteSnapshot(note: memo, tasks: [task]))
        return task
    }

    func addTask(
        to noteID: NoteID,
        text: String,
        insertingAt position: Int? = nil,
        insertingAfter precedingTaskID: TaskID? = nil,
        indentLevel: Int = 0,
        createdAt: Date = Date()
    ) async throws -> Task {
        try await waitForNoteCreation(noteID)
        let tasks = try await repository.orderedTasks(in: noteID)
        let insertionIndex: Int
        let preservesExistingDepth: Bool
        if let precedingTaskID {
            guard let precedingIndex = tasks.firstIndex(where: { $0.id == precedingTaskID }) else {
                throw PersistenceError.missing(.task, precedingTaskID.stringValue)
            }
            insertionIndex = TaskHierarchy.insertionIndexAfterSubtree(
                startingAt: precedingIndex, in: tasks
            )
            preservesExistingDepth = indentLevel == tasks[precedingIndex].indentLevel
        } else {
            insertionIndex = min(max(position ?? tasks.count, 0), tasks.count)
            preservesExistingDepth = ProFeatureAccess.preservesTaskDepth(indentLevel, at: insertionIndex, in: tasks)
        }
        if indentLevel > 0 && !ProEntitlement.shared.require(
            .subtasks, isAlreadyActive: preservesExistingDepth, in: noteID
        ) { throw ProAccessError.requiresPro }
        let placement = try TaskInsertionOrder.plan(at: insertionIndex, in: tasks)
        let task = try await repository.replaceEmptyTasksAndAddTask(
            deleting: [],
            id: TaskID(),
            to: noteID,
            createdAt: createdAt,
            text: text,
            orderToken: placement.token,
            indentLevel: indentLevel,
            orderUpdates: placement.updates
        )
        try await reload(noteID)
        scheduleSyncNotification()
        return task
    }

    func stageEmptyTaskInsertion(
        in noteID: NoteID,
        at position: Int,
        deleting emptyTaskIDs: Set<TaskID>,
        indentLevel: Int,
        text: String = "",
        createdAt: Date = Date(),
        richText: RichText? = nil
    ) throws -> Task {
        guard let snapshot = note(noteID) else { throw PersistenceError.missing(.note, noteID.stringValue) }
        let preservesExistingDepth = ProFeatureAccess.preservesTaskDepth(
            indentLevel, at: min(max(position, 0), snapshot.tasks.count), in: snapshot.tasks
        )
        if indentLevel > 0 && !ProEntitlement.shared.require(
            .subtasks, isAlreadyActive: preservesExistingDepth, in: noteID
        ) { throw ProAccessError.requiresPro }
        let removedBeforeInsertion = snapshot.tasks[..<min(max(position, 0), snapshot.tasks.count)]
            .filter { emptyTaskIDs.contains($0.id) }
            .count
        var remaining = snapshot.tasks.filter { !emptyTaskIDs.contains($0.id) }
        let insertionIndex = min(max(position - removedBeforeInsertion, 0), remaining.count)
        let placement = try TaskInsertionOrder.plan(at: insertionIndex, in: remaining)
        let updatesByID = Dictionary(uniqueKeysWithValues: placement.updates.map { ($0.id, $0) })
        remaining = remaining.map { task in
            updatesByID[task.id].map { presentationTask(task, applying: $0) } ?? task
        }
        let stamp = snapshot.note.lastMeaningfulEditVersion
        let task = Task(
            id: TaskID(),
            noteID: noteID,
            createdAt: createdAt,
            richText: richText ?? RichText(text: text),
            textVersion: stamp,
            completionVersion: stamp,
            orderToken: placement.token,
            orderVersion: stamp,
            indentLevel: indentLevel,
            indentVersion: stamp,
            lifecycleVersion: stamp
        )
        remaining.insert(task, at: insertionIndex)
        stagedTaskInsertions[task.id] = StagedTaskInsertion(
            task: task,
            deletingEmptyTaskIDs: emptyTaskIDs,
            preservesExistingDepth: preservesExistingDepth,
            orderUpdates: placement.updates,
            presentationRevision: nextEditRevision()
        )
        publish(MacNoteSnapshot(note: snapshot.note, tasks: remaining))
        return task
    }

    func stageTaskSplit(
        _ id: TaskID,
        in noteID: NoteID,
        atUTF16Offset offset: Int
    ) throws -> Task {
        guard let snapshot = note(noteID),
              let index = snapshot.tasks.firstIndex(where: { $0.id == id }),
              let parts = snapshot.tasks[index].richText.split(atUTF16Offset: offset),
              !parts.head.text.isEmpty, !parts.tail.text.isEmpty else {
            throw PersistenceError.domainInvariant
        }
        let source = snapshot.tasks[index]
        let insertion = TaskHierarchy.insertionIndexAfterSubtree(startingAt: index, in: snapshot.tasks)
        let tail = try stageEmptyTaskInsertion(
            in: noteID, at: insertion, deleting: [], indentLevel: source.indentLevel,
            text: parts.tail.text, richText: parts.tail
        )
        // The split itself saves the latest typing value. Retire its queued
        // full-text edit so it cannot overwrite the shortened head afterward.
        stagedTaskInsertions[tail.id]?.retiredSourceEdit = pendingTaskTextEdits.removeValue(forKey: id)
        stagedTaskInsertions[tail.id]?.sourceTextWrite = inFlightTaskTextEdits[id]
        stagedTaskInsertions[tail.id]?.splittingTask = (id, parts.head)
        refreshPresentationEdits(for: noteID)
        return tail
    }

    func commitStagedTaskInsertion(
        _ task: Task,
        deleting emptyTaskIDs: Set<TaskID>
    ) async throws {
        let staged = stagedTaskInsertions[task.id]
        do {
            try await waitForNoteCreation(task.noteID)
            let preservesExistingDepth = staged?.preservesExistingDepth == true
                && staged?.task.noteID == task.noteID
                && staged?.task.indentLevel == task.indentLevel
                && staged?.task.orderToken == task.orderToken
            if task.indentLevel > 0 && !ProEntitlement.shared.require(
                .subtasks, isAlreadyActive: preservesExistingDepth, in: task.noteID
            ) {
                throw ProAccessError.requiresPro
            }
            if let source = staged?.splittingTask {
                // Wait only for a write already submitted before Enter. New
                // edits to either half wait for the atomic split instead.
                _ = try? await staged?.sourceTextWrite?.value
                await waitForStagedTaskInsertion(source.id)
            }
            for id in emptyTaskIDs {
                await waitForPendingTaskTextEdit(for: id)
            }
            for update in staged?.orderUpdates ?? [] {
                await waitForStagedTaskInsertion(update.id)
            }
            _ = try await repository.replaceEmptyTasksAndAddTask(
                deleting: emptyTaskIDs,
                id: task.id,
                to: task.noteID,
                createdAt: task.createdAt,
                text: task.text,
                orderToken: task.orderToken,
                indentLevel: task.indentLevel,
                orderUpdates: staged?.orderUpdates ?? [],
                richText: task.richText,
                splittingTask: staged?.splittingTask
            )
            CompletedTaskOrderPreference.removeOriginalOrderTokens(for: emptyTaskIDs)
            finishStagedTaskInsertion(task.id)
            try await reload(task.noteID)
            scheduleSyncNotification()
        } catch {
            finishStagedTaskInsertion(task.id)
            if let source = staged?.splittingTask,
               let retiredEdit = staged?.retiredSourceEdit,
               pendingTaskTextEdits[source.id] == nil {
                queueTaskTextEdit(source.id, richText: retiredEdit.richText, onFailure: retiredEdit.onFailure)
            }
            try? await reload(task.noteID)
            throw error
        }
    }

    func editTask(_ id: TaskID, text: String) async throws {
        await waitForPendingTaskTextEdit(for: id)
        let task = try await repository.editTask(id: id, text: text)
        try await reload(task.noteID)
        scheduleSyncNotification()
    }

    func editTask(_ id: TaskID, richText: RichText) async throws {
        if let noteID = noteID(containing: id),
           let previous = note(noteID)?.tasks.first(where: { $0.id == id })?.richText,
           previous.text == richText.text && previous.spans != richText.spans {
            guard ProEntitlement.shared.require(.textStyling, in: noteID) else { throw ProAccessError.requiresPro }
        }
        await waitForPendingTaskTextEdit(for: id)
        let task = try await repository.editTask(id: id, richText: richText)
        try await reload(task.noteID)
        scheduleSyncNotification()
    }

    @discardableResult
    func queueTaskTextEdit(
        _ id: TaskID,
        richText: RichText,
        onFailure: @escaping (Error) -> Void
    ) -> Swift.Task<Void, Never> {
        if let noteID = noteID(containing: id),
           let previous = note(noteID)?.tasks.first(where: { $0.id == id })?.richText,
           previous.text == richText.text && previous.spans != richText.spans,
           !ProEntitlement.shared.require(.textStyling, in: noteID) {
            return Swift.Task { onFailure(ProAccessError.requiresPro) }
        }
        let revision = nextEditRevision()
        pendingTaskTextEdits[id] = PendingTaskTextEdit(
            revision: revision,
            richText: richText,
            onFailure: onFailure
        )
        if let noteID = noteID(containing: id) {
            refreshPresentationEdits(for: noteID)
        }
        if let worker = taskTextEditWorkers[id] { return worker }
        let worker = Swift.Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.drainTaskTextEdits(for: id)
        }
        taskTextEditWorkers[id] = worker
        return worker
    }

    @discardableResult
    func queueTaskTextEdit(
        _ id: TaskID,
        text: String,
        onFailure: @escaping (Error) -> Void
    ) -> Swift.Task<Void, Never> {
        queueTaskTextEdit(
            id,
            richText: RichText(text: text),
            onFailure: onFailure
        )
    }

    func setTaskIndentLevels(
        _ levels: [(id: TaskID, level: Int)],
        moveCompletedGroupsToEnd: Bool = false,
        undoDirection: MacTaskIndentationUndoDirection? = nil
    ) async throws {
        guard let noteID = levels.first.flatMap({ noteID(containing: $0.id) }) else { return }
        let currentLevels = Dictionary(uniqueKeysWithValues: (note(noteID)?.tasks ?? []).map { ($0.id, $0.indentLevel) })
        guard levels.contains(where: { currentLevels[$0.id] != $0.level }) else { return }
        guard ProEntitlement.shared.require(.subtasks, in: noteID) else { throw ProAccessError.requiresPro }
        let updates = levels.map { TaskStructureUpdate(id: $0.id, indentLevel: $0.level) }
        presentTaskStructureUpdates(updates, in: noteID)
        try await commitTaskStructureUpdates(
            updates,
            in: noteID,
            moveCompletedGroupsToEnd: moveCompletedGroupsToEnd,
            undoDirection: undoDirection
        )
    }

    /// Promotes a task one level while keeping the former parent's remaining
    /// descendants together. Moving only its indent level in place would make
    /// following siblings appear as children of the promoted task.
    func outdentTask(
        _ id: TaskID,
        in noteID: NoteID,
        moveCompletedGroupsToEnd: Bool = false
    ) async throws {
        let updates = try stageTaskOutdent(id, in: noteID)
        guard !updates.isEmpty else { return }
        try await commitTaskStructureUpdates(
            updates,
            in: noteID,
            moveCompletedGroupsToEnd: moveCompletedGroupsToEnd,
            undoDirection: .outdent
        )
    }

    func stageTaskIndentLevels(
        _ levels: [(id: TaskID, level: Int)],
        in noteID: NoteID
    ) -> [TaskStructureUpdate] {
        guard ProEntitlement.shared.require(.subtasks, in: noteID) else { return [] }
        let updates = levels.map { TaskStructureUpdate(id: $0.id, indentLevel: $0.level) }
        presentTaskStructureUpdates(updates, in: noteID)
        return updates
    }

    func stageTaskOutdent(_ id: TaskID, in noteID: NoteID) throws -> [TaskStructureUpdate] {
        guard ProEntitlement.shared.require(.subtasks, in: noteID) else { return [] }
        guard let ordered = note(noteID)?.tasks,
              let index = ordered.firstIndex(where: { $0.id == id }),
              ordered[index].indentLevel > 0,
              let parentIndex = ordered[..<index].lastIndex(
                where: { $0.indentLevel == ordered[index].indentLevel - 1 }
              ) else {
            return []
        }

        let movingRange = TaskHierarchy.subtreeRange(startingAt: index, in: ordered)
        let movingSubtree = Array(ordered[movingRange])
        let parentID = ordered[parentIndex].id
        var remaining = ordered
        remaining.removeSubrange(movingRange)
        guard let remainingParentIndex = remaining.firstIndex(where: { $0.id == parentID }) else {
            throw PersistenceError.domainInvariant
        }
        let destination = TaskHierarchy.subtreeRange(
            startingAt: remainingParentIndex,
            in: remaining
        ).upperBound
        let lower = destination > 0 ? remaining[destination - 1].orderToken : nil
        let upper = destination < remaining.count ? remaining[destination].orderToken : nil
        var previous = lower
        let updates = try movingSubtree.map { task in
            let orderToken = try OrderToken.between(previous, upper)
            previous = orderToken
            return TaskStructureUpdate(
                id: task.id,
                orderToken: orderToken,
                indentLevel: task.indentLevel - 1
            )
        }
        presentTaskStructureUpdates(updates, in: noteID)
        return updates
    }

    func commitTaskStructureUpdates(
        _ updates: [TaskStructureUpdate],
        in noteID: NoteID,
        moveCompletedGroupsToEnd: Bool,
        undoDirection: MacTaskIndentationUndoDirection? = nil
    ) async throws {
        let existingTasks = try await repository.orderedTasks(in: noteID)
        let oldLevels = Dictionary(uniqueKeysWithValues: existingTasks.map { ($0.id, $0.indentLevel) })
        if updates.contains(where: { $0.indentLevel != nil && $0.indentLevel != oldLevels[$0.id] }) {
            guard ProEntitlement.shared.require(.subtasks, in: noteID) else {
                try? await reload(noteID)
                throw ProAccessError.requiresPro
            }
        }
        let before = undoDirection == nil ? [] : existingTasks
        let taskIDs = Set(existingTasks.map(\.id))
        let originalPreferenceTokens = CompletedTaskOrderPreference.snapshot(for: taskIDs)
        do {
            _ = try await repository.applyTaskStructureUpdates(in: noteID, updates: updates)
            CompletedTaskOrderPreference.removeOriginalOrderTokens(for: taskIDs)
            try await reconcileTaskHierarchy(
                in: noteID,
                moveCompletedGroupsToEnd: moveCompletedGroupsToEnd
            )
            if let undoDirection,
               undoController.recordTaskIndentation(
                   before: before,
                   after: try await repository.orderedTasks(in: noteID),
                   performedOutdent: undoDirection == .outdent
               ) {
                indentationPreferenceUndo = (taskIDs, originalPreferenceTokens)
                refreshUndoAction()
            }
            try await reload(noteID)
            scheduleSyncNotification()
        } catch {
            try? await reload(noteID)
            throw error
        }
    }

    func setTaskCompletion(
        _ id: TaskID,
        completed: Bool,
        moveToEndWhenCompleted: Bool = false
    ) async throws -> TaskID? {
        await waitForPendingTaskTextEdit(for: id)
        let beforeTasks = try await repository.orderedTasks(
            in: try await repository.task(id: id).noteID
        )
        let task = try await repository.setTaskCompletion(
            id: id,
            completion: completed ? .completed(at: Date()) : .incomplete
        )
        guard moveToEndWhenCompleted else {
            try await recordTaskCompletion(before: beforeTasks, taskID: id)
            try await reload(task.noteID)
            scheduleSyncNotification()
            return nil
        }

        // Publish the completion immediately. Reordering a large subtree can
        // require several durable order-token updates, but the checkbox/gauge
        // should reflect the user's action before that work finishes.
        try await reload(task.noteID)
        try await recordTaskCompletion(before: beforeTasks, taskID: id)

        let tasks = try await repository.orderedTasks(in: task.noteID)
        let group = topLevelGroup(containing: id, in: tasks)
        guard !group.isEmpty else { throw PersistenceError.domainInvariant }
        if completed, groupIsComplete(group) {
            let movedToEnd = tasks.suffix(group.count).map(\.id) != group.map(\.id)
            if movedToEnd {
                try await moveCompletedGroupAfterIncompleteGroups(group)
                try await recordTaskCompletion(before: beforeTasks, taskID: id)
                try await reload(task.noteID)
                scheduleSyncNotification()
                return group.first?.id
            }
        } else if !completed {
            try await restoreGroup(group)
            try await recordTaskCompletion(before: beforeTasks, taskID: id)
            try await reload(task.noteID)
        }
        scheduleSyncNotification()
        return nil
    }

    private func topLevelGroup(containing id: TaskID, in tasks: [Task]) -> [Task] {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              let root = tasks[..<(index + 1)].lastIndex(where: { $0.indentLevel == 0 }) else {
            return []
        }
        let end = tasks[(root + 1)...].firstIndex(where: { $0.indentLevel == 0 }) ?? tasks.endIndex
        return Array(tasks[root..<end])
    }

    private func topLevelGroups(in tasks: [Task]) throws -> [[Task]] {
        guard !tasks.isEmpty else { return [] }
        guard tasks[0].indentLevel == 0 else { throw PersistenceError.domainInvariant }

        var groups: [[Task]] = []
        var start = tasks.startIndex
        for index in tasks.indices.dropFirst() where tasks[index].indentLevel == 0 {
            groups.append(Array(tasks[start..<index]))
            start = index
        }
        groups.append(Array(tasks[start..<tasks.endIndex]))
        return groups
    }

    /// A top-level task is complete when every recursive leaf in its subtree is complete.
    /// Parent rows with children intentionally do not need their own completion flag.
    private func groupIsComplete(_ group: [Task]) -> Bool {
        guard group.first?.indentLevel == 0 else { return false }
        let leaves = TaskHierarchy.leafTasks(in: group)
        return !leaves.isEmpty && leaves.allSatisfy(\.isCompleted)
    }

    private func preservesTaskParents(
        in tasks: [Task], applying updates: [TaskStructureUpdate]
    ) -> Bool {
        // Parent identity is derived from order and depth, so validate both together.
        let updatesByID = Dictionary(uniqueKeysWithValues: updates.map { ($0.id, $0) })
        let proposed = tasks.map { task in
            updatesByID[task.id].map { presentationTask(task, applying: $0) } ?? task
        }.sorted(by: Task.orderedBefore)
        guard TaskHierarchy.isValidPreorder(proposed) else { return false }

        let originalParents = Dictionary(uniqueKeysWithValues: tasks.enumerated().map {
            ($0.element.id, TaskHierarchy.parentID(at: $0.offset, in: tasks))
        })
        return proposed.indices.allSatisfy { index in
            TaskHierarchy.parentID(at: index, in: proposed)
                == (originalParents[proposed[index].id] ?? nil)
        }
    }

    private func reconcileTaskHierarchy(
        in noteID: NoteID,
        moveCompletedGroupsToEnd: Bool
    ) async throws {
        var tasks = try await repository.orderedTasks(in: noteID)
        let completionUpdates = tasks.enumerated().compactMap { index, task in
            task.isCompleted && TaskHierarchy.hasSubtasks(at: index, in: tasks)
                ? TaskStructureUpdate(id: task.id, completion: .incomplete)
                : nil
        }
        if !completionUpdates.isEmpty {
            _ = try await repository.applyTaskStructureUpdates(
                in: noteID,
                updates: completionUpdates
            )
            tasks = try await repository.orderedTasks(in: noteID)
        }

        guard moveCompletedGroupsToEnd else { return }

        // Indentation can expose a previously completed parent as a leaf even
        // though no checkbox was tapped. Re-evaluate every top-level group in
        // this note so that case follows the same completion-ordering rule.
        let completedRootIDs = try topLevelGroups(in: tasks).compactMap { group in
            groupIsComplete(group) ? group.first?.id : nil
        }
        for rootID in completedRootIDs {
            let currentTasks = try await repository.orderedTasks(in: noteID)
            let group = topLevelGroup(containing: rootID, in: currentTasks)
            guard !group.isEmpty,
                  groupIsComplete(group),
                  currentTasks.suffix(group.count).map(\.id) != group.map(\.id) else {
                continue
            }
            try await moveGroupToEnd(group)
        }
    }

    private func moveGroupToEnd(_ group: [Task]) async throws {
        guard group.first?.indentLevel == 0,
              group.dropFirst().allSatisfy({ $0.indentLevel > 0 }) else {
            throw PersistenceError.domainInvariant
        }
        for task in group {
            CompletedTaskOrderPreference.recordOriginalOrderToken(task.orderToken, for: task.id)
        }
        let groupIDs = Set(group.map(\.id))
        let currentTasks = try await repository.orderedTasks(in: group[0].noteID)
        var previous = currentTasks.last(where: { !groupIDs.contains($0.id) })?.orderToken
        let updates = try group.map { task in
            let orderToken = try OrderToken.between(previous, nil)
            previous = orderToken
            return TaskStructureUpdate(id: task.id, orderToken: orderToken)
        }
        _ = try await repository.applyTaskStructureUpdates(
            in: group[0].noteID,
            updates: updates
        )
    }

    /// Keeps the completed section at the bottom while retaining a task's
    /// original relative position within that section. A task completed later
    /// must not leapfrog an already completed task that originally followed it.
    private func moveCompletedGroupAfterIncompleteGroups(_ group: [Task]) async throws {
        guard let root = group.first,
              root.indentLevel == 0,
              group.dropFirst().allSatisfy({ $0.indentLevel > 0 }) else {
            throw PersistenceError.domainInvariant
        }
        for task in group {
            CompletedTaskOrderPreference.recordOriginalOrderToken(task.orderToken, for: task.id)
        }
        let groupOriginalToken = CompletedTaskOrderPreference.originalOrderToken(for: root.id)
            ?? root.orderToken
        let groupIDs = Set(group.map(\.id))
        let currentTasks = try await repository.orderedTasks(in: root.noteID)
        let remaining = currentTasks.filter { !groupIDs.contains($0.id) }
        let remainingGroups = try topLevelGroups(in: remaining)

        let destination: Int
        if let laterCompletedGroup = remainingGroups.first(where: { candidate in
            guard groupIsComplete(candidate), let candidateRoot = candidate.first else { return false }
            let candidateOriginalToken = CompletedTaskOrderPreference.originalOrderToken(
                for: candidateRoot.id
            ) ?? candidateRoot.orderToken
            return groupOriginalToken < candidateOriginalToken
        }), let index = remaining.firstIndex(where: { $0.id == laterCompletedGroup[0].id }) {
            destination = index
        } else {
            destination = remaining.endIndex
        }

        let lower = destination > 0 ? remaining[destination - 1].orderToken : nil
        let upper = destination < remaining.count ? remaining[destination].orderToken : nil
        var previous = lower
        let updates = try group.map { task in
            let orderToken = try OrderToken.between(previous, upper)
            previous = orderToken
            return TaskStructureUpdate(id: task.id, orderToken: orderToken)
        }
        _ = try await repository.applyTaskStructureUpdates(in: root.noteID, updates: updates)
    }

    private func restoreGroup(_ group: [Task]) async throws {
        let updates = group.compactMap { task -> TaskStructureUpdate? in
            guard let token = CompletedTaskOrderPreference.originalOrderToken(for: task.id) else {
                return nil
            }
            return TaskStructureUpdate(id: task.id, orderToken: token)
        }
        if let noteID = group.first?.noteID, !updates.isEmpty {
            let tasks = try await repository.orderedTasks(in: noteID)
            guard preservesTaskParents(in: tasks, applying: updates) else {
                CompletedTaskOrderPreference.removeOriginalOrderTokens(for: group.map(\.id))
                return
            }
            _ = try await repository.applyTaskStructureUpdates(in: noteID, updates: updates)
        }
        for task in group where CompletedTaskOrderPreference.originalOrderToken(for: task.id) != nil {
            CompletedTaskOrderPreference.removeOriginalOrderToken(for: task.id)
        }
    }

    func applyCompletedTaskOrdering(enabled: Bool) async throws {
        let notes = try await repository.visibleNotes()
        var hasChanges = false

        if enabled {
            for note in notes {
                let currentTasks = try await repository.orderedTasks(in: note.id)
                let originalTasks = currentTasks.sorted { lhs, rhs in
                    let lhsToken = CompletedTaskOrderPreference.originalOrderToken(for: lhs.id)
                        ?? lhs.orderToken
                    let rhsToken = CompletedTaskOrderPreference.originalOrderToken(for: rhs.id)
                        ?? rhs.orderToken
                    if lhsToken != rhsToken { return lhsToken < rhsToken }
                    return Task.orderedBefore(lhs, rhs)
                }
                let originalGroups = try topLevelGroups(in: originalTasks)
                let incompleteGroups = originalGroups.filter { !groupIsComplete($0) }
                let completeGroups = originalGroups.filter(groupIsComplete)
                let desiredTasks = (incompleteGroups + completeGroups).flatMap { $0 }

                if currentTasks.map(\.id) != desiredTasks.map(\.id) {
                    // Older versions moved completed descendants independently. Restore all
                    // remembered positions first so their real parent/subtree is reconstructed.
                    let restorationUpdates = currentTasks.compactMap { task -> TaskStructureUpdate? in
                        guard let originalToken = CompletedTaskOrderPreference.originalOrderToken(
                            for: task.id
                        ), originalToken != task.orderToken else {
                            return nil
                        }
                        return TaskStructureUpdate(id: task.id, orderToken: originalToken)
                    }
                    if !restorationUpdates.isEmpty {
                        _ = try await repository.applyTaskStructureUpdates(
                            in: note.id, updates: restorationUpdates
                        )
                        hasChanges = true
                    }

                    let restoredTasks = try await repository.orderedTasks(in: note.id)
                    if restoredTasks.map(\.id) != desiredTasks.map(\.id) {
                        for group in completeGroups {
                            try await moveGroupToEnd(group)
                            hasChanges = true
                        }
                    }
                }

                for group in incompleteGroups {
                    for task in group {
                        CompletedTaskOrderPreference.removeOriginalOrderToken(for: task.id)
                    }
                }
                for group in completeGroups {
                    for task in group {
                        let originalToken = CompletedTaskOrderPreference.originalOrderToken(for: task.id)
                            ?? task.orderToken
                        CompletedTaskOrderPreference.recordOriginalOrderToken(
                            originalToken,
                            for: task.id
                        )
                    }
                }
            }
        } else {
            for note in notes {
                let tasks = try await repository.orderedTasks(in: note.id)
                let updates = tasks.compactMap { task -> TaskStructureUpdate? in
                    guard let token = CompletedTaskOrderPreference.originalOrderToken(for: task.id),
                          token != task.orderToken else { return nil }
                    return TaskStructureUpdate(id: task.id, orderToken: token)
                }
                guard !updates.isEmpty else { continue }
                if preservesTaskParents(in: tasks, applying: updates) {
                    _ = try await repository.applyTaskStructureUpdates(
                        in: note.id, updates: updates
                    )
                    hasChanges = true
                }
            }
            CompletedTaskOrderPreference.clearOriginalOrderTokens()
        }

        guard hasChanges else { return }
        try await reload()
        scheduleSyncNotification()
    }

    @discardableResult
    func moveTask(_ id: TaskID, in noteID: NoteID, to destination: Int) async throws -> Bool {
        let ordered = try await repository.orderedTasks(in: noteID)
        var reordered = ordered
        guard (0...reordered.count).contains(destination),
              let originalIndex = reordered.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let taskDepth = reordered[originalIndex].indentLevel
        let subtreeEnd = TaskHierarchy.subtreeRange(
            startingAt: originalIndex,
            in: reordered
        ).upperBound
        let subtreeRange = originalIndex..<subtreeEnd
        guard !(subtreeRange.contains(destination) || destination == subtreeEnd) else {
            return false
        }

        var resolvedDestination = destination
        if taskDepth == 0 {
            // A root task can only be inserted between other root subtrees. A
            // drop line inside a parent's children otherwise makes the moved
            // subtree their new parent, so snap it to the nearest root boundary.
            for rootIndex in reordered.indices where reordered[rootIndex].indentLevel == 0 {
                let rootRange = TaskHierarchy.subtreeRange(startingAt: rootIndex, in: reordered)
                guard rootRange.lowerBound != originalIndex,
                      rootRange.lowerBound < destination,
                      destination < rootRange.upperBound else {
                    continue
                }
                let distanceToStart = destination - rootRange.lowerBound
                let distanceToEnd = rootRange.upperBound - destination
                resolvedDestination = distanceToStart <= distanceToEnd
                    ? rootRange.lowerBound
                    : rootRange.upperBound
                break
            }
        }

        let movedSubtree = Array(reordered[subtreeRange])
        reordered.removeSubrange(subtreeRange)
        let adjustedDestination = resolvedDestination > subtreeEnd
            ? resolvedDestination - movedSubtree.count
            : resolvedDestination
        guard (0...reordered.count).contains(adjustedDestination) else { return false }

        var candidate = reordered
        candidate.insert(contentsOf: movedSubtree, at: adjustedDestination)
        guard TaskHierarchy.isValidPreorder(candidate) else { return false }
        let movedIDs = Set(movedSubtree.map(\.id))
        let originalParents = Dictionary(uniqueKeysWithValues: ordered.enumerated().map {
            ($0.element.id, TaskHierarchy.parentID(at: $0.offset, in: ordered))
        })
        for index in candidate.indices where !movedIDs.contains(candidate[index].id) {
            guard TaskHierarchy.parentID(at: index, in: candidate)
                    == (originalParents[candidate[index].id] ?? nil) else {
                return false
            }
        }

        let placement = try TaskInsertionOrder.plan(at: adjustedDestination, in: reordered)
        let upper = adjustedDestination < reordered.count ? reordered[adjustedDestination].orderToken : nil
        var previous = placement.token
        var updates = placement.updates
        for (index, task) in movedSubtree.enumerated() {
            let orderToken = index == 0 ? placement.token : try OrderToken.between(previous, upper)
            previous = orderToken
            updates.append(TaskStructureUpdate(id: task.id, orderToken: orderToken))
        }
        presentTaskStructureUpdates(updates, in: noteID)
        do {
            _ = try await repository.applyTaskStructureUpdates(in: noteID, updates: updates)
        } catch {
            try? await reload(noteID)
            throw error
        }
        CompletedTaskOrderPreference.removeOriginalOrderTokens(for: ordered.map(\.id))
        undoController.recordTaskReorder(
            before: ordered,
            after: try await repository.orderedTasks(in: noteID)
        )
        refreshUndoAction()

        try await reload(noteID)
        scheduleSyncNotification()
        return true
    }

    func deleteTask(_ id: TaskID) async throws {
        let task = try await repository.task(id: id)
        let noteID = task.noteID
        await waitForPendingTaskTextEdit(for: id)
        try await repository.deleteTask(id: id)
        CompletedTaskOrderPreference.removeOriginalOrderToken(for: id)
        undoController.recordTaskDeletion(noteID: noteID, tasks: [task])
        refreshUndoAction()
        try await reload(noteID)
        scheduleSyncNotification()
    }

    func deleteNote(_ id: NoteID) async throws {
        try await waitForNoteCreation(id)
        guard let deletedSnapshot = note(id) else { return }
        await waitForPendingTitleEdit(for: id)
        for taskID in notes.first(where: { $0.id == id })?.tasks.map(\.id) ?? [] {
            await waitForPendingTaskTextEdit(for: taskID)
        }
        try await repository.deleteNote(id: id)
        undoController.recordNoteDeletion(
            note: deletedSnapshot.note,
            tasks: deletedSnapshot.tasks
        )
        refreshUndoAction()
        removePresentation(for: id)
        scheduleSyncNotification()
    }

    func undoLatestAction() async throws {
        let action = try await undoController.undo()
        if action == .indentTask || action == .outdentTask,
           let indentationPreferenceUndo {
            CompletedTaskOrderPreference.restore(
                indentationPreferenceUndo.originalTokens,
                for: indentationPreferenceUndo.taskIDs
            )
        }
        refreshUndoAction()
        try await reload()
        scheduleSyncNotification()
    }

    func discardUndo() {
        undoController.discard()
        refreshUndoAction()
    }

    func discardUndoIfAffected(by records: Set<DomainRecordID>) {
        undoController.discardIfAffected(by: records)
        refreshUndoAction()
    }

    func setUndoEnabled(_ enabled: Bool) {
        isUndoEnabled = enabled
        if !enabled { undoController.discard() }
        refreshUndoAction()
    }

    func cleanEmptyTasks(
        in noteID: NoteID,
        preserving preservedTaskID: TaskID? = nil
    ) async throws {
        guard let snapshot = note(noteID), snapshot.kind != .singleTask,
              snapshot.tasks.contains(where: {
                  $0.text.isEmpty && $0.id != preservedTaskID
              }) else { return }
        for taskID in notes.first(where: { $0.id == noteID })?.tasks.map(\.id) ?? [] {
            await waitForPendingTaskTextEdit(for: taskID)
        }
        for task in try await repository.orderedTasks(in: noteID)
        where task.text.isEmpty && task.id != preservedTaskID {
            try await repository.deleteTask(id: task.id)
        }
        CompletedTaskOrderPreference.removeOriginalOrderTokens(
            for: snapshot.tasks.filter { $0.text.isEmpty && $0.id != preservedTaskID }.map(\.id)
        )
        try await reload(noteID)
        scheduleSyncNotification()
    }

}

private extension MacSharedStore {
    func recordTaskCompletion(before: [Task], taskID: TaskID) async throws {
        guard let noteID = before.first?.noteID else { return }
        undoController.recordTaskCompletion(
            before: before,
            after: try await repository.orderedTasks(in: noteID),
            taskID: taskID
        )
        refreshUndoAction()
    }

    func refreshUndoAction() {
        if !isUndoEnabled { undoController.discard() }
        let action = undoController.availableAction
        if action != .indentTask && action != .outdentTask {
            indentationPreferenceUndo = nil
        }
        undoAction = action
    }

    func nextEditRevision() -> UInt64 {
        nextPresentationEditRevision &+= 1
        return nextPresentationEditRevision
    }

    func waitForPendingTaskTextEdit(for id: TaskID) async {
        while let worker = taskTextEditWorkers[id] {
            await worker.value
        }
    }

    func waitForPendingTitleEdit(for id: NoteID) async {
        while let worker = noteTitleEditWorkers[id] {
            await worker.value
        }
    }

    func drainTaskTextEdits(for id: TaskID) async {
        let editedNoteID = noteID(containing: id)
        while let edit = pendingTaskTextEdits[id] {
            await waitForStagedTaskInsertion(id)
            if let split = stagedTaskInsertions.values.first(where: { $0.splittingTask?.id == id }) {
                await waitForStagedTaskInsertion(split.task.id)
            }
            guard pendingTaskTextEdits[id]?.revision == edit.revision else { continue }
            do {
                let write = Swift.Task { try await repository.editTask(id: id, richText: edit.richText) }
                inFlightTaskTextEdits[id] = write
                defer { inFlightTaskTextEdits[id] = nil }
                _ = try await write.value
            } catch {
                guard pendingTaskTextEdits[id]?.revision == edit.revision else { continue }
                let latest = pendingTaskTextEdits.removeValue(forKey: id) ?? edit
                taskTextEditWorkers[id] = nil
                if let editedNoteID { try? await reload(editedNoteID) }
                latest.onFailure(error)
                return
            }

            guard pendingTaskTextEdits[id]?.revision == edit.revision else {
                continue
            }
            pendingTaskTextEdits[id] = nil
            do {
                if let editedNoteID { try await reload(editedNoteID) }
            } catch {
                taskTextEditWorkers[id] = nil
                edit.onFailure(error)
                return
            }
            scheduleSyncNotification()
        }
        taskTextEditWorkers[id] = nil
    }

    func waitForStagedTaskInsertion(_ id: TaskID) async {
        guard stagedTaskInsertions[id] != nil else { return }
        await withCheckedContinuation { continuation in
            if stagedTaskInsertions[id] != nil {
                stagedTaskInsertionWaiters[id, default: []].append(continuation)
            } else {
                continuation.resume()
            }
        }
    }

    func finishStagedTaskInsertion(_ id: TaskID) {
        stagedTaskInsertions[id] = nil
        for waiter in stagedTaskInsertionWaiters.removeValue(forKey: id) ?? [] {
            waiter.resume()
        }
    }

    func drainNoteTitleEdits(for id: NoteID) async {
        while let edit = pendingNoteTitleEdits[id] {
            do {
                try await waitForNoteCreation(id)
                _ = try await repository.renameNote(id: id, to: edit.title, editedAt: Date())
            } catch {
                let latest = pendingNoteTitleEdits.removeValue(forKey: id) ?? edit
                noteTitleEditWorkers[id] = nil
                try? await reload(id)
                latest.onFailure(error)
                return
            }

            guard pendingNoteTitleEdits[id]?.revision == edit.revision else {
                continue
            }
            pendingNoteTitleEdits[id] = nil
            do {
                try await reload(id)
            } catch {
                noteTitleEditWorkers[id] = nil
                edit.onFailure(error)
                return
            }
            scheduleSyncNotification()
        }
        noteTitleEditWorkers[id] = nil
    }

    func applyingPendingPresentationEdits(
        to snapshots: [MacNoteSnapshot]
    ) -> [MacNoteSnapshot] {
        snapshots.map { snapshot in
            let note = pendingNoteTitleEdits[snapshot.id].map {
                presentationNote(snapshot.note, title: $0.title)
            } ?? snapshot.note
            let staged = stagedTaskInsertions.values
                .filter { $0.task.noteID == snapshot.id }
                .sorted { $0.presentationRevision < $1.presentationRevision }
            let hiddenTaskIDs = staged.reduce(into: Set<TaskID>()) {
                $0.formUnion($1.deletingEmptyTaskIDs)
            }
            var visibleTasks = snapshot.tasks.filter { !hiddenTaskIDs.contains($0.id) }
            let persistedIDs = Set(visibleTasks.map(\.id))
            visibleTasks.append(contentsOf: staged.map(\.task).filter { !persistedIDs.contains($0.id) })
            var orderUpdates: [TaskID: TaskStructureUpdate] = [:]
            for insertion in staged {
                for update in insertion.orderUpdates { orderUpdates[update.id] = update }
            }
            visibleTasks = visibleTasks.map { task in
                orderUpdates[task.id].map { presentationTask(task, applying: $0) } ?? task
            }
            visibleTasks.sort(by: Task.orderedBefore)
            let tasks = visibleTasks.map { task in
                let splitHead = staged.compactMap(\.splittingTask).last(where: { $0.id == task.id })?.head
                let richText = pendingTaskTextEdits[task.id]?.richText ?? splitHead
                return richText.map { presentationTask(task, richText: $0) } ?? task
            }
            return MacNoteSnapshot(note: note, tasks: tasks)
        }
    }

    func publish(_ snapshots: [MacNoteSnapshot]) {
        let incomingIDs = Set(snapshots.map(\.id))
        for id in notePresentations.keys where !incomingIDs.contains(id) {
            notePresentations[id] = nil
        }
        for snapshot in snapshots {
            if let presentation = notePresentations[snapshot.id] {
                presentation.update(snapshot)
            } else {
                notePresentations[snapshot.id] = MacNotePresentation(snapshot: snapshot)
            }
        }
        let ids = snapshots.map(\.id)
        if orderedNoteIDs != ids {
            orderedNoteIDs = ids
        }
    }

    func publish(_ snapshot: MacNoteSnapshot) {
        if let presentation = notePresentations[snapshot.id] {
            presentation.update(snapshot)
        } else {
            notePresentations[snapshot.id] = MacNotePresentation(snapshot: snapshot)
        }
        var ids = orderedNoteIDs
        if !ids.contains(snapshot.id) {
            ids.append(snapshot.id)
        }
        ids.sort { lhs, rhs in
            guard let left = notePresentations[lhs]?.snapshot,
                  let right = notePresentations[rhs]?.snapshot else { return lhs < rhs }
            if left.note.lastMeaningfulEditAt != right.note.lastMeaningfulEditAt {
                return left.note.lastMeaningfulEditAt > right.note.lastMeaningfulEditAt
            }
            return lhs < rhs
        }
        if orderedNoteIDs != ids {
            orderedNoteIDs = ids
        }
    }

    func removePresentation(for id: NoteID) {
        notePresentations[id] = nil
        orderedNoteIDs.removeAll { $0 == id }
    }

    func noteID(containing taskID: TaskID) -> NoteID? {
        notePresentations.first { $0.value.snapshot.tasks.contains { $0.id == taskID } }?.key
    }

    func refreshPresentationEdits(for noteID: NoteID) {
        guard let snapshot = note(noteID) else { return }
        publish(applyingPendingPresentationEdits(to: [snapshot])[0])
    }

    func presentTaskStructureUpdates(
        _ updates: [TaskStructureUpdate],
        in noteID: NoteID
    ) {
        guard let snapshot = note(noteID) else { return }
        let byID = Dictionary(uniqueKeysWithValues: updates.map { ($0.id, $0) })
        let tasks = snapshot.tasks.map { task in
            byID[task.id].map { presentationTask(task, applying: $0) } ?? task
        }.sorted(by: Task.orderedBefore)
        publish(MacNoteSnapshot(note: snapshot.note, tasks: tasks))
    }

    func scheduleSyncNotification() {
        guard let syncCoordinator else { return }
        Swift.Task { await syncCoordinator.notifyLocalChanges() }
    }

    func presentationNote(
        _ note: TildoneDomain.Note,
        title: String?
    ) -> TildoneDomain.Note {
        TildoneDomain.Note(
            id: note.id,
            createdAt: note.createdAt,
            title: title,
            titleVersion: note.titleVersion,
            color: note.color,
            colorVersion: note.colorVersion,
            kind: note.kind,
            kindVersion: note.kindVersion,
            singleMemoFont: note.singleMemoFont,
            singleMemoFontVersion: note.singleMemoFontVersion,
            lifecycle: note.lifecycle,
            lifecycleVersion: note.lifecycleVersion,
            lastMeaningfulEditAt: note.lastMeaningfulEditAt,
            lastMeaningfulEditVersion: note.lastMeaningfulEditVersion,
            schemaVersion: note.schemaVersion
        )
    }

    func presentationTask(
        _ task: TildoneDomain.Task,
        richText: RichText
    ) -> TildoneDomain.Task {
        TildoneDomain.Task(
            id: task.id,
            noteID: task.noteID,
            createdAt: task.createdAt,
            richText: richText,
            textVersion: task.textVersion,
            completion: task.completion,
            completionVersion: task.completionVersion,
            orderToken: task.orderToken,
            orderVersion: task.orderVersion,
            indentLevel: task.indentLevel,
            indentVersion: task.indentVersion,
            lifecycle: task.lifecycle,
            lifecycleVersion: task.lifecycleVersion,
            schemaVersion: task.schemaVersion
        )
    }

    func presentationTask(
        _ task: TildoneDomain.Task,
        applying update: TaskStructureUpdate
    ) -> TildoneDomain.Task {
        TildoneDomain.Task(
            id: task.id,
            noteID: task.noteID,
            createdAt: task.createdAt,
            richText: task.richText,
            textVersion: task.textVersion,
            completion: update.completion ?? task.completion,
            completionVersion: task.completionVersion,
            orderToken: update.orderToken ?? task.orderToken,
            orderVersion: task.orderVersion,
            indentLevel: update.indentLevel ?? task.indentLevel,
            indentVersion: task.indentVersion,
            lifecycle: task.lifecycle,
            lifecycleVersion: task.lifecycleVersion,
            schemaVersion: task.schemaVersion
        )
    }
}
