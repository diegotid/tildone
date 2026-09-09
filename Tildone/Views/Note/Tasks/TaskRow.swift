//
//  TaskRow.swift
//  Tildone
//

import Foundation
import SwiftUI
import TildoneDomain

struct TaskRow: View {
    let task: TildoneDomain.Task
    let dragPayload: MacTaskDragPayload
    let rowIndex: Int
    let fontSize: Double
    let isDark: Bool
    let contentColor: Color
    let cursorColor: Color
    let placeholderColor: Color
    let truncation: TaskLineTruncation
    let isFirst: Bool
    let followsDeeperTask: Bool
    let isShowingRowControls: Bool
    let hasSubtasks: Bool
    let isSubtasksCollapsed: Bool
    let subtaskProgress: TaskSubtaskProgress?
    let checkboxChecked: Bool
    let isTaskCompletionPending: Bool
    let feedbackResetToken: UUID
    @FocusState.Binding var focusedTaskID: TaskID?
    let isActive: Bool
    let placesCaretAtStartOnFocus: Bool
    let onNativeFocus: () -> Void
    let onNativeBlur: () -> Void
    let onEditLink: () -> Void
    @State private var rowHeight: CGFloat = 0
    @State private var dropPlacement: TaskRowDropPlacement?
    let onToggle: () -> Void
    let onEdit: (RichText) -> Void
    let onEnter: (Int?) -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onMoveUp: () -> Void
    let onSubmit: () -> Void
    let onInsertAbove: () -> Void
    let onToggleSubtasks: () -> Void
    let onIndent: () -> Void
    let onOutdent: () -> Void
    let onDrop: (MacTaskDragPayload, Int) -> Bool
    let onHover: (Bool) -> Void
    let onRowHover: (Bool) -> Void

    private var taskControlSize: CGFloat {
        NoteTypography.taskControlSize(for: CGFloat(fontSize))
    }

    private var taskLineHeight: CGFloat {
        NoteTypography.taskLineHeight(for: CGFloat(fontSize))
    }

    private var taskControlVerticalPadding: CGFloat {
        max(0, (taskLineHeight - taskControlSize) / 2)
    }

    // AppKit's editable NSTextField draws a few points lower than SwiftUI's
    // static text at the same font size. Keep it aligned with the checkbox
    // without changing the completed-row presentation.
    private var editableTaskTextVerticalOffset: CGFloat { -1 }

    private var inactiveTaskTextVerticalOffset: CGFloat {
        NoteTypography.inactiveTaskTextVerticalOffset(for: CGFloat(fontSize))
    }

    private var taskActionControlSize: CGFloat {
        max(12, taskLineHeight)
    }

    private var hierarchyTransitionTopSpacing: CGFloat {
        max(2, CGFloat(fontSize) * 0.3)
    }

    private var taskActionColor: Color {
        (isDark ? Color(.primaryFontWhite) : Color(.primaryFontColor)).opacity(0.7)
    }

    private var linkedTaskText: TaskTextLinkPresentation? {
        TaskTextLinks.presentation(
            for: task.richText,
            fontSize: CGFloat(fontSize),
            baseColor: NSColor(contentColor)
        )
    }

    private var showsCompletedAppearance: Bool {
        task.isCompleted || subtaskProgress?.fraction == 1
    }

