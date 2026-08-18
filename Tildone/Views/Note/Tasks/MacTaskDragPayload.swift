//
//  MacTaskDragPayload.swift
//  Tildone
//

import CoreTransferable
import TildoneDomain
import UniformTypeIdentifiers

struct MacTaskDragPayload: Codable, Hashable, Transferable {
    let noteID: NoteID
    let taskID: TaskID

    func isValid(for noteID: NoteID, taskIDs: [TaskID]) -> Bool {
        self.noteID == noteID && taskIDs.contains(taskID)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
    }
}
