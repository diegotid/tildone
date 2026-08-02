//
//  TaskRow.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import SwiftUI
import TildoneDomain

struct TaskRow: View {
    let task: Task
    var focusedTask: FocusState<TaskID?>.Binding
    let onCommit: (String) async -> Void
    let onToggle: () async -> Void
    let onDelete: () async -> Void
    let onMoveUp: () async -> Void
    let onMoveDown: () async -> Void
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 8) {
            TaskCheckbox(isChecked: task.isCompleted) {
                Swift.Task { await onToggle() }
            }

            TextField("Task", text: $draft, axis: .horizontal)
                .focused(focusedTask, equals: task.id)
                .lineLimit(1)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .submitLabel(.done)
                .onSubmit { commit() }
                .onChange(of: focusedTask.wrappedValue) { oldValue, newValue in
                    if oldValue == task.id, newValue != task.id { commit() }
                }
                .onChange(of: task.text) { _, remoteText in
                    if focusedTask.wrappedValue != task.id { draft = remoteText }
                }
        }
        .frame(maxWidth: .infinity, minHeight: 33, maxHeight: 33)
        .onAppear { draft = task.text }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: task.isCompleted ? "Mark incomplete" : "Complete") {
            Swift.Task { await onToggle() }
        }
        .accessibilityAction(named: "Delete") { Swift.Task { await onDelete() } }
        .accessibilityAction(named: "Move Up") { Swift.Task { await onMoveUp() } }
        .accessibilityAction(named: "Move Down") { Swift.Task { await onMoveDown() } }
    }

    private func commit() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != task.text else { return }
        Swift.Task { await onCommit(value) }
    }
}
