//
//  NoteTaskPreview.swift
//  Tildone
//

import TildoneDomain

struct NoteTaskPreview: Identifiable, Hashable {
    let id: TaskID
    let richText: RichText
    var text: String { richText.text }
    let isCompleted: Bool
    let indentLevel: Int
    let subtaskProgress: TaskSubtaskProgress?

    init(_ task: Task, subtaskProgress: TaskSubtaskProgress? = nil) {
        id = task.id
        richText = task.richText
        isCompleted = task.isCompleted
        indentLevel = task.indentLevel
        self.subtaskProgress = subtaskProgress
    }
}