    private var showsHoverControls: Bool {
        isShowingRowControls && !isActive
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Group {
                if let subtaskProgress {
                    SubtaskProgressGauge(progress: subtaskProgress, size: taskControlSize)
                } else {
                    Checkbox(checked: checkboxChecked, size: taskControlSize)
                        .disabled(task.text.isEmpty)
                        .onToggle { onToggle() }
                        .allowsHitTesting(!isTaskCompletionPending)
                }
            }
            .padding(.vertical, taskControlVerticalPadding)

            if let linkedTaskText, showsCompletedAppearance || !isActive {
                TaskTextLinksView(
                    text: linkedTaskText.attributedText,
                    isCompleted: showsCompletedAppearance,
                    truncation: truncation,
                    onEdit: showsCompletedAppearance ? nil : onEditLink,
                    onPaste: showsCompletedAppearance || !isShowingRowControls ? nil : onPaste
                )
                .frame(maxWidth: .infinity, minHeight: taskLineHeight, alignment: .leading)
                .if(truncation == .single) {
                    $0.modifier(TaskTextTruncationTooltip(
                        text: linkedTaskText.plainText,
                        fontSize: CGFloat(fontSize)
                    ))
                }
            } else if showsCompletedAppearance {
                Text(MouseSafeTaskTextField.displayAttributedString(
                    from: task.richText,
                    fontSize: CGFloat(fontSize),
                    baseColor: NSColor(contentColor)
                ))
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(0.6)
                .strikethrough(true, color: .accentColor)
                .frame(maxWidth: .infinity, minHeight: taskLineHeight, alignment: .leading)
                .if(truncation == .single) {
                    $0.modifier(TaskTextTruncationTooltip(
                        text: task.text,
                        fontSize: CGFloat(fontSize)
                    ))
                }
            } else {
                ZStack(alignment: .leading) {
                    if task.text.isEmpty {
                        Text("New task.default")
                            .font(.system(size: CGFloat(fontSize)))
                            .foregroundStyle(placeholderColor.opacity(0.35))
                            .allowsHitTesting(false)
                    }
                    if truncation == .single {
                        MouseSafeTaskTextField(
                            richText: Binding(get: { task.richText }, set: onEdit),
                            taskID: task.id,
                            isFocused: isActive,
                            placesCaretAtStartOnFocus: placesCaretAtStartOnFocus,
                            fontSize: CGFloat(fontSize),
                            textColor: contentColor,
                            cursorColor: cursorColor,
                            truncation: truncation,
                            onFocus: onNativeFocus,
                            onBlur: onNativeBlur,
                            onEnter: { onEnter($0) },
                            onMoveUp: onMoveUp,
                            onMoveDown: onSubmit
                        )
                        .frame(maxWidth: .infinity, minHeight: taskLineHeight, maxHeight: taskLineHeight, alignment: .leading)
                        .offset(y: isActive
                            ? editableTaskTextVerticalOffset
                            : inactiveTaskTextVerticalOffset)
                        .onReceive(NotificationCenter.default.publisher(for: .copy)) { _ in
                            if focusedTaskID == task.id { onCopy() }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .paste)) { _ in
                            if focusedTaskID == task.id { onPaste() }
                        }
                    } else {
                        MouseSafeTaskTextField(
                            richText: Binding(get: { task.richText }, set: onEdit),
                            taskID: task.id,
                            isFocused: isActive,
                            placesCaretAtStartOnFocus: placesCaretAtStartOnFocus,
                            fontSize: CGFloat(fontSize),
                            textColor: contentColor,
                            cursorColor: cursorColor,
                            truncation: truncation,
                            onFocus: onNativeFocus,
                            onBlur: onNativeBlur,
                            onEnter: { onEnter($0) },
                            onMoveUp: onMoveUp,
                            onMoveDown: onSubmit
                        )
                        .padding(.trailing, isShowingRowControls && !isActive
                            ? (hasSubtasks ? 86 : 66) : 0)
                        .offset(y: isActive
                            ? editableTaskTextVerticalOffset
                            : inactiveTaskTextVerticalOffset)
                        .onReceive(NotificationCenter.default.publisher(for: .copy)) { _ in
                            if focusedTaskID == task.id { onCopy() }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .paste)) { _ in
                            if focusedTaskID == task.id { onPaste() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: taskLineHeight, alignment: .leading)
            }

            HStack(spacing: 2) {
                if hasSubtasks {
                    Button(action: onToggleSubtasks) {
                        Image(systemName: isSubtasksCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: taskActionControlSize * 0.65, weight: .semibold))
                            .frame(width: taskActionControlSize, height: taskActionControlSize)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(taskActionColor)
                    .contentShape(Rectangle())
                    .help(isSubtasksCollapsed ? "Expand subtasks" : "Collapse subtasks")
                    .accessibilityLabel(isSubtasksCollapsed ? "Expand subtasks" : "Collapse subtasks")
                }

                Menu {
                    Button(action: onIndent) {
                        Label {
                            Text("Make subtask")
                        } icon: {
                            Image(systemName: "arrow.turn.down.right")
                                .foregroundStyle(.primary)
                        }
                    }
                    Button(action: onOutdent) {
                        Label {
                            Text("Promote task")
                        } icon: {
                            Image(systemName: "arrow.turn.left.up")
                                .foregroundStyle(.primary)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: taskActionControlSize * 0.6, weight: .semibold))
                        .frame(width: taskActionControlSize, height: taskActionControlSize)
                        .scaleEffect(0.75, anchor: .center)
                        .hidden()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .contentShape(Rectangle())
                .overlay {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: taskActionControlSize * 0.65, weight: .semibold))
                        .foregroundStyle(taskActionColor)
                        .frame(width: taskActionControlSize, height: taskActionControlSize)
                        .allowsHitTesting(false)
                }
                .padding(.leading, 5)
                .padding(.trailing, 4)
                .opacity(showsHoverControls ? 1 : 0)
                .allowsHitTesting(showsHoverControls)
                .help("Task hierarchy")
                .accessibilityLabel("Task hierarchy")

                Button(action: onInsertAbove) {
                    Image(systemName: "plus")
                        .font(.system(size: taskActionControlSize * 0.65, weight: .semibold))
                        .frame(width: taskActionControlSize, height: taskActionControlSize)
                }
                .buttonStyle(.plain)
                .foregroundStyle(taskActionColor)
                .contentShape(Rectangle())
                .opacity(showsHoverControls ? 1 : 0)
                .allowsHitTesting(showsHoverControls)
                .help("Insert task above")
                .accessibilityLabel("Insert task above")

                TaskReorderHandle(
                    payload: dragPayload,
                    taskText: task.text,
                    isCompleted: task.isCompleted,
                    fontSize: fontSize,
                    isDark: isDark,
                    size: taskActionControlSize * 0.9
                )
                .padding(.leading, 2)
            }
            .opacity(showsHoverControls ? 1 : 0)
            .allowsHitTesting(showsHoverControls)
            .padding(.trailing, 8)
            .frame(
                width: truncation == .single && showsHoverControls ? (hasSubtasks ? 86 : 66) : 0,
                height: showsHoverControls ? taskActionControlSize : 0,
                alignment: .trailing
            )
            .offset(y: truncation == .multiple ? 1 : 0)
            .if(truncation == .single) { $0.clipped() }
        }
        .padding(.leading, 2 + CGFloat(task.indentLevel) * (Layout.checkboxSize + 8))
        .padding(.top, followsDeeperTask ? hierarchyTransitionTopSpacing : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover(perform: onRowHover)
        .if(isFirst) { $0.onHover { onHover($0) } }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rowHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, height in rowHeight = height }
            }
        }
        .padding(.top, dropPlacement == .before ? TaskReorderFeedback.insertionSpacing : 0)
        .padding(.bottom, dropPlacement == .after ? TaskReorderFeedback.insertionSpacing : 0)
        .background(alignment: dropPlacement == .before ? .top : .bottom) {
            TaskReorderInsertionLine()
                .opacity(dropPlacement == nil ? 0 : 1)
                .offset(
                    y: dropPlacement == .before
                        ? TaskReorderFeedback.insertionSpacing / 2
                        : -TaskReorderFeedback.insertionSpacing / 2
                )
        }
        .animation(TaskReorderFeedback.animation, value: dropPlacement)
        .onChange(of: feedbackResetToken) { _, _ in
            dropPlacement = nil
        }
        .onDrop(
            of: [.json],
            delegate: TaskRowDropDelegate(
                rowIndex: rowIndex,
                rowHeight: rowHeight,
                placement: $dropPlacement,
                onDrop: onDrop
            )
        )
    }

}

