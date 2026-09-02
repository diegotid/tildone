//
//  ConsequentialActionUndoController.swift
//  Tildone
//

import Foundation
import TildoneDomain

/// One-level, process-local undo for consequential content mutations. The
/// controller retains domain values only and performs inverses through normal
/// repository operations so versions, tombstones, and outbound work advance.
@MainActor
public final class ConsequentialActionUndoController {
    public private(set) var availableAction: ConsequentialActionKind?

    private let repository: TildoneRepository
    private var item: Item?

    public init(repository: TildoneRepository) {
        self.repository = repository
    }

    public func recordNoteDeletion(note: Note, tasks: [Task]) {
        replace(with: .deleteNote(noteID: note.id, tasks: tasks))
    }

    public func recordTaskDeletion(noteID: NoteID, tasks: [Task]) {
        guard !tasks.isEmpty else { return }
        replace(with: .deleteTask(noteID: noteID, tasks: tasks))
    }

    public func recordTaskCompletion(before: [Task], after: [Task], taskID: TaskID) {
        guard let original = before.first(where: { $0.id == taskID }),
              let current = after.first(where: { $0.id == taskID }),
              original.completion != current.completion else { return }
        let currentByID = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        var originalOrder: [TaskID: OrderToken] = [:]
        for task in before {
            guard let current = currentByID[task.id],
                  current.orderToken != task.orderToken else { continue }
            originalOrder[task.id] = task.orderToken
        }
        replace(with: .taskCompletion(
            noteID: original.noteID,
            taskID: taskID,
            completion: original.completion,
            orderTokens: originalOrder,
            performedCompletion: current.isCompleted
        ))
    }

    public func recordTaskReorder(before: [Task], after: [Task]) {
        let currentByID = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        var originalOrder: [TaskID: OrderToken] = [:]
        for task in before {
            guard let current = currentByID[task.id],
                  current.orderToken != task.orderToken else { continue }
            originalOrder[task.id] = task.orderToken
        }
        guard let noteID = before.first?.noteID, !originalOrder.isEmpty else { return }
        replace(with: .taskReorder(noteID: noteID, orderTokens: originalOrder))
    }

    @discardableResult
    public func recordTaskIndentation(
        before: [Task],
        after: [Task],
        performedOutdent: Bool
    ) -> Bool {
        let currentByID = Dictionary(uniqueKeysWithValues: after.map { ($0.id, $0) })
        let changedIndentation = before.contains { task in
            currentByID[task.id].map { $0.indentLevel != task.indentLevel } ?? false
        }
        guard let noteID = before.first?.noteID, changedIndentation else { return false }

        var updates: [TaskStructureUpdate] = []
        for task in before {
            guard let current = currentByID[task.id] else { continue }
            let orderToken = current.orderToken != task.orderToken ? task.orderToken : nil
            let indentLevel = current.indentLevel != task.indentLevel ? task.indentLevel : nil
            let completion = current.completion != task.completion ? task.completion : nil
            guard orderToken != nil || indentLevel != nil || completion != nil else { continue }
            updates.append(TaskStructureUpdate(
                id: task.id,
                orderToken: orderToken,
                indentLevel: indentLevel,
                completion: completion
            ))
        }
        replace(with: .taskIndentation(
            noteID: noteID,
            updates: updates,
            performedOutdent: performedOutdent
        ))
        return true
    }

    public func recordNoteColor(noteID: NoteID, previousColor: NoteColor, newColor: NoteColor) {
        guard previousColor != newColor else { return }
        replace(with: .noteColor(noteID: noteID, color: previousColor))
    }

