import Foundation
import TildoneDomain

enum StoredDomainMapping {
    static func note(from stored: StoredNote) throws -> Note {
        guard let id = NoteID(string: stored.stableID) else {
            throw malformed(.note, "invalid", "stableID")
        }
        try validateSchema(stored.recordSchemaVersion, kind: .note)
        guard let lifecycle = LifecycleState(rawValue: stored.lifecycleRawValue) else {
            throw malformed(.note, id.stringValue, "lifecycle")
        }
        return Note(
            id: id,
            createdAt: stored.createdAt,
            title: stored.title,
            titleVersion: try stamp(
                counter: stored.titleVersionCounter,
                replica: stored.titleVersionReplicaID,
                kind: .note,
                stableID: id.stringValue,
                field: "titleVersion"
            ),
            lifecycle: lifecycle,
            lifecycleVersion: try stamp(
                counter: stored.lifecycleVersionCounter,
                replica: stored.lifecycleVersionReplicaID,
                kind: .note,
                stableID: id.stringValue,
                field: "lifecycleVersion"
            ),
            lastMeaningfulEditAt: stored.lastMeaningfulEditAt,
            schemaVersion: stored.recordSchemaVersion
        )
    }

    static func task(from stored: StoredTask, expectedNoteID: NoteID? = nil) throws -> Task {
        guard let id = TaskID(string: stored.stableID) else {
            throw malformed(.task, "invalid", "stableID")
        }
        guard let noteID = NoteID(string: stored.noteStableID) else {
            throw malformed(.task, id.stringValue, "ownership")
        }
        if let expectedNoteID, expectedNoteID != noteID {
            throw PersistenceError.ownershipMismatch(
                taskID: id.stringValue,
                expectedNoteID: expectedNoteID.stringValue
            )
        }
        try validateSchema(stored.recordSchemaVersion, kind: .task)
        guard let lifecycle = LifecycleState(rawValue: stored.lifecycleRawValue) else {
            throw malformed(.task, id.stringValue, "lifecycle")
        }
        guard stored.isCompleted == (stored.completedAt != nil) else {
            throw malformed(.task, id.stringValue, "completion")
        }
        let completion: CompletionState = if let completedAt = stored.completedAt {
            .completed(at: completedAt)
        } else {
            .incomplete
        }
        let token: OrderToken
        do {
            token = try OrderToken(rawValue: stored.orderTokenRawValue)
        } catch {
            throw malformed(.task, id.stringValue, "orderToken")
        }
        return Task(
            id: id,
            noteID: noteID,
            createdAt: stored.createdAt,
            text: stored.text,
            textVersion: try stamp(
                counter: stored.textVersionCounter,
                replica: stored.textVersionReplicaID,
                kind: .task,
                stableID: id.stringValue,
                field: "textVersion"
            ),
            completion: completion,
            completionVersion: try stamp(
                counter: stored.completionVersionCounter,
                replica: stored.completionVersionReplicaID,
                kind: .task,
                stableID: id.stringValue,
                field: "completionVersion"
            ),
            orderToken: token,
            orderVersion: try stamp(
                counter: stored.orderVersionCounter,
                replica: stored.orderVersionReplicaID,
                kind: .task,
                stableID: id.stringValue,
                field: "orderVersion"
            ),
            lifecycle: lifecycle,
            lifecycleVersion: try stamp(
                counter: stored.lifecycleVersionCounter,
                replica: stored.lifecycleVersionReplicaID,
                kind: .task,
                stableID: id.stringValue,
                field: "lifecycleVersion"
            ),
            schemaVersion: stored.recordSchemaVersion
        )
    }

    static func storedNote(from note: Note) throws -> StoredNote {
        let title = try parts(note.titleVersion)
        let lifecycle = try parts(note.lifecycleVersion)
        return StoredNote(
            stableID: note.id.stringValue,
            createdAt: note.createdAt,
            title: note.title,
            titleVersionCounter: title.counter,
            titleVersionReplicaID: title.replica,
            lifecycleRawValue: note.lifecycle.rawValue,
            lifecycleVersionCounter: lifecycle.counter,
            lifecycleVersionReplicaID: lifecycle.replica,
            lastMeaningfulEditAt: note.lastMeaningfulEditAt,
            recordSchemaVersion: note.schemaVersion
        )
    }

