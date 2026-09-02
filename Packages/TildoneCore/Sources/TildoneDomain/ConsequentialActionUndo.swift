//
//  ConsequentialActionUndo.swift
//  Tildone
//

import Foundation

/// The user-visible local action retained by the one-level undo history.
public enum ConsequentialActionKind: Hashable, Sendable {
    case deleteNote
    case deleteTask
    case completeTask
    case uncompleteTask
    case reorderTask
    case indentTask
    case outdentTask
    case changeNoteColor
}

/// Stable identities let presentation adapters discard undo only when a
/// remotely applied change replaced one of the records involved in the action.
public enum DomainRecordID: Hashable, Sendable {
    case note(NoteID)
    case task(TaskID)
}

public enum ConsequentialActionUndoError: Error, Equatable, Sendable {
    case unavailable
}