    @discardableResult
    public func undo() async throws -> ConsequentialActionKind {
        guard let item else { throw ConsequentialActionUndoError.unavailable }
        switch item {
        case let .deleteNote(noteID, tasks):
            _ = try await repository.restoreNote(id: noteID)
            for task in tasks.sorted(by: Task.orderedBefore) {
                _ = try await repository.restoreTask(id: task.id)
            }
        case let .deleteTask(_, tasks):
            for task in tasks.sorted(by: Task.orderedBefore) {
                _ = try await repository.restoreTask(id: task.id)
            }
        case let .taskCompletion(noteID, taskID, completion, orderTokens, _):
            var updates = orderTokens.map {
                TaskStructureUpdate(id: $0.key, orderToken: $0.value)
            }
            if let index = updates.firstIndex(where: { $0.id == taskID }) {
                updates[index] = TaskStructureUpdate(
                    id: taskID,
                    orderToken: updates[index].orderToken,
                    completion: completion
                )
            } else {
                updates.append(TaskStructureUpdate(id: taskID, completion: completion))
            }
            _ = try await repository.applyTaskStructureUpdates(in: noteID, updates: updates)
        case let .taskReorder(noteID, orderTokens):
            _ = try await repository.applyTaskStructureUpdates(
                in: noteID,
                updates: orderTokens.map {
                    TaskStructureUpdate(id: $0.key, orderToken: $0.value)
                }
            )
        case let .taskIndentation(noteID, updates, _):
            _ = try await repository.applyTaskStructureUpdates(in: noteID, updates: updates)
        case let .noteColor(noteID, color):
            _ = try await repository.setNoteColor(id: noteID, color: color)
        }
        let action = item.kind
        discard()
        return action
    }

    public func discard() {
        item = nil
        availableAction = nil
    }

    public func discardIfAffected(by records: Set<DomainRecordID>) {
        guard let item, !item.affectedRecords.isDisjoint(with: records) else { return }
        discard()
    }
}

private extension ConsequentialActionUndoController {
    enum Item {
        case deleteNote(noteID: NoteID, tasks: [Task])
        case deleteTask(noteID: NoteID, tasks: [Task])
        case taskCompletion(
            noteID: NoteID,
            taskID: TaskID,
            completion: CompletionState,
            orderTokens: [TaskID: OrderToken],
            performedCompletion: Bool
        )
        case taskReorder(noteID: NoteID, orderTokens: [TaskID: OrderToken])
        case taskIndentation(
            noteID: NoteID,
            updates: [TaskStructureUpdate],
            performedOutdent: Bool
        )
        case noteColor(noteID: NoteID, color: NoteColor)

        var kind: ConsequentialActionKind {
            switch self {
            case .deleteNote: .deleteNote
            case .deleteTask: .deleteTask
            case let .taskCompletion(_, _, _, _, performedCompletion):
                performedCompletion ? .completeTask : .uncompleteTask
            case .taskReorder: .reorderTask
            case let .taskIndentation(_, _, performedOutdent):
                performedOutdent ? .outdentTask : .indentTask
            case .noteColor: .changeNoteColor
            }
        }

        var affectedRecords: Set<DomainRecordID> {
            switch self {
            case let .deleteNote(noteID, tasks):
                Set([.note(noteID)]) + Set(tasks.map { .task($0.id) })
            case let .deleteTask(noteID, tasks):
                Set([.note(noteID)]) + Set(tasks.map { .task($0.id) })
            case let .taskCompletion(noteID, taskID, _, orderTokens, _):
                Set([.note(noteID), .task(taskID)]) + Set(orderTokens.keys.map { .task($0) })
            case let .taskReorder(noteID, orderTokens):
                Set([.note(noteID)]) + Set(orderTokens.keys.map { .task($0) })
            case let .taskIndentation(noteID, updates, _):
                Set([.note(noteID)]) + Set(updates.map { .task($0.id) })
            case let .noteColor(noteID, _):
                Set([.note(noteID)])
            }
        }
    }

    func replace(with item: Item) {
        self.item = item
        availableAction = item.kind
    }
}

private extension Set where Element == DomainRecordID {
    static func + (lhs: Self, rhs: Self) -> Self {
        lhs.union(rhs)
    }
}
