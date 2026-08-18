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

    init(repository: TildoneRepository) {
        self.repository = repository
    }

    func attachSyncCoordinator(_ coordinator: TildoneSyncCoordinator?) {
        syncCoordinator = coordinator
    }

    func reload() async throws {
        let domainNotes = try await repository.visibleNotes()
        var snapshots: [MacNoteSnapshot] = []
        snapshots.reserveCapacity(domainNotes.count)
        for note in domainNotes {
            snapshots.append(MacNoteSnapshot(note: note, tasks: try await repository.orderedTasks(in: note.id)))
        }
        notes = snapshots
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
        _ = try await repository.renameNote(id: id, to: title, editedAt: Date())
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
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
            orderToken: try OrderToken.between(lower, upper)
        )
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
        return task
    }

    func editTask(_ id: TaskID, text: String) async throws {
        _ = try await repository.editTask(id: id, text: text)
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

    func setTaskCompletion(
        _ id: TaskID,
        completed: Bool,
        moveToEndWhenCompleted: Bool = false
    ) async throws {
        let task = try await repository.setTaskCompletion(
            id: id,
            completion: completed ? .completed(at: Date()) : .incomplete
        )
        if completed && moveToEndWhenCompleted {
            CompletedTaskOrderPreference.recordOriginalOrderToken(task.orderToken, for: id)
            let tasks = try await repository.orderedTasks(in: task.noteID)
            guard let originalOrderToken = CompletedTaskOrderPreference.originalOrderToken(for: id) else {
                throw PersistenceError.domainInvariant
            }
            let nextCompletedTask = tasks
                .compactMap { candidate -> (task: Task, originalOrderToken: OrderToken)? in
                    guard candidate.id != id,
                          candidate.isCompleted,
                          let originalOrderToken = CompletedTaskOrderPreference.originalOrderToken(
                            for: candidate.id
                          ) else {
                        return nil
                    }
                    return (candidate, originalOrderToken)
                }
                .filter { $0.originalOrderToken > originalOrderToken }
                .min { $0.originalOrderToken < $1.originalOrderToken }?
                .task
            if let nextCompletedTask,
               let nextIndex = tasks.firstIndex(where: { $0.id == nextCompletedTask.id }) {
                let lower = tasks[..<nextIndex]
                    .last(where: { $0.id != id })?
                    .orderToken
                _ = try await repository.moveTask(
                    id: id,
                    to: try OrderToken.between(lower, nextCompletedTask.orderToken)
                )
            } else if tasks.last?.id != id {
                let lower = tasks.last(where: { $0.id != id })?.orderToken
                _ = try await repository.moveTask(
                    id: id,
                    to: try OrderToken.between(lower, nil)
                )
            }
        } else if !completed,
                  moveToEndWhenCompleted,
                  let originalOrderToken = CompletedTaskOrderPreference.originalOrderToken(for: id) {
            if originalOrderToken != task.orderToken {
                _ = try await repository.moveTask(id: id, to: originalOrderToken)
            }
            CompletedTaskOrderPreference.removeOriginalOrderToken(for: id)
        }
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

    func applyCompletedTaskOrdering(enabled: Bool) async throws {
        let notes = try await repository.visibleNotes()
        var hasChanges = false

        if enabled {
            for note in notes {
                let completedTasks = try await repository.orderedTasks(in: note.id)
                    .filter(\.isCompleted)
                for task in completedTasks {
                    CompletedTaskOrderPreference.recordOriginalOrderToken(
                        task.orderToken,
                        for: task.id
                    )
                }
                for task in completedTasks {
                    let tasks = try await repository.orderedTasks(in: note.id)
                    guard tasks.last?.id != task.id else { continue }
                    let lower = tasks.last(where: { $0.id != task.id })?.orderToken
                    _ = try await repository.moveTask(
                        id: task.id,
                        to: try OrderToken.between(lower, nil)
                    )
                    hasChanges = true
                }
            }
        } else {
            for note in notes {
                let completedTasks = try await repository.orderedTasks(in: note.id)
                    .filter(\.isCompleted)
                for task in completedTasks {
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
        var reordered = try await repository.orderedTasks(in: noteID)
        guard (0...reordered.count).contains(destination),
              let originalIndex = reordered.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let moved = reordered.remove(at: originalIndex)
        let adjustedDestination = destination > originalIndex ? destination - 1 : destination
        reordered.insert(moved, at: adjustedDestination)
        guard adjustedDestination != originalIndex else { return false }

        let lower = adjustedDestination > 0 ? reordered[adjustedDestination - 1].orderToken : nil
        let upper = adjustedDestination + 1 < reordered.count
            ? reordered[adjustedDestination + 1].orderToken
            : nil
        _ = try await repository.moveTask(id: id, to: try OrderToken.between(lower, upper))
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
        return true
    }

    func deleteTask(_ id: TaskID) async throws {
        try await repository.deleteTask(id: id)
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

    func deleteNote(_ id: NoteID) async throws {
        try await repository.deleteNote(id: id)
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

    func cleanEmptyTasks(in noteID: NoteID) async throws {
        for task in try await repository.orderedTasks(in: noteID) where task.text.isEmpty {
            try await repository.deleteTask(id: task.id)
        }
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

}
