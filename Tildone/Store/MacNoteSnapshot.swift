//
//  MacNoteSnapshot.swift
//  Tildone
//

import Foundation
import TildoneDomain

struct MacNoteSnapshot: Identifiable {
    let note: TildoneDomain.Note
    let tasks: [TildoneDomain.Task]

    var id: NoteID { note.id }
    var createdAt: Date { note.createdAt }
    var title: String? { note.title }
    var color: NoteColor { note.color }
    var kind: NoteKind { note.kind }
    var singleMemoFont: SingleMemoFont { note.singleMemoFont }
    var singleTask: Task? { tasks.first }
    var isEmpty: Bool {
        if kind == .singleTask { return singleTask?.text.isEmpty != false }
        return tasks.isEmpty && title == nil
    }
    var progressTasks: [Task] {
        kind == .singleTask ? Array(tasks.prefix(1)) : TaskHierarchy.leafTasks(in: tasks)
    }
    var isComplete: Bool {
        !progressTasks.isEmpty && progressTasks.allSatisfy(\.isCompleted)
    }
    var isDeletable: Bool { isEmpty || isComplete }
    var pendingTasks: [Task] { progressTasks.filter { !$0.isCompleted } }
    var completedAt: Date? {
        guard isComplete else { return nil }
        return progressTasks.compactMap(\.completedAt).max()
    }

    /// Retains the released window-autosave key for migrated notes.
    var legacyWindowKey: String { createdAt.ISO8601Format() }
}
