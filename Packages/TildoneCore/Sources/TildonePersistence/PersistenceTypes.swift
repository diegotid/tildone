//
//  PersistenceTypes.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
import Foundation
import TildoneDomain

public enum PersistedEntityKind: String, Codable, Hashable, Sendable {
    case note
    case task
}

public enum PersistenceError: Error, Equatable, Sendable {
    case openFailure
    case saveFailure
    case missing(PersistedEntityKind, String)
    case missingPendingMutation(String)
    case duplicateID(PersistedEntityKind, String)
    case ownershipMismatch(taskID: String, expectedNoteID: String)
    case malformedRepresentation(PersistedEntityKind, String, field: String)
    case domainInvariant
    case unsupportedRecordSchema(PersistedEntityKind, Int)
    case workspaceMismatch
    case workspaceInUse
    case invalidWorkspace
    case invalidStoreLocation
    case invalidQuarantineMetadata
    case atomicMutationFailure
    case counterOverflow
}

public enum WorkspaceIdentity: Hashable, Sendable {
    case localOnly
    /// The UUID is an opaque account-scoped identifier supplied by the caller.
    case account(UUID)

    var kindRawValue: String {
        switch self {
        case .localOnly: "local-only"
        case .account: "account"
        }
    }

    var opaqueID: String? {
        switch self {
        case .localOnly: nil
        case let .account(id): id.uuidString.lowercased()
        }
    }
}

public enum PersistenceStoreKind: Hashable, Sendable {
    case persistent
    case inMemory
    case preview
    case temporaryMigration
}

public struct PersistenceStoreDescriptor: Hashable, Sendable {
    public let kind: PersistenceStoreKind
    public let workspace: WorkspaceIdentity
    public let baseDirectory: URL?
    public let identifier: UUID
    public let explicitStoreURL: URL?

    private init(
        kind: PersistenceStoreKind,
        workspace: WorkspaceIdentity,
        baseDirectory: URL?,
        identifier: UUID,
        explicitStoreURL: URL? = nil
    ) {
        self.kind = kind
        self.workspace = workspace
        self.baseDirectory = baseDirectory
        self.identifier = identifier
        self.explicitStoreURL = explicitStoreURL
    }

    public static func persistent(baseDirectory: URL, workspace: WorkspaceIdentity) -> Self {
        Self(kind: .persistent, workspace: workspace, baseDirectory: baseDirectory, identifier: UUID())
    }

    public static func inMemory(
        workspace: WorkspaceIdentity = .localOnly,
        identifier: UUID = UUID()
    ) -> Self {
        Self(kind: .inMemory, workspace: workspace, baseDirectory: nil, identifier: identifier)
    }

    public static func preview(baseDirectory: URL, identifier: UUID = UUID()) -> Self {
        Self(kind: .preview, workspace: .localOnly, baseDirectory: baseDirectory, identifier: identifier)
    }

    public static func temporaryMigration(
        baseDirectory: URL,
        workspace: WorkspaceIdentity,
        identifier: UUID = UUID()
    ) -> Self {
        Self(kind: .temporaryMigration, workspace: workspace, baseDirectory: baseDirectory, identifier: identifier)
    }

    /// An explicitly located shared-schema store used by the Mac legacy
    /// importer and its developer tool. Callers must supply the complete file
    /// URL; there is deliberately no production-path default.
    public static func temporaryMigration(
        storeURL: URL,
        workspace: WorkspaceIdentity = .localOnly,
        identifier: UUID = UUID()
    ) -> Self {
        Self(
            kind: .temporaryMigration,
            workspace: workspace,
            baseDirectory: storeURL.deletingLastPathComponent(),
            identifier: identifier,
            explicitStoreURL: storeURL
        )
    }
}

public struct PendingMutationSnapshot: Codable, Hashable, Sendable {
    public let id: UUID
    public let targetKind: PersistedEntityKind
    public let targetStableID: String
    public let sequence: UInt64
    public let createdAt: Date
    public let attemptCount: UInt64
    public let lastAttemptAt: Date?
    public let supersededBy: UUID?
}

public enum PendingMutationPayload: Hashable, Sendable {
    case note(Note)
    case task(Task)
}

public struct PreparedPendingMutation: Hashable, Sendable {
    public let mutationID: UUID
    public let payload: PendingMutationPayload

    public init(mutationID: UUID, payload: PendingMutationPayload) {
        self.mutationID = mutationID
        self.payload = payload
    }
}

public struct WorkspaceSnapshot: Codable, Hashable, Sendable {
    public let identityKind: String
    public let opaqueWorkspaceID: String?
    public let replicaID: ReplicaID
    public let logicalCounter: UInt64
    public let sharedSchemaVersion: Int
    public let futureSyncEngineState: Data?
}

public enum QuarantinedRecordKind: String, Codable, Hashable, Sendable {
    case note
    case task
    case schemaMarker
    case unknown
}

public enum QuarantineCategory: String, Codable, Hashable, Sendable {
    case malformedIdentifier
    case unsupportedSchema
    case invalidOwnership
    case invalidVersion
    case invalidLifecycle
    case invalidCompletion
    case invalidOrderToken
    case unsupportedRecordType
}

public struct QuarantinedRecordSnapshot: Codable, Hashable, Sendable {
    public let id: UUID
    public let recordKind: QuarantinedRecordKind
    public let opaqueRecordID: String
    public let category: QuarantineCategory
    public let recordSchemaVersion: Int?
    public let quarantinedAt: Date
}
