//
//  TaskRow.swift
//  Tildone
//

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
    let feedbackResetToken: UUID
    @FocusState.Binding var focusedTaskID: TaskID?
    let isActive: Bool
    let placesCaretAtStartOnFocus: Bool
    let onNativeFocus: () -> Void
    @State private var rowHeight: CGFloat = 0
    @State private var dropPlacement: TaskRowDropPlacement?
    let onToggle: () -> Void
    let onEdit: (String) -> Void
    let onEnter: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onMoveUp: () -> Void
    let onSubmit: () -> Void
    let onDrop: (MacTaskDragPayload, Int) -> Bool
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Checkbox(checked: task.isCompleted)
                .disabled(task.text.isEmpty)
                .onToggle { onToggle() }
                .padding(.vertical, 2.4)

            if task.isCompleted {
                Text(task.text)
                    .font(.system(size: CGFloat(fontSize)))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(
                        contentColor.opacity(0.6)
                    )
                    .overlay {
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .offset(y: 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            text: Binding(get: { task.text }, set: onEdit),
                            taskID: task.id,
                            isFocused: isActive,
                            placesCaretAtStartOnFocus: placesCaretAtStartOnFocus,
                            fontSize: CGFloat(fontSize),
                            textColor: contentColor,
                            cursorColor: cursorColor,
                            onFocus: onNativeFocus,
                            onEnter: onEnter,
                            onMoveUp: onMoveUp,
                            onMoveDown: onSubmit
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onReceive(NotificationCenter.default.publisher(for: .copy)) { _ in
                            if focusedTaskID == task.id { onCopy() }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .paste)) { _ in
                            if focusedTaskID == task.id { onPaste() }
                        }
                    } else {
                        TextField("", text: Binding(get: { task.text }, set: onEdit), axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: CGFloat(fontSize)))
                            .foregroundColor(contentColor)
                            .tint(cursorColor)
                            .background(Color.clear)
                            .focused($focusedTaskID, equals: task.id)
                            .onKeyPress(keys: [.return]) { _ in
                                onEnter()
                                return .handled
                            }
                            .onReceive(NotificationCenter.default.publisher(for: .copy)) { _ in
                                if focusedTaskID == task.id { onCopy() }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: .paste)) { _ in
                                if focusedTaskID == task.id { onPaste() }
                            }
                            .onSubmit { onSubmit() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TaskReorderHandle(
                payload: dragPayload,
                taskText: task.text,
                isCompleted: task.isCompleted,
                fontSize: fontSize,
                isDark: isDark
            )
            .padding(.trailing, 8)
        }
        .padding(.leading, 2)
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
