//
//  MacUndoMenuButton.swift
//  Tildone
//

import SwiftUI
import TildoneDomain

struct MacUndoMenuButton: View {
    @ObservedObject var store: MacSharedStore
    let onFailure: (Error) -> Void

    var body: some View {
        Button(title) {
            Swift.Task {
                do { try await store.undoLatestAction() }
                catch { onFailure(error) }
            }
        }
        .disabled(store.undoAction == nil)
        .keyboardShortcut("z", modifiers: .command)
    }

    private var title: String {
        guard let action = store.undoAction else { return String(localized: "Undo") }
        return switch action {
        case .deleteNote: String(localized: "Undo Delete Note")
        case .deleteTask: String(localized: "Undo Delete Task")
        case .completeTask: String(localized: "Undo Complete Task")
        case .uncompleteTask: String(localized: "Undo Uncomplete Task")
        case .reorderTask: String(localized: "Undo Reorder Task")
        case .indentTask: String(localized: "Undo Indent Task")
        case .outdentTask: String(localized: "Undo Outdent Task")
        case .changeNoteColor: String(localized: "Undo Change Note Color")
        }
    }
}
