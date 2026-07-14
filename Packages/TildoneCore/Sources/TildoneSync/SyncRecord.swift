//
//  SyncRecord.swift
//  Tildone
//
import Foundation
import TildoneDomain

/// The transport-independent unit exchanged by the synchronization pipeline.
/// CloudKit is only one adapter for this representation.
public enum SyncRecord: Codable, Hashable, Sendable {
    case note(Note)
    case task(Task)

    public var recordName: String {
        switch self {
        case let .note(note): note.id.recordName
        case let .task(task): task.id.recordName
        }
    }

    public var schemaVersion: Int {
        switch self {
        case let .note(note): note.schemaVersion
        case let .task(task): task.schemaVersion
        }
    }
}

public struct SyncOutboundMutation: Hashable, Sendable {
    public let mutationID: UUID
    public let record: SyncRecord

    public init(mutationID: UUID, record: SyncRecord) {
        self.mutationID = mutationID
        self.record = record
    }
}

public enum SyncRecordKind: String, Codable, Hashable, Sendable {
    case note
    case task
}

public extension SyncRecord {
    var kind: SyncRecordKind {
        switch self {
        case .note: .note
        case .task: .task
        }
    }
}
