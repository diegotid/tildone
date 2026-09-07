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
    let onCommit: (RichText) async -> Void
    let onToggle: () async -> Void
    let onToggleSubtasks: () -> Void
    let onIndent: () async -> Void
    let onOutdent: () async -> Void
    let onMoveUp: () async -> Void
    let onMoveDown: () async -> Void
    @State private var draft = RichText(text: "")

    private var isVisuallyCompleted: Bool {
        task.isCompleted || subtaskProgress?.fraction == 1
    }

    private var linkedTaskText: AttributedString? {
        TaskTextLinks.displayText(for: task.richText)
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
                    .opacity(isVisuallyCompleted ? 0.6 : 1)
                    .frame(maxWidth: .infinity, minHeight: 33, alignment: .leading)
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture(count: 2)
                            .onEnded { focusedTask.wrappedValue = task.id }
                    )
            } else {
                RichTaskTextEditor(
                    richText: $draft,
                    modelRichText: task.richText,
                    taskID: task.id,
                    focusedTask: focusedTask,
                    isCompleted: isVisuallyCompleted,
                    onCommit: commit
                )
                .frame(maxWidth: .infinity, minHeight: 33, maxHeight: 33, alignment: .leading)
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
        .onAppear { draft = task.richText }
        .onChange(of: task.richText) { _, remoteText in
            if focusedTask.wrappedValue != task.id { draft = remoteText }
        }
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

    private func commit(_ finalRichText: RichText) {
        let value = finalRichText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.text.isEmpty, value != task.richText else { return }
        Swift.Task { await onCommit(value) }
    }
}

private enum TaskTextLinks {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func displayText(for richText: RichText) -> AttributedString? {
        guard let detector else { return nil }
        let text = richText.text
        let matches = detector.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
        let foundURL = matches.contains { match in
            guard let destination = match.url,
                  let scheme = destination.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  let host = destination.host,
                  !host.isEmpty else { return false }
            return true
        }
        guard foundURL else { return nil }
        return RichTaskTextEditor.displayText(from: richText, shortenLinks: true)
    }
}
