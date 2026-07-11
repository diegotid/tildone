import Foundation
import SwiftData

/// The first schema of the new shared store. It has no relationship to the
/// released Mac application's legacy SwiftData schema or store.
public enum TildoneSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [StoredNote.self, StoredTask.self, PendingMutation.self, WorkspaceMetadata.self, QuarantinedRecord.self]
    }
}

public enum TildoneSchemaMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [TildoneSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

@Model
final class StoredNote {
    var stableID: String
    var createdAt: Date
    var title: String?
    var titleVersionCounter: Int64
    var titleVersionReplicaID: String
    var lifecycleRawValue: String
    var lifecycleVersionCounter: Int64
    var lifecycleVersionReplicaID: String
    var lastMeaningfulEditAt: Date
    var recordSchemaVersion: Int

    init(
        stableID: String,
        createdAt: Date,
        title: String?,
        titleVersionCounter: Int64,
        titleVersionReplicaID: String,
        lifecycleRawValue: String,
        lifecycleVersionCounter: Int64,
        lifecycleVersionReplicaID: String,
        lastMeaningfulEditAt: Date,
        recordSchemaVersion: Int
    ) {
        self.stableID = stableID
        self.createdAt = createdAt
        self.title = title
        self.titleVersionCounter = titleVersionCounter
        self.titleVersionReplicaID = titleVersionReplicaID
        self.lifecycleRawValue = lifecycleRawValue
        self.lifecycleVersionCounter = lifecycleVersionCounter
        self.lifecycleVersionReplicaID = lifecycleVersionReplicaID
        self.lastMeaningfulEditAt = lastMeaningfulEditAt
        self.recordSchemaVersion = recordSchemaVersion
    }
}

@Model
final class StoredTask {
    var stableID: String
    /// Stable ownership is retained even when either row is tombstoned.
    var noteStableID: String
    var createdAt: Date
    var text: String
    var textVersionCounter: Int64
    var textVersionReplicaID: String
    var isCompleted: Bool
    var completedAt: Date?
    var completionVersionCounter: Int64
    var completionVersionReplicaID: String
    var orderTokenRawValue: String
    var orderVersionCounter: Int64
    var orderVersionReplicaID: String
    var lifecycleRawValue: String
    var lifecycleVersionCounter: Int64
    var lifecycleVersionReplicaID: String
    var recordSchemaVersion: Int

    init(
        stableID: String,
        noteStableID: String,
        createdAt: Date,
        text: String,
        textVersionCounter: Int64,
        textVersionReplicaID: String,
        isCompleted: Bool,
        completedAt: Date?,
        completionVersionCounter: Int64,
        completionVersionReplicaID: String,
        orderTokenRawValue: String,
        orderVersionCounter: Int64,
        orderVersionReplicaID: String,
        lifecycleRawValue: String,
        lifecycleVersionCounter: Int64,
        lifecycleVersionReplicaID: String,
        recordSchemaVersion: Int
    ) {
        self.stableID = stableID
        self.noteStableID = noteStableID
        self.createdAt = createdAt
        self.text = text
        self.textVersionCounter = textVersionCounter
        self.textVersionReplicaID = textVersionReplicaID
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.completionVersionCounter = completionVersionCounter
        self.completionVersionReplicaID = completionVersionReplicaID
        self.orderTokenRawValue = orderTokenRawValue
        self.orderVersionCounter = orderVersionCounter
        self.orderVersionReplicaID = orderVersionReplicaID
        self.lifecycleRawValue = lifecycleRawValue
        self.lifecycleVersionCounter = lifecycleVersionCounter
        self.lifecycleVersionReplicaID = lifecycleVersionReplicaID
        self.recordSchemaVersion = recordSchemaVersion
    }
}

@Model
final class PendingMutation {
    var mutationID: String
    var targetKindRawValue: String
    var targetStableID: String
    var sequence: Int64
    var createdAt: Date
    var attemptCount: Int64
    var lastAttemptAt: Date?
    /// Superseded rows remain acknowledgeable but are not scheduled again.
    var supersededByMutationID: String?

    init(
        mutationID: String,
        targetKindRawValue: String,
        targetStableID: String,
        sequence: Int64,
        createdAt: Date,
        attemptCount: Int64 = 0,
        lastAttemptAt: Date? = nil,
        supersededByMutationID: String? = nil
    ) {
        self.mutationID = mutationID
        self.targetKindRawValue = targetKindRawValue
        self.targetStableID = targetStableID
        self.sequence = sequence
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
        self.supersededByMutationID = supersededByMutationID
    }
}

@Model
final class WorkspaceMetadata {
    var singletonKey: String
    var workspaceKindRawValue: String
    var opaqueWorkspaceID: String?
    var replicaID: String
    var logicalCounter: Int64
    var sharedSchemaVersion: Int
    /// Reserved bytes for a future sync engine. Persistence never interprets them.
    var futureSyncEngineState: Data?

    init(
        workspaceKindRawValue: String,
        opaqueWorkspaceID: String?,
        replicaID: String,
        logicalCounter: Int64 = 0,
        sharedSchemaVersion: Int = 1,
        futureSyncEngineState: Data? = nil
    ) {
        singletonKey = "workspace"
        self.workspaceKindRawValue = workspaceKindRawValue
        self.opaqueWorkspaceID = opaqueWorkspaceID
        self.replicaID = replicaID
        self.logicalCounter = logicalCounter
        self.sharedSchemaVersion = sharedSchemaVersion
        self.futureSyncEngineState = futureSyncEngineState
    }
}

@Model
final class QuarantinedRecord {
    var quarantineID: String
    var recordKind: String
    var opaqueRecordID: String
    var errorCategory: String
    var recordSchemaVersion: Int?
    var quarantinedAt: Date

    init(
        quarantineID: String = UUID().uuidString.lowercased(),
        recordKind: String,
        opaqueRecordID: String,
        errorCategory: String,
        recordSchemaVersion: Int?,
        quarantinedAt: Date
    ) {
        self.quarantineID = quarantineID
        self.recordKind = recordKind
        self.opaqueRecordID = opaqueRecordID
        self.errorCategory = errorCategory
        self.recordSchemaVersion = recordSchemaVersion
        self.quarantinedAt = quarantinedAt
    }
}