    static func update(_ stored: StoredNote, from note: Note) throws {
        let title = try parts(note.titleVersion)
        let lifecycle = try parts(note.lifecycleVersion)
        stored.title = note.title
        stored.titleVersionCounter = title.counter
        stored.titleVersionReplicaID = title.replica
        stored.lifecycleRawValue = note.lifecycle.rawValue
        stored.lifecycleVersionCounter = lifecycle.counter
        stored.lifecycleVersionReplicaID = lifecycle.replica
        stored.lastMeaningfulEditAt = note.lastMeaningfulEditAt
        stored.recordSchemaVersion = note.schemaVersion
    }

    static func storedTask(from task: Task) throws -> StoredTask {
        let text = try parts(task.textVersion)
        let completion = try parts(task.completionVersion)
        let order = try parts(task.orderVersion)
        let lifecycle = try parts(task.lifecycleVersion)
        return StoredTask(
            stableID: task.id.stringValue,
            noteStableID: task.noteID.stringValue,
            createdAt: task.createdAt,
            text: task.text,
            textVersionCounter: text.counter,
            textVersionReplicaID: text.replica,
            isCompleted: task.isCompleted,
            completedAt: task.completedAt,
            completionVersionCounter: completion.counter,
            completionVersionReplicaID: completion.replica,
            orderTokenRawValue: task.orderToken.rawValue,
            orderVersionCounter: order.counter,
            orderVersionReplicaID: order.replica,
            lifecycleRawValue: task.lifecycle.rawValue,
            lifecycleVersionCounter: lifecycle.counter,
            lifecycleVersionReplicaID: lifecycle.replica,
            recordSchemaVersion: task.schemaVersion
        )
    }

    static func update(_ stored: StoredTask, from task: Task) throws {
        let text = try parts(task.textVersion)
        let completion = try parts(task.completionVersion)
        let order = try parts(task.orderVersion)
        let lifecycle = try parts(task.lifecycleVersion)
        guard stored.noteStableID == task.noteID.stringValue else {
            throw PersistenceError.ownershipMismatch(
                taskID: task.id.stringValue,
                expectedNoteID: stored.noteStableID
            )
        }
        stored.text = task.text
        stored.textVersionCounter = text.counter
        stored.textVersionReplicaID = text.replica
        stored.isCompleted = task.isCompleted
        stored.completedAt = task.completedAt
        stored.completionVersionCounter = completion.counter
        stored.completionVersionReplicaID = completion.replica
        stored.orderTokenRawValue = task.orderToken.rawValue
        stored.orderVersionCounter = order.counter
        stored.orderVersionReplicaID = order.replica
        stored.lifecycleRawValue = task.lifecycle.rawValue
        stored.lifecycleVersionCounter = lifecycle.counter
        stored.lifecycleVersionReplicaID = lifecycle.replica
        stored.recordSchemaVersion = task.schemaVersion
    }

    private static func validateSchema(_ version: Int, kind: PersistedEntityKind) throws {
        guard version > 0 else {
            throw PersistenceError.malformedRepresentation(kind, "unknown", field: "schemaVersion")
        }
        let current = kind == .note ? Note.currentSchemaVersion : Task.currentSchemaVersion
        guard version <= current else {
            throw PersistenceError.unsupportedRecordSchema(kind, version)
        }
    }

    private static func stamp(
        counter: Int64,
        replica: String,
        kind: PersistedEntityKind,
        stableID: String,
        field: String
    ) throws -> VersionStamp {
        guard counter >= 0, let replicaID = ReplicaID(string: replica) else {
            throw malformed(kind, stableID, field)
        }
        return VersionStamp(logicalCounter: UInt64(counter), replicaID: replicaID)
    }

    private static func parts(_ stamp: VersionStamp) throws -> (counter: Int64, replica: String) {
        guard stamp.logicalCounter <= UInt64(Int64.max) else {
            throw PersistenceError.counterOverflow
        }
        return (Int64(stamp.logicalCounter), stamp.replicaID.stringValue)
    }

    private static func malformed(
        _ kind: PersistedEntityKind,
        _ stableID: String,
        _ field: String
    ) -> PersistenceError {
        .malformedRepresentation(kind, stableID, field: field)
    }
}
