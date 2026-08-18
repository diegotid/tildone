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
    var isComplete: Bool { !tasks.isEmpty && tasks.allSatisfy(\.isCompleted) }
    var isDeletable: Bool { isEmpty || isComplete }
    var pendingTasks: [Task] { tasks.filter { !$0.isCompleted } }
    var completedAt: Date? {
        guard isComplete else { return nil }
        return tasks.compactMap(\.completedAt).max()
    }

    /// Retains the released window-autosave key for migrated notes.
    var legacyWindowKey: String { createdAt.ISO8601Format() }
}
