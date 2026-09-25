//
//  TaskRow.swift
//  Tildone
//

import AppKit
import Foundation
import SwiftUI
import TildoneDomain

struct TaskRow: View {
    let task: TildoneDomain.Task
    let dragPayload: MacTaskDragPayload
    let rowIndex: Int
    let fontSize: Double
    let isDark: Bool
    let noteBackgroundColor: Color
    let noteBackgroundOpacity: Double
    let contentColor: Color
    let cursorColor: Color
    let searchQuery: String
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
    @FocusState.Binding var focusedTaskID: TaskID?
    let isActive: Bool
    let placesCaretAtStartOnFocus: Bool
    let onNativeFocus: () -> Void
    let onNativeBlur: () -> Void
    let onEditLink: () -> Void
    @State private var rowHeight: CGFloat = 0
    @State private var isDropTargeted = false
    let onToggle: () -> Void
    let onEdit: (RichText) -> Void
    let onEnter: (Int?) -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onPastedList: (MouseSafeTaskTextField.PastedList) -> Bool
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

    private var inactiveTaskTextVerticalOffset: CGFloat {
        NoteTypography.inactiveTaskTextVerticalOffset(for: CGFloat(fontSize))
    }

    private var focusedTaskTextVerticalAdjustment: CGFloat {
        NoteTypography.focusedTaskTextVerticalAdjustment(for: CGFloat(fontSize))
    }

