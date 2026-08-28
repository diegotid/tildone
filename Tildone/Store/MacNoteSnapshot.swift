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
    var isEmpty: Bool { tasks.isEmpty && title == nil }
    var isComplete: Bool {
        let leaves = TaskHierarchy.leafTasks(in: tasks)
        return !leaves.isEmpty && leaves.allSatisfy(\.isCompleted)
    }
    var isDeletable: Bool { isEmpty || isComplete }
    var pendingTasks: [Task] { TaskHierarchy.leafTasks(in: tasks).filter { !$0.isCompleted } }
    var completedAt: Date? {
        guard isComplete else { return nil }
        return TaskHierarchy.leafTasks(in: tasks).compactMap(\.completedAt).max()
    }

    /// Retains the released window-autosave key for migrated notes.
    var legacyWindowKey: String { createdAt.ISO8601Format() }
}