private enum TaskTextLinks {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func presentation(
        for richText: RichText,
        fontSize: CGFloat,
        baseColor: NSColor
    ) -> TaskTextLinkPresentation? {
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
        return TaskTextLinkPresentation(
            attributedText: MouseSafeTaskTextField.displayAttributedString(
                from: richText,
                fontSize: fontSize,
                baseColor: baseColor,
                shortenLinks: true
            ),
            plainText: shortenedLinkText(text, matches: matches)
        )
    }

    private static func shortenedLinkText(
        _ text: String,
        matches: [NSTextCheckingResult]
    ) -> String {
        let result = NSMutableString(string: text)
        for match in matches.reversed() {
            guard let destination = match.url,
                  let scheme = destination.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  let host = destination.host,
                  !host.isEmpty else { continue }
            let displayHost = host.lowercased().hasPrefix("www.")
                ? String(host.dropFirst(4))
                : host
            result.replaceCharacters(in: match.range, with: displayHost)
        }
        return result as String
    }
}

private struct TaskTextLinkPresentation {
    let attributedText: AttributedString
    let plainText: String
}

private struct TaskTextLinksView: View {
    let text: AttributedString
    let isCompleted: Bool
    let truncation: TaskLineTruncation
    let onEdit: (() -> Void)?
    let onPaste: (() -> Void)?

    var body: some View {
        // Keep font and foreground styling in the attributed value; applying
        // them here would flatten the task's rich spans when it leaves edit mode.
        Text(text)
            .lineLimit(truncation == .single ? 1 : nil)
            .truncationMode(.tail)
            .opacity(isCompleted ? 0.6 : 1)
            .strikethrough(isCompleted, color: .accentColor)
            .contentShape(Rectangle())
        .if(onEdit != nil) {
            $0.highPriorityGesture(
                TapGesture(count: 2)
                    .onEnded { onEdit?() }
            )
        }
        .if(onPaste != nil) {
            $0.onReceive(NotificationCenter.default.publisher(for: .paste)) { _ in
                onPaste?()
            }
        }
    }
}

private struct TaskTextTruncationTooltip: ViewModifier {
    let text: String
    let fontSize: CGFloat
    @State private var availableWidth: CGFloat = 0

    private var isTruncated: Bool {
        let font = NSFont.systemFont(ofSize: fontSize)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        return textWidth > availableWidth
    }

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .allowsHitTesting(false)
                        .onAppear { availableWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, width in
                            availableWidth = width
                        }
                }
            }
            .if(isTruncated) { $0.help(text) }
    }
}
