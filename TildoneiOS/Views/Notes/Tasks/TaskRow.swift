//
//  TaskRow.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import Foundation
import SwiftUI
import TildoneDomain
import UIKit

struct TaskRow: View {
    let task: Task
    let noteColor: NoteColor
    let subtaskProgress: TaskSubtaskProgress?
    let subtasksExpanded: Bool?
    let canIndent: Bool
    let canOutdent: Bool
    var focusedTask: FocusState<TaskID?>.Binding
    let onBeginEditing: () -> Void
    let onCommit: (RichText) async -> Void
    let onToggle: () async -> Void
    let onToggleSubtasks: () -> Void
    let onIndent: () async -> Void
    let onOutdent: () async -> Void
    let onMoveUp: () async -> Void
    let onMoveDown: () async -> Void
    @State private var draft = RichText(text: "")
    @State private var isEditingTask = false

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

            if focusedTask.wrappedValue != task.id && !isEditingTask {
                if linkedTaskText == nil {
                    Button {
                        isEditingTask = true
                        onBeginEditing()
                    } label: {
                        taskDisplayText
                    }
                    .buttonStyle(.plain)
                } else {
                    taskDisplayText
                        .simultaneousGesture(
                            TapGesture(count: 2)
                                .onEnded {
                                    isEditingTask = true
                                    onBeginEditing()
                                }
                        )
                }
            } else {
                RichTaskTextEditor(
                    richText: $draft,
                    modelRichText: task.richText,
                    taskID: task.id,
                    focusedTask: focusedTask,
                    isCompleted: isVisuallyCompleted,
                    forceFocus: isEditingTask,
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
        .onChange(of: focusedTask.wrappedValue) { _, focusedID in
            if focusedID != task.id { isEditingTask = false }
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

    private var taskDisplayText: some View {
        DisplayText(
            richText: task.richText,
            noteColor: noteColor,
            linkedText: linkedTaskText
        )
        .lineLimit(1)
        .strikethrough(isVisuallyCompleted)
        .opacity(isVisuallyCompleted ? 0.6 : 1)
        .frame(maxWidth: .infinity, minHeight: 33, maxHeight: 33, alignment: .leading)
        .contentShape(Rectangle())
    }

    private struct DisplayText: View {
        let richText: RichText
        let noteColor: NoteColor
        let linkedText: AttributedString?
        @Environment(\.colorScheme) private var colorScheme

        private var tagColor: UIColor {
            UIColor(noteColor.swiftUIColor).withAlphaComponent(0.5)
        }

        private var contrastingTextColor: UIColor {
            let surface = UIColor.secondarySystemGroupedBackground.resolvedColor(
                with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
            )
            var tagRed: CGFloat = 0
            var tagGreen: CGFloat = 0
            var tagBlue: CGFloat = 0
            var tagAlpha: CGFloat = 1
            var surfaceRed: CGFloat = 0
            var surfaceGreen: CGFloat = 0
            var surfaceBlue: CGFloat = 0
            tagColor.getRed(&tagRed, green: &tagGreen, blue: &tagBlue, alpha: &tagAlpha)
            surface.getRed(&surfaceRed, green: &surfaceGreen, blue: &surfaceBlue, alpha: nil)
            let red = tagRed * tagAlpha + surfaceRed * (1 - tagAlpha)
            let green = tagGreen * tagAlpha + surfaceGreen * (1 - tagAlpha)
            let blue = tagBlue * tagAlpha + surfaceBlue * (1 - tagAlpha)
            func linear(_ component: CGFloat) -> CGFloat {
                component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
            return luminance > 0.179 ? .black : .white
        }

        private var segments: [DisplaySegment] {
            let source = linkedText.map { NSAttributedString($0) }
                ?? NSAttributedString(RichTaskTextEditor.displayText(from: richText, detectLinks: false))
            let text = source.string as NSString
            let expression = try? NSRegularExpression(
                pattern: "\\[[^\\[\\]]+\\]|[^\\s\\[\\]]+|[\\[\\]]"
            )
            let matches = expression?.matches(
                in: source.string,
                range: NSRange(location: 0, length: source.length)
            ) ?? []
            guard !matches.isEmpty else {
                return [DisplaySegment(
                    id: 0,
                    leading: AttributedString(""),
                    text: AttributedString(source),
                    trailing: AttributedString(""),
                    isTag: false
                )]
            }

            var output: [DisplaySegment] = []
            var previousEnd = 0
            for (index, match) in matches.enumerated() {
                let token = text.substring(with: match.range)
                let inner = token.count >= 2 ? String(token.dropFirst().dropLast()) : ""
                let isTag = token.first == "["
                    && token.last == "]"
                    && inner.contains(where: { !$0.isWhitespace })
                    && (match.range.location == 0 || text.character(at: match.range.location - 1) != 91)
                    && (NSMaxRange(match.range) == source.length || text.character(at: NSMaxRange(match.range)) != 93)
                var contentRange = match.range
                if isTag {
                    contentRange = NSRange(location: match.range.location + 1, length: match.range.length - 2)
                }
                let tokenEnd = NSMaxRange(match.range)
                let trailingEnd = index + 1 < matches.count ? matches[index + 1].range.location : source.length
                let leadingRange = NSRange(location: previousEnd, length: match.range.location - previousEnd)
                let trailingRange = NSRange(location: tokenEnd, length: trailingEnd - tokenEnd)
                let prefix = source.attributedSubstring(from: leadingRange)
                let content = NSMutableAttributedString(
                    attributedString: source.attributedSubstring(from: contentRange)
                )
                if isTag, content.length > 0 {
                    let contentRange = NSRange(location: 0, length: content.length)
                    content.addAttribute(.foregroundColor, value: contrastingTextColor, range: contentRange)
                    content.removeAttribute(.backgroundColor, range: contentRange)
                }
                let suffix = source.attributedSubstring(from: trailingRange)
                output.append(DisplaySegment(
                    id: index,
                    leading: AttributedString(prefix),
                    text: (try? AttributedString(content, including: \.uiKit)) ?? AttributedString(content.string),
                    trailing: AttributedString(suffix),
                    isTag: isTag
                ))
                previousEnd = trailingEnd
            }
            return output
        }

        var body: some View {
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    Text(segment.leading)
                    if segment.isTag {
                        Text(segment.text)
                            .background {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(uiColor: tagColor))
                                    .padding(.horizontal, -2)
                            }
                    } else {
                        Text(segment.text)
                    }
                    Text(segment.trailing)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 33, maxHeight: 33, alignment: .leading)
            .clipped()
        }
    }

    private struct DisplaySegment: Identifiable {
        let id: Int
        let leading: AttributedString
        let text: AttributedString
        let trailing: AttributedString
        let isTag: Bool
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
