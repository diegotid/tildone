//
//  DevelopmentCloudKitContractManifest.swift
//  Tildone
//
//  Reviewable contract generated from the same field constants as the mapper.
//
import Foundation
import TildoneDomain

public enum CloudKitContractFieldType: String, Codable, Hashable, Sendable {
    case int64 = "Int64"
    case string = "String"
    case date = "Date/Time"
    case bool = "Boolean"
}

public struct CloudKitContractField: Codable, Hashable, Sendable {
    public let name: String
    public let type: CloudKitContractFieldType
    public let optional: Bool

    public init(_ name: String, _ type: CloudKitContractFieldType, optional: Bool = false) {
        self.name = name
        self.type = type
        self.optional = optional
    }
}

public struct CloudKitRecordVersionContract: Codable, Hashable, Sendable {
    public let recordType: String
    public let schemaVersion: Int
    public let recordNameRule: String
    public let fields: [CloudKitContractField]
}

public enum DevelopmentCloudKitContractManifest {
    public static let database = "private"
    public static let zoneOwner = "CKCurrentUserDefaultName"

    private static let noteV1Fields: [CloudKitContractField] = [
        .init(CloudKitRecordMapper.Field.schemaVersion, .int64),
        .init(CloudKitRecordMapper.Field.createdAt, .date),
        .init(CloudKitRecordMapper.Field.title, .string, optional: true),
        .init(CloudKitRecordMapper.Field.titleCounter, .int64),
        .init(CloudKitRecordMapper.Field.titleReplica, .string),
        .init(CloudKitRecordMapper.Field.lifecycle, .string),
        .init(CloudKitRecordMapper.Field.lifecycleCounter, .int64),
        .init(CloudKitRecordMapper.Field.lifecycleReplica, .string),
        .init(CloudKitRecordMapper.Field.meaningfulEditAt, .date),
        .init(CloudKitRecordMapper.Field.meaningfulEditCounter, .int64),
        .init(CloudKitRecordMapper.Field.meaningfulEditReplica, .string)
    ]

    private static let noteV2Fields = noteV1Fields + [
        CloudKitContractField(CloudKitRecordMapper.Field.color, .string),
        CloudKitContractField(CloudKitRecordMapper.Field.colorCounter, .int64),
        CloudKitContractField(CloudKitRecordMapper.Field.colorReplica, .string)
    ]

    private static let taskV1Fields: [CloudKitContractField] = [
        .init(CloudKitRecordMapper.Field.schemaVersion, .int64),
        .init(CloudKitRecordMapper.Field.noteID, .string),
        .init(CloudKitRecordMapper.Field.createdAt, .date),
        .init(CloudKitRecordMapper.Field.text, .string),
        .init(CloudKitRecordMapper.Field.textCounter, .int64),
        .init(CloudKitRecordMapper.Field.textReplica, .string),
        .init(CloudKitRecordMapper.Field.isCompleted, .bool),
        .init(CloudKitRecordMapper.Field.completedAt, .date, optional: true),
        .init(CloudKitRecordMapper.Field.completionCounter, .int64),
        .init(CloudKitRecordMapper.Field.completionReplica, .string),
        .init(CloudKitRecordMapper.Field.orderToken, .string),
        .init(CloudKitRecordMapper.Field.orderCounter, .int64),
        .init(CloudKitRecordMapper.Field.orderReplica, .string),
        .init(CloudKitRecordMapper.Field.lifecycle, .string),
        .init(CloudKitRecordMapper.Field.lifecycleCounter, .int64),
        .init(CloudKitRecordMapper.Field.lifecycleReplica, .string)
    ]

    private static let taskV2Fields = taskV1Fields + [
        .init(CloudKitRecordMapper.Field.indentLevel, .int64),
        .init(CloudKitRecordMapper.Field.indentCounter, .int64),
        .init(CloudKitRecordMapper.Field.indentReplica, .string)
    ]

    private static let clientV1Fields: [CloudKitContractField] = [
        .init(CloudKitRecordMapper.Field.schemaVersion, .int64),
        .init(CloudKitRecordMapper.Field.clientReplicaID, .string),
        .init(CloudKitRecordMapper.Field.clientPlatform, .string)
    ]

    public static let records: [CloudKitRecordVersionContract] = [
        .init(
            recordType: TildoneCloudSchema.noteRecordType,
            schemaVersion: 1,
            recordNameRule: NoteID.recordNamePrefix + "<canonical-lowercase-UUID>",
            fields: noteV1Fields
        ),
        .init(
            recordType: TildoneCloudSchema.noteRecordType,
            schemaVersion: 2,
            recordNameRule: NoteID.recordNamePrefix + "<canonical-lowercase-UUID>",
            fields: noteV2Fields
        ),
        .init(
            recordType: TildoneCloudSchema.taskRecordType,
            schemaVersion: 1,
            recordNameRule: TaskID.recordNamePrefix + "<canonical-lowercase-UUID>",
            fields: taskV1Fields
        ),
        .init(
            recordType: TildoneCloudSchema.taskRecordType,
            schemaVersion: 2,
            recordNameRule: TaskID.recordNamePrefix + "<canonical-lowercase-UUID>",
            fields: taskV2Fields
        ),
        .init(
            recordType: TildoneCloudSchema.clientRecordType,
            schemaVersion: 1,
            recordNameRule: "client-<canonical-lowercase-replica-UUID>",
            fields: clientV1Fields
        )
    ]

    public static func markdown() -> String {
        var lines = [
            "# Development CloudKit contract manifest",
            "",
            "> Generated by `swift run --package-path Packages/TildoneCore TildoneCloudContractManifestGenerator` from the mapper's encoder/decoder field constants. Do not edit the field tables by hand.",
            "",
            "- Container: `\(TildoneCloudSchema.containerIdentifier)`",
            "- Database: `\(database)`",
            "- Custom zone: `\(TildoneCloudSchema.zoneName)`",
            "- Zone owner: `\(zoneOwner)`",
            "- Subscription ID: `\(TildoneCloudSchema.subscriptionIdentifier)`",
            ""
        ]
        for record in records {
            lines += [
                "## `\(record.recordType)` V\(record.schemaVersion)",
                "",
                "Record name: `\(record.recordNameRule)`",
                "",
                "| Field | CloudKit type | Optional |",
                "| --- | --- | --- |"
            ]
            lines += record.fields.map { field in
                let optionality = field.optional ? "yes" : "no"
                return "| `\(field.name)` | `\(field.type.rawValue)` | \(optionality) |"
            }
            lines.append("")
        }
        lines += [
            "## Compatibility behavior",
            "",
            "- `TDNote` V1 remains readable. Missing V2 color fields decode as yellow at the title version, then the local V3 sidecar migration queues a V2 note atomically.",
            "- Synthesized color authority is explicit: an existing V2 color wins; otherwise legacy Mac per-note/global color wins over a platform-default backfill; V1 implicit yellow has lowest authority.",
            "- `TDTask` V1 remains readable as indentation level zero at its order version. V2 adds an independently versioned indentation depth. `TDClient` accepts V1 only and is advisory metadata outside the content outbox; last-seen time is CloudKit server modification metadata, not a record field.",
            "- Unknown types, future schema versions, malformed identifiers, wrong-zone records, missing required fields, and invalid field types are rejected/quarantined. Content records use lifecycle tombstones; unexpected physical deletions are normalized locally.",
            "- All records live only in the named custom zone of the private database. Record names contain stable IDs only, never note titles or task text.",
            ""
        ]
        return lines.joined(separator: "\n")
    }
}
