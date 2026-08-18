//
//  TaskReorderDropTarget.swift
//  Tildone
//

import SwiftUI

struct TaskReorderDropTarget: View {
    let feedbackResetToken: UUID
    let onDrop: (MacTaskDragPayload) -> Bool
    @State private var isTargeted = false

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(
                height: isTargeted
                    ? TaskReorderFeedback.expandedHeight
                    : TaskReorderFeedback.restingHeight
            )
            .contentShape(Rectangle())
            .background {
                TaskReorderInsertionLine()
                    .opacity(isTargeted ? 1 : 0)
            }
            .dropDestination(for: MacTaskDragPayload.self) { payloads, _ in
                guard payloads.count == 1, let payload = payloads.first else { return false }
                return onDrop(payload)
            } isTargeted: {
                isTargeted = $0
            }
            .animation(TaskReorderFeedback.animation, value: isTargeted)
            .onChange(of: feedbackResetToken) { _, _ in
                isTargeted = false
            }
    }
}
