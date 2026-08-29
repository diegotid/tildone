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
    let subtaskProgress: TaskSubtaskProgress?
    let canIndent: Bool
    let canOutdent: Bool
    var focusedTask: FocusState<TaskID?>.Binding
    let onCommit: (String) async -> Void
    let onToggle: () async -> Void
    let onIndent: () async -> Void
    let onOutdent: () async -> Void
    let onDelete: () async -> Void
    let onMoveUp: () async -> Void
    let onMoveDown: () async -> Void
    @State private var draft = ""

    private var isVisuallyCompleted: Bool {
        task.isCompleted || subtaskProgress?.fraction == 1
    }

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let subtaskProgress {
                    TaskSubtaskProgressGauge(progress: subtaskProgress)
                } else {
                    TaskCheckbox(isChecked: task.isCompleted) {
                        Swift.Task { await onToggle() }
                    }
                }
            }
            .frame(width: 32, height: 33)

            TextField("Task", text: $draft, axis: .horizontal)
                .focused(focusedTask, equals: task.id)
                .lineLimit(1)
                .strikethrough(isVisuallyCompleted)
                .foregroundStyle(isVisuallyCompleted ? .secondary : .primary)
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
        .padding(.leading, CGFloat(task.indentLevel) * 24)
        .onAppear { draft = task.text }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if canIndent {
                Button("Indent task") { Swift.Task { await onIndent() } }
            }
            if canOutdent {
                Button("Outdent task") { Swift.Task { await onOutdent() } }
            }
            Button("Delete") { Swift.Task { await onDelete() } }
            Button("Move Up") { Swift.Task { await onMoveUp() } }
            Button("Move Down") { Swift.Task { await onMoveDown() } }
        }
    }

    private func commit() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != task.text else { return }
        Swift.Task { await onCommit(value) }
    }
}
