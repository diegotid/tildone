//
//  MacSyncContentSnapshot.swift
//  Tildone
//

import TildoneDomain

struct MacSyncContentSnapshot {
    let notes: [TildoneDomain.Note]
    let tasks: [TildoneDomain.Task]
    let fingerprint: String
}
