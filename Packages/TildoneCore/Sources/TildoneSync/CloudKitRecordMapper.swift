//
//  CloudKitRecordMapper.swift
//  Tildone
//
import CloudKit
import Foundation
import TildoneDomain

public enum TildoneCloudSchema {
    public static let containerIdentifier = "iCloud.studio.cuatro.tildone"
    public static let zoneName = "TildoneUserData"
    public static let subscriptionIdentifier = "tildone-private-zone-v1"
    public static let noteRecordType = "TDNote"
    public static let taskRecordType = "TDTask"

    public static var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }
}

public enum CloudRecordMappingError: Error, Equatable, Sendable {
    case unsupportedRecordType(String)
    case malformedIdentifier(String)
    case wrongZone(String)
    case missingField(String, String)
    case invalidField(String, String)
    case unsupportedSchema(String, Int)

    public var safeRecordName: String {
        switch self {
        case let .unsupportedRecordType(name), let .malformedIdentifier(name),
             let .wrongZone(name), let .missingField(name, _),
             let .invalidField(name, _), let .unsupportedSchema(name, _):
            name
        }
    }
}

public struct CloudKitRecordMapper: Sendable {
    public init() {}

    public func record(
        from value: SyncRecord,
        reusing systemRecord: CKRecord? = nil
    ) -> CKRecord {
        let recordType: String
        switch value {
        case .note: recordType = TildoneCloudSchema.noteRecordType
        case .task: recordType = TildoneCloudSchema.taskRecordType
        }
        let expectedID = CKRecord.ID(
            recordName: value.recordName,
            zoneID: TildoneCloudSchema.zoneID
        )
        let record: CKRecord
        if let systemRecord,
           systemRecord.recordID == expectedID,
           systemRecord.recordType == recordType {
            record = systemRecord
        } else {
            record = CKRecord(recordType: recordType, recordID: expectedID)
        }
        clearKnownFields(on: record)
        switch value {
        case let .note(note): encode(note, into: record)
        case let .task(task): encode(task, into: record)
        }
        return record
    }

    public func syncRecord(from record: CKRecord) throws -> SyncRecord {
        let name = record.recordID.recordName
        guard record.recordID.zoneID == TildoneCloudSchema.zoneID else {
            throw CloudRecordMappingError.wrongZone(name)
        }
        switch record.recordType {
        case TildoneCloudSchema.noteRecordType:
            return .note(try decodeNote(record))
        case TildoneCloudSchema.taskRecordType:
            return .task(try decodeTask(record))
        default:
            throw CloudRecordMappingError.unsupportedRecordType(safeUnknownName(for: record))
        }
    }
}

private extension CloudKitRecordMapper {
    enum Field {
        static let schemaVersion = "schemaVersion"
        static let createdAt = "createdAt"
        static let title = "title"
        static let titleCounter = "titleVersionCounter"
        static let titleReplica = "titleVersionReplicaID"
        static let lifecycle = "lifecycle"
        static let lifecycleCounter = "lifecycleVersionCounter"
        static let lifecycleReplica = "lifecycleVersionReplicaID"
        static let meaningfulEditAt = "lastMeaningfulEditAt"
        static let meaningfulEditCounter = "lastMeaningfulEditVersionCounter"
        static let meaningfulEditReplica = "lastMeaningfulEditVersionReplicaID"
        static let noteID = "noteID"
        static let text = "text"
        static let textCounter = "textVersionCounter"
        static let textReplica = "textVersionReplicaID"
        static let isCompleted = "isCompleted"
        static let completedAt = "completedAt"
        static let completionCounter = "completionVersionCounter"
        static let completionReplica = "completionVersionReplicaID"
        static let orderToken = "orderToken"
        static let orderCounter = "orderVersionCounter"
        static let orderReplica = "orderVersionReplicaID"

        static let all = [
            schemaVersion, createdAt, title, titleCounter, titleReplica,
            lifecycle, lifecycleCounter, lifecycleReplica, meaningfulEditAt,
            meaningfulEditCounter, meaningfulEditReplica, noteID, text,
            textCounter, textReplica, isCompleted, completedAt,
            completionCounter, completionReplica, orderToken, orderCounter,
            orderReplica
        ]
    }

