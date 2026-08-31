//
//  MacSharedStore.swift
//  Tildone
//

import Foundation
import SwiftUI
import TildoneDomain
import TildonePersistence
import TildoneSync

@MainActor
final class MacSharedStore: ObservableObject {
    @Published private var orderedNoteIDs: [NoteID] = []

    var notes: [MacNoteSnapshot] {
        orderedNoteIDs.compactMap { notePresentations[$0]?.snapshot }
    }

    private let repository: TildoneRepository
    private var syncCoordinator: TildoneSyncCoordinator?
    private var nextReloadRevision: UInt64 = 0
    private var latestFullReloadRevision: UInt64 = 0
    private var latestNoteReloadRevisions: [NoteID: UInt64] = [:]
    private var nextPresentationEditRevision: UInt64 = 0
    private var pendingTaskTextEdits: [TaskID: PendingTaskTextEdit] = [:]
    private var taskTextEditWorkers: [TaskID: Swift.Task<Void, Never>] = [:]
    private var pendingNoteTitleEdits: [NoteID: PendingNoteTitleEdit] = [:]
    private var noteTitleEditWorkers: [NoteID: Swift.Task<Void, Never>] = [:]
    private var notePresentations: [NoteID: MacNotePresentation] = [:]

    private struct PendingTaskTextEdit {
        let revision: UInt64
        let text: String
        let onFailure: (Error) -> Void
    }

    private struct PendingNoteTitleEdit {
        let revision: UInt64
        let title: String?
        let onFailure: (Error) -> Void
    }

    init(repository: TildoneRepository) {
        self.repository = repository
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
        publish(applyingPendingPresentationEdits(to: snapshots))
    }

