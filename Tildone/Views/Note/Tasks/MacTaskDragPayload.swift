//
//  MacTaskDragPayload.swift
//  Tildone
//

import CoreTransferable
import TildoneDomain
import UniformTypeIdentifiers

struct MacTaskDragPayload: Codable, Hashable, Transferable {
    // A text editor can accept public.json and intercept a task drop.
    static let contentType = UTType(exportedAs: "studio.cuatro.tildone.task-drag", conformingTo: .data)

    let noteID: NoteID
    let taskID: TaskID

    func isValid(for noteID: NoteID, taskIDs: [TaskID]) -> Bool {
        self.noteID == noteID && taskIDs.contains(taskID)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }
}
