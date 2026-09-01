//
//  TildoneiOSOverviewSnapshot.swift
//  Tildone
//

import TildoneDomain

struct TildoneiOSOverviewSnapshot {
    var notes: [Note] = []
    var taskSummaries: [NoteID: NoteTaskSummary] = [:]
    var taskListTexts: [NoteID: String] = [:]
    var taskPreviews: [NoteID: [NoteTaskPreview]] = [:]
}
