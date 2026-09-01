//
//  TildoneiOSNoteSnapshot.swift
//  Tildone
//

import TildoneDomain

struct TildoneiOSNoteSnapshot: Equatable {
    let note: Note?
    let tasks: [Task]

    static let empty = TildoneiOSNoteSnapshot(note: nil, tasks: [])
}
