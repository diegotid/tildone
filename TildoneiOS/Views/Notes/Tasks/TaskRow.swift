//
//  TaskRow.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import Foundation
import SwiftUI
import TildoneDomain

struct TaskRow: View {
    let task: Task
    let subtaskProgress: TaskSubtaskProgress?
    let subtasksExpanded: Bool?
    let canIndent: Bool
    let canOutdent: Bool
    var focusedTask: FocusState<TaskID?>.Binding
    let onCommit: (String) async -> Void
    let onToggle: () async -> Void
    let onToggleSubtasks: () -> Void
    let onIndent: () async -> Void
    let onOutdent: () async -> Void
    let onMoveUp: () async -> Void
    let onMoveDown: () async -> Void
    @State private var draft = ""

    private var isVisuallyCompleted: Bool {
        task.isCompleted || subtaskProgress?.fraction == 1
    }

    private var linkedTaskText: AttributedString? {
        TaskTextLinks.displayText(for: task.text)
    }

    var body: some View {
        HStack(spacing: 6) {
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

            if let linkedTaskText, focusedTask.wrappedValue != task.id {
                Text(linkedTaskText)
                    .lineLimit(1)
                    .strikethrough(isVisuallyCompleted)
                    .foregroundStyle(isVisuallyCompleted ? .secondary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 33, alignment: .leading)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded { focusedTask.wrappedValue = task.id }
                    )
            } else {
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

            if let subtasksExpanded {
                Button(action: onToggleSubtasks) {
                    Image(systemName: subtasksExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 32, height: 33)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(subtasksExpanded ? "Collapse subtasks" : "Expand subtasks")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 33, maxHeight: 33)
        .padding(.leading, 24 * CGFloat(task.indentLevel) - 6)
        .onAppear { draft = task.text }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if canIndent {
                Button("Make subtask") { Swift.Task { await onIndent() } }
            }
            if canOutdent {
                Button("Promote task") { Swift.Task { await onOutdent() } }
            }
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

private enum TaskTextLinks {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func displayText(for text: String) -> AttributedString? {
        guard let detector else { return nil }
        let matches = detector.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
        var displayText = AttributedString()
        var cursor = text.startIndex
        var foundURL = false

        for match in matches {
            guard let range = Range(match.range, in: text),
                  let destination = match.url,
                  let scheme = destination.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  let host = destination.host,
                  !host.isEmpty else {
                continue
            }
            let displayHost = host.lowercased().hasPrefix("www.")
                ? String(host.dropFirst(4))
                : host
            displayText += AttributedString(String(text[cursor..<range.lowerBound]))
            var linkText = AttributedString(displayHost)
            linkText.link = destination
            linkText.foregroundColor = .accentColor
            displayText += linkText
            cursor = range.upperBound
            foundURL = true
        }

        guard foundURL else { return nil }
        displayText += AttributedString(String(text[cursor...]))
        return displayText
    }
}