    func clearKnownFields(on record: CKRecord) {
        for field in Field.all { record[field] = nil }
    }

    func encode(_ note: Note, into record: CKRecord) {
        record[Field.schemaVersion] = NSNumber(value: note.schemaVersion)
        record[Field.createdAt] = note.createdAt as NSDate
        record[Field.title] = note.title as NSString?
        encode(note.titleVersion, prefixCounter: Field.titleCounter, replica: Field.titleReplica, into: record)
        record[Field.lifecycle] = note.lifecycle.rawValue as NSString
        encode(note.lifecycleVersion, prefixCounter: Field.lifecycleCounter, replica: Field.lifecycleReplica, into: record)
        record[Field.meaningfulEditAt] = note.lastMeaningfulEditAt as NSDate
        encode(note.lastMeaningfulEditVersion, prefixCounter: Field.meaningfulEditCounter, replica: Field.meaningfulEditReplica, into: record)
    }

    func encode(_ task: Task, into record: CKRecord) {
        record[Field.schemaVersion] = NSNumber(value: task.schemaVersion)
        record[Field.noteID] = task.noteID.stringValue as NSString
        record[Field.createdAt] = task.createdAt as NSDate
        record[Field.text] = task.text as NSString
        encode(task.textVersion, prefixCounter: Field.textCounter, replica: Field.textReplica, into: record)
        record[Field.isCompleted] = NSNumber(value: task.isCompleted)
        record[Field.completedAt] = task.completedAt as NSDate?
        encode(task.completionVersion, prefixCounter: Field.completionCounter, replica: Field.completionReplica, into: record)
        record[Field.orderToken] = task.orderToken.rawValue as NSString
        encode(task.orderVersion, prefixCounter: Field.orderCounter, replica: Field.orderReplica, into: record)
        record[Field.lifecycle] = task.lifecycle.rawValue as NSString
        encode(task.lifecycleVersion, prefixCounter: Field.lifecycleCounter, replica: Field.lifecycleReplica, into: record)
    }

    func encode(
        _ stamp: VersionStamp,
        prefixCounter counter: String,
        replica: String,
        into record: CKRecord
    ) {
        record[counter] = NSNumber(value: stamp.logicalCounter)
        record[replica] = stamp.replicaID.stringValue as NSString
    }

    func decodeNote(_ record: CKRecord) throws -> Note {
        let name = record.recordID.recordName
        guard let id = NoteID(recordName: name) else {
            throw CloudRecordMappingError.malformedIdentifier(name)
        }
        let schema = try int(Field.schemaVersion, in: record)
        guard schema == Note.currentSchemaVersion else {
            throw CloudRecordMappingError.unsupportedSchema(name, schema)
        }
        return Note(
            id: id,
            createdAt: try date(Field.createdAt, in: record),
            title: try optionalString(Field.title, in: record),
            titleVersion: try stamp(Field.titleCounter, Field.titleReplica, in: record),
            lifecycle: try lifecycle(in: record),
            lifecycleVersion: try stamp(Field.lifecycleCounter, Field.lifecycleReplica, in: record),
            lastMeaningfulEditAt: try date(Field.meaningfulEditAt, in: record),
            lastMeaningfulEditVersion: try stamp(Field.meaningfulEditCounter, Field.meaningfulEditReplica, in: record),
            schemaVersion: schema
        )
    }

