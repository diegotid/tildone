//
//  LegacyMigrationTypes.swift
//  Tildone
//
//  Created by OpenAI Codex on 7/13/26.
//
import Foundation
import TildoneDomain

public enum LegacyMigrationPhase: String, Codable, Hashable, Sendable {
    case notStarted = "not-started"
    case sourceInspected = "source-inspected"
    case destinationPrepared = "destination-prepared"
    case copyInProgress = "copy-in-progress"
    case copyCompleted = "copy-completed"
    case verificationInProgress = "verification-in-progress"
    case verified
    case eligibleForCutover = "eligible-for-cutover"
    case failed
}

public enum LegacyMigrationFailureCategory: String, Codable, Hashable, Sendable {
    case missingSource = "missing-source"
    case sourceOpen = "source-open"
    case incompatibleSource = "incompatible-source"
    case sourceChanged = "source-changed"
    case differentSource = "different-source"
    case sourceDestinationCollision = "source-destination-collision"
    case invalidRelationship = "invalid-relationship"
    case destinationOpen = "destination-open"
    case destinationNotEmpty = "destination-not-empty"
    case destinationWrite = "destination-write"
    case migrationVersionMismatch = "migration-version-mismatch"
    case priorFailedDestination = "prior-failed-destination"
    case verificationMismatch = "verification-mismatch"
    case unsupportedDestinationSchema = "unsupported-destination-schema"
}

public enum LegacyMigrationActivationState: String, Codable, Hashable, Sendable {
    case notActivated = "not-activated"
    case verifiedNotActivated = "verified-not-activated"
    case activated
}

public enum LegacyMigrationEntityKind: String, Codable, Hashable, Sendable {
    case note
    case task
}

public enum LegacyMigrationClassification: String, Codable, Hashable, Sendable {
    case userContent = "user-content"
    case excludedSystemNote = "excluded-system-note"
    case excludedSystemTask = "excluded-system-task"
    case excludedTransientEmptyTask = "excluded-transient-empty-task"
}

public struct LegacySourceFingerprint: Codable, Hashable, Sendable {
    public let identityDigest: String
    public let contentDigest: String
    public let fileCount: Int
    public let totalByteCount: UInt64

    public init(identityDigest: String, contentDigest: String, fileCount: Int, totalByteCount: UInt64) {
        self.identityDigest = identityDigest
        self.contentDigest = contentDigest
        self.fileCount = fileCount
        self.totalByteCount = totalByteCount
    }
}

public struct LegacyMigrationCounts: Codable, Hashable, Sendable {
    public let eligibleNotes: Int
    public let eligibleTasks: Int
    public let excludedSystemNotes: Int
    public let excludedSystemTasks: Int
    public let excludedTransientTasks: Int

    public init(
        eligibleNotes: Int,
        eligibleTasks: Int,
        excludedSystemNotes: Int,
        excludedSystemTasks: Int,
        excludedTransientTasks: Int
    ) {
        self.eligibleNotes = eligibleNotes
        self.eligibleTasks = eligibleTasks
        self.excludedSystemNotes = excludedSystemNotes
        self.excludedSystemTasks = excludedSystemTasks
        self.excludedTransientTasks = excludedTransientTasks
    }

    public static let zero = Self(
        eligibleNotes: 0,
        eligibleTasks: 0,
        excludedSystemNotes: 0,
        excludedSystemTasks: 0,
        excludedTransientTasks: 0
    )
}

public struct LegacyMigrationSnapshot: Codable, Hashable, Sendable {
    public let migrationFormatVersion: Int
    public let phase: LegacyMigrationPhase
    public let lastCompletedPhase: LegacyMigrationPhase
    public let failureCategory: LegacyMigrationFailureCategory?
    public let sourceFingerprint: LegacySourceFingerprint
    public let destinationSchemaVersion: Int
    public let sourceCounts: LegacyMigrationCounts
    public let destinationNoteCount: Int
    public let destinationTaskCount: Int
    public let mappingCount: Int
    public let migrationReplicaID: ReplicaID
    public let logicalCounterProgress: UInt64
    public let startedAt: Date
    public let updatedAt: Date
    public let copyCompletedAt: Date?
    public let verifiedAt: Date?
    public let eligibleAt: Date?
    public let activationState: LegacyMigrationActivationState
    public let cloudSeedingEverBegun: Bool
}

public struct LegacyMappingRequest: Hashable, Sendable {
    public let legacyKey: String
    public let entityKind: LegacyMigrationEntityKind
    public let classification: LegacyMigrationClassification
    public let ownerLegacyKey: String?
    public let visibleOrder: Int?

    public init(
        legacyKey: String,
        entityKind: LegacyMigrationEntityKind,
        classification: LegacyMigrationClassification,
        ownerLegacyKey: String? = nil,
        visibleOrder: Int? = nil
    ) {
        self.legacyKey = legacyKey
        self.entityKind = entityKind
        self.classification = classification
        self.ownerLegacyKey = ownerLegacyKey
        self.visibleOrder = visibleOrder
    }
}

public struct LegacyMappingSnapshot: Codable, Hashable, Sendable {
    public let legacyKey: String
    public let entityKind: LegacyMigrationEntityKind
    public let classification: LegacyMigrationClassification
    public let stableID: String?
    public let ownerLegacyKey: String?
    public let visibleOrder: Int?
    public let firstVersionCounter: UInt64?
    public let versionCount: Int
}

public struct LegacyImportedNote: Hashable, Sendable {
    public let legacyKey: String
    public let createdAt: Date
    public let title: String?
    public let lastMeaningfulEditAt: Date

    public init(legacyKey: String, createdAt: Date, title: String?, lastMeaningfulEditAt: Date) {
        self.legacyKey = legacyKey
        self.createdAt = createdAt
        self.title = title
        self.lastMeaningfulEditAt = lastMeaningfulEditAt
    }
}

public struct LegacyImportedTask: Hashable, Sendable {
    public let legacyKey: String
    public let ownerLegacyKey: String
    public let createdAt: Date
    public let text: String
    public let completedAt: Date?
    public let orderToken: OrderToken

    public init(
        legacyKey: String,
        ownerLegacyKey: String,
        createdAt: Date,
        text: String,
        completedAt: Date?,
        orderToken: OrderToken
    ) {
        self.legacyKey = legacyKey
        self.ownerLegacyKey = ownerLegacyKey
        self.createdAt = createdAt
        self.text = text
        self.completedAt = completedAt
        self.orderToken = orderToken
    }
}

public struct LegacyMigrationAudit: Codable, Hashable, Sendable {
    public let noteCount: Int
    public let taskCount: Int
    public let mappingCount: Int
    public let pendingMutationCount: Int
    public let duplicateNoteIDs: Bool
    public let duplicateTaskIDs: Bool
    public let duplicateMappedStableIDs: Bool
    public let destinationSchemaVersion: Int
}

public enum LegacyMigrationPersistenceError: Error, Equatable, Sendable {
    case stateMissing
    case invalidState
    case incompatibleExistingState(LegacyMigrationFailureCategory)
    case invalidFingerprint
    case invalidMapping(String)
    case missingMapping(String)
    case importedValueMismatch(String)
    case destinationNotEmpty
    case saveFailure
}