    func reload(_ noteID: NoteID) async throws {
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

    func note(_ id: NoteID) -> MacNoteSnapshot? {
        notePresentations[id]?.snapshot
    }

    func presentation(for id: NoteID) -> MacNotePresentation? {
        notePresentations[id]
    }

    func createNote(createdAt: Date = Date()) async throws -> MacNoteSnapshot {
        let id = NoteID()
        _ = try await repository.createNote(
            id: id,
            createdAt: createdAt,
            title: nil,
            color: NoteColor.current()
        )
        try await reload(id)
        scheduleSyncNotification()
        guard let note = note(id) else { throw PersistenceError.domainInvariant }
        return note
    }

    func renameNote(_ id: NoteID, to title: String?) async throws {
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
        _ = try await repository.setNoteColor(id: id, color: color)
        try await reload(id)
        scheduleSyncNotification()
    }

    func addTask(
        to noteID: NoteID,
        text: String,
        insertingAt position: Int? = nil,
        indentLevel: Int = 0,
        createdAt: Date = Date()
    ) async throws -> Task {
        let tasks = try await repository.orderedTasks(in: noteID)
        let insertionIndex = min(max(position ?? tasks.count, 0), tasks.count)
        let lower = insertionIndex > 0 ? tasks[insertionIndex - 1].orderToken : nil
        let upper = insertionIndex < tasks.count ? tasks[insertionIndex].orderToken : nil
        let task = try await repository.addTask(
            id: TaskID(),
            to: noteID,
            createdAt: createdAt,
            text: text,
            orderToken: try OrderToken.between(lower, upper),
            indentLevel: indentLevel
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
        createdAt: Date = Date()
    ) throws -> Task {
        guard let snapshot = note(noteID) else { throw PersistenceError.missing(.note, noteID.stringValue) }
        let removedBeforeInsertion = snapshot.tasks[..<min(max(position, 0), snapshot.tasks.count)]
            .filter { emptyTaskIDs.contains($0.id) }
            .count
        var remaining = snapshot.tasks.filter { !emptyTaskIDs.contains($0.id) }
        let insertionIndex = min(max(position - removedBeforeInsertion, 0), remaining.count)
        let lower = insertionIndex > 0 ? remaining[insertionIndex - 1].orderToken : nil
        let upper = insertionIndex < remaining.count ? remaining[insertionIndex].orderToken : nil
        let stamp = snapshot.note.lastMeaningfulEditVersion
        let task = Task(
            id: TaskID(),
            noteID: noteID,
            createdAt: createdAt,
            text: "",
            textVersion: stamp,
            completionVersion: stamp,
            orderToken: try OrderToken.between(lower, upper),
            orderVersion: stamp,
            indentLevel: indentLevel,
            indentVersion: stamp,
            lifecycleVersion: stamp
        )
        remaining.insert(task, at: insertionIndex)
        publish(MacNoteSnapshot(note: snapshot.note, tasks: remaining))
        return task
    }

    func commitStagedTaskInsertion(
        _ task: Task,
        deleting emptyTaskIDs: Set<TaskID>
    ) async throws {
        do {
            for id in emptyTaskIDs {
                await waitForPendingTaskTextEdit(for: id)
            }
            _ = try await repository.replaceEmptyTasksAndAddTask(
                deleting: emptyTaskIDs,
                id: task.id,
                to: task.noteID,
                createdAt: task.createdAt,
                text: task.text,
                orderToken: task.orderToken,
                indentLevel: task.indentLevel
            )
            try await reload(task.noteID)
            scheduleSyncNotification()
        } catch {
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

    @discardableResult
    func queueTaskTextEdit(
        _ id: TaskID,
        text: String,
        onFailure: @escaping (Error) -> Void
    ) -> Swift.Task<Void, Never> {
        let revision = nextEditRevision()
        pendingTaskTextEdits[id] = PendingTaskTextEdit(
            revision: revision,
            text: text,
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

    func setTaskIndentLevels(
        _ levels: [(id: TaskID, level: Int)],
        moveCompletedGroupsToEnd: Bool = false
    ) async throws {
        guard let noteID = levels.first.flatMap({ noteID(containing: $0.id) }) else { return }
        let updates = levels.map { TaskStructureUpdate(id: $0.id, indentLevel: $0.level) }
        presentTaskStructureUpdates(updates, in: noteID)
        try await commitTaskStructureUpdates(
            updates,
            in: noteID,
            moveCompletedGroupsToEnd: moveCompletedGroupsToEnd
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
            moveCompletedGroupsToEnd: moveCompletedGroupsToEnd
        )
    }

    func stageTaskIndentLevels(
        _ levels: [(id: TaskID, level: Int)],
        in noteID: NoteID
    ) -> [TaskStructureUpdate] {
        let updates = levels.map { TaskStructureUpdate(id: $0.id, indentLevel: $0.level) }
        presentTaskStructureUpdates(updates, in: noteID)
        return updates
    }

    func stageTaskOutdent(_ id: TaskID, in noteID: NoteID) throws -> [TaskStructureUpdate] {
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
        moveCompletedGroupsToEnd: Bool
    ) async throws {
        do {
            _ = try await repository.applyTaskStructureUpdates(in: noteID, updates: updates)
            try await reconcileTaskHierarchy(
                in: noteID,
                moveCompletedGroupsToEnd: moveCompletedGroupsToEnd
            )
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
        let task = try await repository.setTaskCompletion(
            id: id,
            completion: completed ? .completed(at: Date()) : .incomplete
        )
        guard moveToEndWhenCompleted else {
            try await reload(task.noteID)
            scheduleSyncNotification()
            return nil
        }

        // Publish the completion immediately. Reordering a large subtree can
        // require several durable order-token updates, but the checkbox/gauge
        // should reflect the user's action before that work finishes.
        try await reload(task.noteID)

        let tasks = try await repository.orderedTasks(in: task.noteID)
        let group = topLevelGroup(containing: id, in: tasks)
        guard !group.isEmpty else { throw PersistenceError.domainInvariant }
        if completed, groupIsComplete(group) {
            let movedToEnd = tasks.suffix(group.count).map(\.id) != group.map(\.id)
            if movedToEnd {
                try await moveCompletedGroupAfterIncompleteGroups(group)
                try await reload(task.noteID)
                scheduleSyncNotification()
                return group.first?.id
            }
        } else if !completed {
            try await restoreGroup(group)
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
                    for task in currentTasks {
                        guard let originalToken = CompletedTaskOrderPreference.originalOrderToken(
                            for: task.id
                        ), originalToken != task.orderToken else {
                            continue
                        }
                        _ = try await repository.moveTask(id: task.id, to: originalToken)
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
                for task in tasks {
                    guard let originalOrderToken = CompletedTaskOrderPreference.originalOrderToken(
                        for: task.id
                    ), originalOrderToken != task.orderToken else {
                        continue
                    }
                    _ = try await repository.moveTask(id: task.id, to: originalOrderToken)
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
        let subtreeEnd = reordered[(originalIndex + 1)...].firstIndex {
            $0.indentLevel <= taskDepth
        } ?? reordered.endIndex
        let subtreeRange = originalIndex..<subtreeEnd
        guard !(subtreeRange.contains(destination) || destination == subtreeEnd) else {
            return false
        }

        let movedSubtree = Array(reordered[subtreeRange])
        reordered.removeSubrange(subtreeRange)
        let adjustedDestination = destination > subtreeEnd
            ? destination - movedSubtree.count
            : destination
        guard (0...reordered.count).contains(adjustedDestination) else { return false }

        let lower = adjustedDestination > 0 ? reordered[adjustedDestination - 1].orderToken : nil
        let upper = adjustedDestination < reordered.count ? reordered[adjustedDestination].orderToken : nil
        var previous = lower
        let updates = try movedSubtree.map { task in
            let orderToken = try OrderToken.between(previous, upper)
            previous = orderToken
            return TaskStructureUpdate(id: task.id, orderToken: orderToken)
        }
        presentTaskStructureUpdates(updates, in: noteID)
        _ = try await repository.applyTaskStructureUpdates(in: noteID, updates: updates)

        try await reload(noteID)
        scheduleSyncNotification()
        return true
    }

    func deleteTask(_ id: TaskID) async throws {
        let noteID = try await repository.task(id: id).noteID
        await waitForPendingTaskTextEdit(for: id)
        try await repository.deleteTask(id: id)
        try await reload(noteID)
        scheduleSyncNotification()
    }

    func deleteNote(_ id: NoteID) async throws {
        await waitForPendingTitleEdit(for: id)
        for taskID in notes.first(where: { $0.id == id })?.tasks.map(\.id) ?? [] {
            await waitForPendingTaskTextEdit(for: taskID)
        }
        try await repository.deleteNote(id: id)
        removePresentation(for: id)
        scheduleSyncNotification()
    }

    func cleanEmptyTasks(
        in noteID: NoteID,
        preserving preservedTaskID: TaskID? = nil
    ) async throws {
        for taskID in notes.first(where: { $0.id == noteID })?.tasks.map(\.id) ?? [] {
            await waitForPendingTaskTextEdit(for: taskID)
        }
        for task in try await repository.orderedTasks(in: noteID)
        where task.text.isEmpty && task.id != preservedTaskID {
            try await repository.deleteTask(id: task.id)
        }
        try await reload(noteID)
        scheduleSyncNotification()
    }

}

private extension MacSharedStore {
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
            do {
                _ = try await repository.editTask(id: id, text: edit.text)
            } catch {
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

    func drainNoteTitleEdits(for id: NoteID) async {
        while let edit = pendingNoteTitleEdits[id] {
            do {
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
            let tasks = snapshot.tasks.map { task in
                pendingTaskTextEdits[task.id].map {
                    presentationTask(task, text: $0.text)
                } ?? task
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
            lifecycle: note.lifecycle,
            lifecycleVersion: note.lifecycleVersion,
            lastMeaningfulEditAt: note.lastMeaningfulEditAt,
            lastMeaningfulEditVersion: note.lastMeaningfulEditVersion,
            schemaVersion: note.schemaVersion
        )
    }

    func presentationTask(
        _ task: TildoneDomain.Task,
        text: String
    ) -> TildoneDomain.Task {
        TildoneDomain.Task(
            id: task.id,
            noteID: task.noteID,
            createdAt: task.createdAt,
            text: text,
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
            text: task.text,
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