    private var taskTextVerticalOffset: CGFloat {
        inactiveTaskTextVerticalOffset + (isActive ? focusedTaskTextVerticalAdjustment : 0)
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
                    SubtaskProgressGauge(
                        progress: subtaskProgress,
                        size: taskControlSize,
                        noteBackgroundColor: noteBackgroundColor
                    )
                } else {
                    Checkbox(checked: checkboxChecked, size: taskControlSize)
                        .disabled(task.text.isEmpty)
                        .onToggle { onToggle() }
                        .allowsHitTesting(!isTaskCompletionPending)
                }
            }
            .padding(.vertical, taskControlVerticalPadding)

            if showsCompletedAppearance && !isActive && !task.text.isEmpty {
                WordTagsView(
                    richText: task.richText,
                    fontSize: CGFloat(fontSize),
                    foregroundColor: contentColor,
                    tagColor: tagBackgroundColor(
                        from: noteBackgroundColor,
                        noteOpacity: noteBackgroundOpacity
                    ),
                    truncation: truncation,
                    isCompleted: showsCompletedAppearance,
                    onSelect: showsCompletedAppearance ? nil : onEditLink
                )
                .frame(maxWidth: .infinity, minHeight: taskLineHeight, alignment: .leading)
                .transaction { $0.animation = nil }
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
                            searchQuery: searchQuery,
                            truncation: truncation,
                            onFocus: onNativeFocus,
                            onBlur: onNativeBlur,
                            onEnter: { onEnter($0) },
                            onMoveUp: onMoveUp,
                            onMoveDown: onSubmit,
                            onPastedList: onPastedList
                        )
                        .frame(maxWidth: .infinity, minHeight: taskLineHeight, maxHeight: taskLineHeight, alignment: .leading)
                        .offset(x: 0, y: taskTextVerticalOffset)
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
                            searchQuery: searchQuery,
                            truncation: truncation,
                            onFocus: onNativeFocus,
                            onBlur: onNativeBlur,
                            onEnter: { onEnter($0) },
                            onMoveUp: onMoveUp,
                            onMoveDown: onSubmit,
                            onPastedList: onPastedList
                        )
                        .padding(.trailing, isShowingRowControls && !isActive
                            ? (hasSubtasks ? 86 : 66) : 0)
                        .offset(x: 0, y: taskTextVerticalOffset)
                        .onReceive(NotificationCenter.default.publisher(for: .copy)) { _ in
                            if focusedTaskID == task.id { onCopy() }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .paste)) { _ in
                            if focusedTaskID == task.id { onPaste() }
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: taskLineHeight, alignment: .leading)
                .transaction { $0.animation = nil }
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
                width: showsHoverControls ? (hasSubtasks ? 86 : 66) : 0,
                height: showsHoverControls ? taskActionControlSize : 0,
                alignment: .trailing
            )
            .offset(y: truncation == .multiple ? 1 : 0)
            .clipped()
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
        .background(Color.accentColor.opacity(isDropTargeted ? 0.1 : 0))
        .dropDestination(for: MacTaskDragPayload.self) { payloads, location in
            guard payloads.count == 1, let payload = payloads.first else { return false }
            let destination = location.y < rowHeight / 2 ? rowIndex : rowIndex + 1
            return onDrop(payload, destination)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
    }

    private func tagBackgroundColor(from color: Color, noteOpacity: Double) -> Color {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        let saturation = min(nsColor.saturationComponent * 2, 1)
        let opacity = min(max(noteOpacity * 2, 0.35), 1)
        return Color(nsColor: NSColor(
            calibratedHue: nsColor.hueComponent,
            saturation: saturation,
            brightness: nsColor.brightnessComponent,
            alpha: opacity
        ))
    }

    static func inactiveDisplayText(
        from richText: RichText,
        fontSize: CGFloat,
        foregroundColor: NSColor
    ) -> NSAttributedString {
        NSAttributedString(MouseSafeTaskTextField.displayAttributedString(
            from: richText,
            fontSize: fontSize,
            baseColor: foregroundColor,
            shortenLinks: true
        ))
    }

    private struct WordTagsView: View {
        let richText: RichText
        let fontSize: CGFloat
        let foregroundColor: Color
        let tagColor: Color
        let truncation: TaskLineTruncation
        let isCompleted: Bool
        let onSelect: (() -> Void)?
        @State private var availableWidth: CGFloat = 0

        private struct Part: Identifiable {
            let id: Int
            let text: AttributedString
            let trailingWhitespace: String
            let isTagged: Bool
            let isEllipsis: Bool
        }

        private var tagTextColor: Color {
            let color = NSColor(tagColor).usingColorSpace(.deviceRGB) ?? NSColor(tagColor)
            func linear(_ component: CGFloat) -> CGFloat {
                component <= 0.04045
                    ? component / 12.92
                    : pow((component + 0.055) / 1.055, 2.4)
            }
            let luminance = 0.2126 * linear(color.redComponent)
                + 0.7152 * linear(color.greenComponent)
                + 0.0722 * linear(color.blueComponent)
            let blackContrast = (luminance + 0.05) / 0.05
            let whiteContrast = 1.05 / (luminance + 0.05)
            return blackContrast >= whiteContrast ? .black : .white
        }

        private var parts: [Part] {
            let attributed = TaskRow.inactiveDisplayText(
                from: richText,
                fontSize: fontSize,
                foregroundColor: NSColor(foregroundColor)
            )
            guard let expression = try? NSRegularExpression(pattern: "\\[[^\\[\\]]+\\]|[^\\s\\[\\]]+|[\\[\\]]") else {
                return []
            }
            let matches = expression.matches(
                in: attributed.string,
                range: NSRange(location: 0, length: attributed.length)
            )
            let source = attributed.string as NSString
            return matches.enumerated().compactMap { index, match in
                let token = attributed.attributedSubstring(from: match.range)
                let innerText = token.string.count >= 2
                    ? String(token.string.dropFirst().dropLast())
                    : ""
                let isTagged = token.string.count >= 3
                    && token.string.first == "["
                    && token.string.last == "]"
                    && innerText.contains(where: { !$0.isWhitespace })
                    && (match.range.location == 0 || source.character(at: match.range.location - 1) != 91)
                    && (NSMaxRange(match.range) == source.length || source.character(at: NSMaxRange(match.range)) != 93)
                let displayRange = isTagged
                    ? NSRange(location: 1, length: match.range.length - 2)
                    : NSRange(location: 0, length: match.range.length)
                let displayText = NSMutableAttributedString(
                    attributedString: token.attributedSubstring(from: displayRange)
                )
                if isTagged {
                    let range = NSRange(location: 0, length: displayText.length)
                    displayText.addAttribute(.foregroundColor, value: NSColor(tagTextColor), range: range)
                    displayText.removeAttribute(.backgroundColor, range: range)
                }
                guard let styledText = try? AttributedString(displayText, including: \.appKit) else {
                    return nil
                }
                let whitespaceStart = NSMaxRange(match.range)
                let whitespaceEnd = index + 1 < matches.count
                    ? matches[index + 1].range.location
                    : attributed.length
                let whitespace = source.substring(with: NSRange(
                    location: whitespaceStart,
                    length: max(0, whitespaceEnd - whitespaceStart)
                ))
                return Part(
                    id: match.range.location,
                    text: styledText,
                    trailingWhitespace: whitespace,
                    isTagged: isTagged,
                    isEllipsis: false
                )
            }
        }

        private var ellipsisWidth: CGFloat {
            ("…" as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: fontSize)
            ]).width
        }

        private var ellipsisPart: Part {
            let attributed = NSAttributedString(
                string: "…",
                attributes: [
                    .font: NSFont.systemFont(ofSize: fontSize),
                    .foregroundColor: NSColor(foregroundColor)
                ]
            )
            let text = (try? AttributedString(attributed, including: \.appKit)) ?? AttributedString("…")
            return Part(id: Int.max, text: text, trailingWhitespace: "", isTagged: false, isEllipsis: true)
        }

        private func truncatedParts(_ parts: [Part], to width: CGFloat) -> [Part] {
            let contentWidth = max(0, width - ellipsisWidth)
            var usedWidth: CGFloat = 0
            var visible: [Part] = []

            for part in parts {
                let textWidth = NSAttributedString(part.text).size().width
                let whitespaceWidth = (part.trailingWhitespace as NSString).size(withAttributes: [
                    .font: NSFont.systemFont(ofSize: fontSize)
                ]).width
                let partWidth = textWidth + whitespaceWidth + (part.isTagged ? 4 : 0)
                let remainingWidth = contentWidth - usedWidth

                if partWidth <= remainingWidth {
                    visible.append(part)
                    usedWidth += partWidth
                    continue
                }

                let textLimit = max(0, remainingWidth - (part.isTagged ? 4 : 0))
                let prefix = prefix(of: part.text, fitting: textLimit)
                if !prefix.characters.isEmpty {
                    visible.append(Part(
                        id: part.id,
                        text: prefix,
                        trailingWhitespace: "",
                        isTagged: part.isTagged,
                        isEllipsis: false
                    ))
                }
                break
            }

            if let last = visible.indices.last {
                let part = visible[last]
                visible[last] = Part(
                    id: part.id,
                    text: part.text,
                    trailingWhitespace: "",
                    isTagged: part.isTagged,
                    isEllipsis: false
                )
            }
            visible.append(ellipsisPart)
            return visible
        }

        private func prefix(of text: AttributedString, fitting width: CGFloat) -> AttributedString {
            let attributed = NSAttributedString(text)
            let source = attributed.string as NSString
            guard source.length > 0, width > 0 else { return AttributedString("") }

            var ranges: [NSRange] = []
            var location = 0
            while location < source.length {
                let range = source.rangeOfComposedCharacterSequence(at: location)
                ranges.append(range)
                location = NSMaxRange(range)
            }

            var lower = 0
            var upper = ranges.count
            while lower < upper {
                let middle = (lower + upper + 1) / 2
                let end = NSMaxRange(ranges[middle - 1])
                let candidate = attributed.attributedSubstring(from: NSRange(location: 0, length: end))
                if candidate.size().width <= width {
                    lower = middle
                } else {
                    upper = middle - 1
                }
            }

            guard lower > 0 else { return AttributedString("") }
            let end = NSMaxRange(ranges[lower - 1])
            return (try? AttributedString(
                attributed.attributedSubstring(from: NSRange(location: 0, length: end)),
                including: \.appKit
            )) ?? AttributedString("")
        }

        var body: some View {
            let displayParts = parts
            let textWidth = displayParts.reduce(CGFloat.zero) { width, part in
                width + NSAttributedString(part.text).size().width
                    + (part.trailingWhitespace as NSString).size(withAttributes: [
                        .font: NSFont.systemFont(ofSize: fontSize)
                    ]).width
                    + (part.isTagged ? 4 : 0)
            }
            let isTruncated = truncation == .single
                && availableWidth > 0
                && textWidth > availableWidth + 0.5

            Group {
                if isTruncated {
                    words(truncatedParts(displayParts, to: availableWidth))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    words(displayParts)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { availableWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, width in
                            availableWidth = width
                        }
                }
            }
            .opacity(isCompleted ? 0.6 : 1)
            .strikethrough(isCompleted, color: .accentColor)
            .contentShape(Rectangle())
            .if(onSelect != nil) { view in
                view.highPriorityGesture(
                    TapGesture(count: 2).onEnded { onSelect?() }
                )
            }
        }

        private func words(_ parts: [Part]) -> some View {
            AnyLayout(WordFlowLayout(
                horizontalSpacing: 0,
                verticalSpacing: 4,
                singleLine: truncation == .single
            )) {
                ForEach(parts) { part in
                    if part.isTagged {
                        HStack(spacing: 0) {
                            Text(part.text)
                                .font(.system(size: fontSize))
                                .foregroundStyle(tagTextColor)
                                .background {
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(tagColor)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .fill(LinearGradient(
                                                    colors: [.clear, .black.opacity(0.14)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                ))
                                        }
                                        .shadow(color: .black.opacity(0.14), radius: 1.25, x: 0, y: -0.5)
                                        .padding(.horizontal, -2)
                                }
                            Text(part.trailingWhitespace)
                                .font(.system(size: fontSize))
                                .foregroundStyle(foregroundColor)
                        }
                    } else {
                        if part.isEllipsis {
                            Text(part.text)
                                .font(.system(size: fontSize))
                                .foregroundStyle(foregroundColor)
                                .accessibilityHidden(true)
                        } else {
                            Text(part.text + AttributedString(part.trailingWhitespace))
                                .font(.system(size: fontSize))
                        }
                    }
                }
            }
        }
    }

    private struct WordFlowLayout: SwiftUI.Layout {
        let horizontalSpacing: CGFloat
        let verticalSpacing: CGFloat
        let singleLine: Bool

        func sizeThatFits(proposal: ProposedViewSize, subviews: SwiftUI.Layout.Subviews, cache: inout ()) -> CGSize {
            let availableWidth = proposal.width ?? .greatestFiniteMagnitude
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0
            var contentWidth: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if !singleLine, x > 0, x + size.width > availableWidth {
                    y += rowHeight + verticalSpacing
                    x = 0
                    rowHeight = 0
                }
                if x > 0 { x += horizontalSpacing }
                x += size.width
                rowHeight = max(rowHeight, size.height)
                contentWidth = max(contentWidth, x)
            }

            return CGSize(width: min(contentWidth, availableWidth), height: y + rowHeight)
        }

        func placeSubviews(
            in bounds: CGRect,
            proposal: ProposedViewSize,
            subviews: SwiftUI.Layout.Subviews,
            cache: inout ()
        ) {
            var x = bounds.minX
            var y = bounds.minY
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if !singleLine, x > bounds.minX, x + size.width > bounds.maxX {
                    y += rowHeight + verticalSpacing
                    x = bounds.minX
                    rowHeight = 0
                }
                if x > bounds.minX { x += horizontalSpacing }
                subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width
                rowHeight = max(rowHeight, size.height)
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
