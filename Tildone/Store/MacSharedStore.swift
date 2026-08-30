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
    @Published private(set) var notes: [MacNoteSnapshot] = []

    private let repository: TildoneRepository
    private var syncCoordinator: TildoneSyncCoordinator?
    private var nextReloadRevision: UInt64 = 0
    private var latestReloadRevision: UInt64 = 0
    private var nextPresentationEditRevision: UInt64 = 0
    private var pendingTaskTextEdits: [TaskID: PendingTaskTextEdit] = [:]
    private var taskTextEditWorkers: [TaskID: Swift.Task<Void, Never>] = [:]
    private var pendingNoteTitleEdits: [NoteID: PendingNoteTitleEdit] = [:]
    private var noteTitleEditWorkers: [NoteID: Swift.Task<Void, Never>] = [:]

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
        latestReloadRevision = reloadRevision
        let domainNotes = try await repository.visibleNotes()
        var snapshots: [MacNoteSnapshot] = []
        snapshots.reserveCapacity(domainNotes.count)
        for note in domainNotes {
            snapshots.append(MacNoteSnapshot(note: note, tasks: try await repository.orderedTasks(in: note.id)))
        }
        guard reloadRevision == latestReloadRevision else { return }
        notes = applyingPendingPresentationEdits(to: snapshots)
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
        await syncCoordinator?.notifyLocalChanges()
    }

    func note(_ id: NoteID) -> MacNoteSnapshot? {
        notes.first { $0.id == id }
    }

    func createNote(createdAt: Date = Date()) async throws -> MacNoteSnapshot {
        let id = NoteID()
        _ = try await repository.createNote(
            id: id,
            createdAt: createdAt,
            title: nil,
            color: NoteColor.current()
        )
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
        guard let note = note(id) else { throw PersistenceError.domainInvariant }
        return note
    }

    func renameNote(_ id: NoteID, to title: String?) async throws {
        await waitForPendingTitleEdit(for: id)
        _ = try await repository.renameNote(id: id, to: title, editedAt: Date())
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
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
        notes = applyingPendingPresentationEdits(to: notes)
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
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
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
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
        return task
    }

    func editTask(_ id: TaskID, text: String) async throws {
        await waitForPendingTaskTextEdit(for: id)
        _ = try await repository.editTask(id: id, text: text)
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
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
        notes = applyingPendingPresentationEdits(to: notes)
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
        var affectedNoteIDs = Set<NoteID>()
        for level in levels {
            let task = try await repository.task(id: level.id)
            affectedNoteIDs.insert(task.noteID)
            _ = try await repository.setTaskIndentLevel(id: level.id, indentLevel: level.level)
        }

        for noteID in affectedNoteIDs {
            try await reconcileTaskHierarchy(
                in: noteID,
                moveCompletedGroupsToEnd: moveCompletedGroupsToEnd
            )
        }

        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

    /// Promotes a task one level while keeping the former parent's remaining
    /// descendants together. Moving only its indent level in place would make
    /// following siblings appear as children of the promoted task.
    func outdentTask(
        _ id: TaskID,
        in noteID: NoteID,
        moveCompletedGroupsToEnd: Bool = false
    ) async throws {
        let ordered = try await repository.orderedTasks(in: noteID)
        guard let index = ordered.firstIndex(where: { $0.id == id }),
              ordered[index].indentLevel > 0,
              let parentIndex = ordered[..<index].lastIndex(
                where: { $0.indentLevel == ordered[index].indentLevel - 1 }
              ) else {
            return
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

        for task in movingSubtree {
            _ = try await repository.setTaskIndentLevel(
                id: task.id,
                indentLevel: task.indentLevel - 1
            )
        }

        let lower = destination > 0 ? remaining[destination - 1].orderToken : nil
        let upper = destination < remaining.count ? remaining[destination].orderToken : nil
        var previous = lower
        for task in movingSubtree {
            let moved = try await repository.moveTask(
                id: task.id,
                to: try OrderToken.between(previous, upper)
            )
            previous = moved.orderToken
        }

        try await reconcileTaskHierarchy(
            in: noteID,
            moveCompletedGroupsToEnd: moveCompletedGroupsToEnd
        )
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
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
            try await reload()
            await syncCoordinator?.notifyLocalChanges()
            return nil
        }

        // Publish the completion immediately. Reordering a large subtree can
        // require several durable order-token updates, but the checkbox/gauge
        // should reflect the user's action before that work finishes.
        try await reload()

        let tasks = try await repository.orderedTasks(in: task.noteID)
        let group = topLevelGroup(containing: id, in: tasks)
        guard !group.isEmpty else { throw PersistenceError.domainInvariant }
        if completed, groupIsComplete(group) {
            let movedToEnd = tasks.suffix(group.count).map(\.id) != group.map(\.id)
            if movedToEnd {
                try await moveCompletedGroupAfterIncompleteGroups(group)
                try await reload()
                await syncCoordinator?.notifyLocalChanges()
                return group.first?.id
            }
        } else if !completed {
            try await restoreGroup(group)
            try await reload()
        }
        await syncCoordinator?.notifyLocalChanges()
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
        let tasks = try await repository.orderedTasks(in: noteID)
        for (index, task) in tasks.enumerated()
        where task.isCompleted && TaskHierarchy.hasSubtasks(at: index, in: tasks) {
            _ = try await repository.setTaskCompletion(id: task.id, completion: .incomplete)
        }

        guard moveCompletedGroupsToEnd else { return }

        // Indentation can expose a previously completed parent as a leaf even
        // though no checkbox was tapped. Re-evaluate every top-level group in
        // this note so that case follows the same completion-ordering rule.
        let completedRootIDs = try topLevelGroups(
            in: try await repository.orderedTasks(in: noteID)
        ).compactMap { group in
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
        for task in group {
            let moved = try await repository.moveTask(
                id: task.id,
                to: try OrderToken.between(previous, nil)
            )
            previous = moved.orderToken
        }
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
        for task in group {
            let moved = try await repository.moveTask(
                id: task.id,
                to: try OrderToken.between(previous, upper)
            )
            previous = moved.orderToken
        }
    }

    private func restoreGroup(_ group: [Task]) async throws {
        for task in group {
            guard let token = CompletedTaskOrderPreference.originalOrderToken(for: task.id) else { continue }
            _ = try await repository.moveTask(id: task.id, to: token)
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
        await syncCoordinator?.notifyLocalChanges()
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
        for task in movedSubtree {
            let moved = try await repository.moveTask(
                id: task.id,
                to: try OrderToken.between(previous, upper)
            )
            previous = moved.orderToken
        }

        try await reload()
        await syncCoordinator?.notifyLocalChanges()
        return true
    }

    func deleteTask(_ id: TaskID) async throws {
        await waitForPendingTaskTextEdit(for: id)
        try await repository.deleteTask(id: id)
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

    func deleteNote(_ id: NoteID) async throws {
        await waitForPendingTitleEdit(for: id)
        for taskID in notes.first(where: { $0.id == id })?.tasks.map(\.id) ?? [] {
            await waitForPendingTaskTextEdit(for: taskID)
        }
        try await repository.deleteNote(id: id)
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
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
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
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
        while let edit = pendingTaskTextEdits[id] {
            do {
                _ = try await repository.editTask(id: id, text: edit.text)
            } catch {
                let latest = pendingTaskTextEdits.removeValue(forKey: id) ?? edit
                taskTextEditWorkers[id] = nil
                try? await reload()
                latest.onFailure(error)
                return
            }

            guard pendingTaskTextEdits[id]?.revision == edit.revision else {
                continue
            }
            pendingTaskTextEdits[id] = nil
            do {
                try await reload()
            } catch {
                taskTextEditWorkers[id] = nil
                edit.onFailure(error)
                return
            }
            await syncCoordinator?.notifyLocalChanges()
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
                try? await reload()
                latest.onFailure(error)
                return
            }

            guard pendingNoteTitleEdits[id]?.revision == edit.revision else {
                continue
            }
            pendingNoteTitleEdits[id] = nil
            do {
                try await reload()
            } catch {
                noteTitleEditWorkers[id] = nil
                edit.onFailure(error)
                return
            }
            await syncCoordinator?.notifyLocalChanges()
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
}
