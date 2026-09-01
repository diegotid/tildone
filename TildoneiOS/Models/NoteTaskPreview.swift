//
//  NoteTaskPreview.swift
//  Tildone
//

import TildoneDomain

struct NoteTaskPreview: Identifiable, Hashable {
    let id: TaskID
    let text: String
    let isCompleted: Bool
    let indentLevel: Int
    let subtaskProgress: TaskSubtaskProgress?

    init(_ task: Task, subtaskProgress: TaskSubtaskProgress? = nil) {
        id = task.id
        text = task.text
        isCompleted = task.isCompleted
        indentLevel = task.indentLevel
        self.subtaskProgress = subtaskProgress
    }
}
