//
//  Fixtures.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
import Foundation
@testable import TildoneDomain

enum Fixtures {
    static let noteID = NoteID(testUUID("10000000-0000-0000-0000-000000000001"))
    static let otherNoteID = NoteID(testUUID("10000000-0000-0000-0000-000000000002"))
    static let replicaID = ReplicaID(testUUID("20000000-0000-0000-0000-000000000001"))
    static let createdAt = Date(timeIntervalSince1970: 10)

    static func taskID(_ suffix: Int = 1) -> TaskID {
        TaskID(testUUID(String(format: "30000000-0000-0000-0000-%012d", suffix)))
    }

    static func stamp(_ counter: UInt64) -> VersionStamp {
        VersionStamp(logicalCounter: counter, replicaID: replicaID)
    }

    static func note(lastMeaningfulEditAt: Date = createdAt) -> Note {
        Note(
            id: noteID,
            createdAt: createdAt,
            title: "Title",
            titleVersion: stamp(1),
            lifecycleVersion: stamp(1),
            lastMeaningfulEditAt: lastMeaningfulEditAt
        )
    }

    static func task(id: TaskID = taskID(), noteID: NoteID = noteID) throws -> Task {
        Task(
            id: id,
            noteID: noteID,
            createdAt: createdAt,
            text: "Task",
            textVersion: stamp(1),
            completionVersion: stamp(1),
            orderToken: try OrderToken(rawValue: "h"),
            orderVersion: stamp(1),
            lifecycleVersion: stamp(1)
        )
    }
}

func testUUID(_ string: String) -> UUID {
    UUID(uuidString: string) ?? UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}