    func decodeTask(_ record: CKRecord) throws -> Task {
        let name = record.recordID.recordName
        guard let id = TaskID(recordName: name) else {
            throw CloudRecordMappingError.malformedIdentifier(name)
        }
        let schema = try int(Field.schemaVersion, in: record)
        guard schema == Task.currentSchemaVersion else {
            throw CloudRecordMappingError.unsupportedSchema(name, schema)
        }
        guard let noteID = NoteID(string: try string(Field.noteID, in: record)) else {
            throw CloudRecordMappingError.invalidField(name, Field.noteID)
        }
        let completed = try bool(Field.isCompleted, in: record)
        let completedAt = try optionalDate(Field.completedAt, in: record)
        guard completed == (completedAt != nil) else {
            throw CloudRecordMappingError.invalidField(name, Field.completedAt)
        }
        let completion: CompletionState = completed ? .completed(at: completedAt!) : .incomplete
        let rawOrder = try string(Field.orderToken, in: record)
        guard let order = try? OrderToken(rawValue: rawOrder) else {
            throw CloudRecordMappingError.invalidField(name, Field.orderToken)
        }
        return Task(
            id: id,
            noteID: noteID,
            createdAt: try date(Field.createdAt, in: record),
            text: try string(Field.text, in: record),
            textVersion: try stamp(Field.textCounter, Field.textReplica, in: record),
            completion: completion,
            completionVersion: try stamp(Field.completionCounter, Field.completionReplica, in: record),
            orderToken: order,
            orderVersion: try stamp(Field.orderCounter, Field.orderReplica, in: record),
            lifecycle: try lifecycle(in: record),
            lifecycleVersion: try stamp(Field.lifecycleCounter, Field.lifecycleReplica, in: record),
            schemaVersion: schema
        )
    }

    func stamp(_ counter: String, _ replica: String, in record: CKRecord) throws -> VersionStamp {
        let value = try int64(counter, in: record)
        guard value > 0,
              let replicaID = ReplicaID(string: try string(replica, in: record)) else {
            throw CloudRecordMappingError.invalidField(record.recordID.recordName, counter)
        }
        return VersionStamp(logicalCounter: UInt64(value), replicaID: replicaID)
    }

    func lifecycle(in record: CKRecord) throws -> LifecycleState {
        guard let value = LifecycleState(rawValue: try string(Field.lifecycle, in: record)) else {
            throw CloudRecordMappingError.invalidField(record.recordID.recordName, Field.lifecycle)
        }
        return value
    }

    func string(_ field: String, in record: CKRecord) throws -> String {
        guard let value = record[field] as? String else {
            throw CloudRecordMappingError.missingField(record.recordID.recordName, field)
        }
        return value
    }

    func optionalString(_ field: String, in record: CKRecord) throws -> String? {
        guard let value = record[field] else { return nil }
        guard let string = value as? String else {
            throw CloudRecordMappingError.invalidField(record.recordID.recordName, field)
        }
        return string
    }

    func date(_ field: String, in record: CKRecord) throws -> Date {
        guard let value = record[field] as? Date,
              value.timeIntervalSinceReferenceDate.isFinite else {
            throw CloudRecordMappingError.missingField(record.recordID.recordName, field)
        }
        return value
    }

    func optionalDate(_ field: String, in record: CKRecord) throws -> Date? {
        guard let value = record[field] else { return nil }
        guard let date = value as? Date,
              date.timeIntervalSinceReferenceDate.isFinite else {
            throw CloudRecordMappingError.invalidField(record.recordID.recordName, field)
        }
        return date
    }

    func int(_ field: String, in record: CKRecord) throws -> Int {
        let value = try int64(field, in: record)
        guard value <= Int64(Int.max), value >= Int64(Int.min) else {
            throw CloudRecordMappingError.invalidField(record.recordID.recordName, field)
        }
        return Int(value)
    }

    func int64(_ field: String, in record: CKRecord) throws -> Int64 {
        guard let number = record[field] as? NSNumber else {
            throw CloudRecordMappingError.missingField(record.recordID.recordName, field)
        }
        return number.int64Value
    }

    func bool(_ field: String, in record: CKRecord) throws -> Bool {
        guard let number = record[field] as? NSNumber else {
            throw CloudRecordMappingError.missingField(record.recordID.recordName, field)
        }
        return number.boolValue
    }

    func safeUnknownName(for record: CKRecord) -> String {
        if NoteID(recordName: record.recordID.recordName) != nil ||
            TaskID(recordName: record.recordID.recordName) != nil {
            return record.recordID.recordName
        }
        return "unknown-" + UUID().uuidString.lowercased()
    }
}
