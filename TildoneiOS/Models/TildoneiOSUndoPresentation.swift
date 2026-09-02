//
//  TildoneiOSUndoPresentation.swift
//  Tildone
//

import SwiftUI
import TildoneDomain

@MainActor
final class TildoneiOSUndoPresentation: ObservableObject {
    @Published private(set) var action: ConsequentialActionKind?
    @Published private(set) var isControlVisible = false
    @Published private(set) var registrationRevision: UInt64 = 0
    @Published var errorMessage: String?

    private var dismissalTask: Swift.Task<Void, Never>?

    deinit { dismissalTask?.cancel() }

    func present(_ action: ConsequentialActionKind) {
        dismissalTask?.cancel()
        self.action = action
        registrationRevision &+= 1
        isControlVisible = action.showsTransientUndoControl
        guard isControlVisible else {
            dismissalTask = nil
            return
        }
        dismissalTask = Swift.Task { [weak self] in
            try? await Swift.Task.sleep(for: .seconds(6))
            guard !Swift.Task.isCancelled else { return }
            self?.isControlVisible = false
        }
    }

    func clear() {
        dismissalTask?.cancel()
        dismissalTask = nil
        action = nil
        isControlVisible = false
        registrationRevision &+= 1
    }

    func reportUndoFailure() {
        errorMessage = String(
            localized: "The change could not be undone. Your notes were not otherwise changed."
        )
        registrationRevision &+= 1
    }

    func performUndo(using operation: @escaping () async throws -> Void) {
        guard action != nil else { return }
        Swift.Task {
            do {
                try await operation()
            } catch {
                reportUndoFailure()
            }
        }
    }
}

extension ConsequentialActionKind {
    var localizedUndoTitle: String {
        switch self {
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

    var localizedUndoActionName: String {
        switch self {
        case .deleteNote: String(localized: "Delete Note")
        case .deleteTask: String(localized: "Delete Task")
        case .completeTask: String(localized: "Complete Task")
        case .uncompleteTask: String(localized: "Uncomplete Task")
        case .reorderTask: String(localized: "Reorder Task")
        case .indentTask: String(localized: "Indent Task")
        case .outdentTask: String(localized: "Outdent Task")
        case .changeNoteColor: String(localized: "Change Note Color")
        }
    }

    var showsTransientUndoControl: Bool {
        self == .deleteNote || self == .deleteTask
    }
}
