//
//  TaskReorderHandle.swift
//  Tildone
//

import SwiftUI

struct TaskReorderHandle: View {
    let payload: MacTaskDragPayload
    let taskText: String
    let isCompleted: Bool
    let fontSize: Double
    let isDark: Bool

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(
                (isDark ? Color(.primaryFontWhite) : Color(.primaryFontColor)).opacity(0.45)
            )
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .help("Drag to reorder")
            .accessibilityLabel("Reorder task")
            .draggable(payload) {
                TaskReorderPreview(
                    taskText: taskText,
                    isCompleted: isCompleted,
                    fontSize: fontSize,
                    isDark: isDark
                )
            }
    }
}
