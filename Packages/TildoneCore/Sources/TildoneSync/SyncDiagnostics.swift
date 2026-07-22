//
//  SyncDiagnostics.swift
//  Tildone
//
import Foundation
import TildonePersistence

#if DEBUG
import OSLog
#endif

enum SyncAccountChangeDiagnosticCategory: String {
    case signedIn = "signed-in"
    case signedOut = "signed-out"
    case switched
}

enum SyncFailureDiagnosticCategory: Equatable {
    case cloud(Int)
    case nonCloudNonPersistence
    case persistenceOpen
    case persistenceSave
    case persistenceMissing
    case persistenceMissingMutation
    case persistenceDuplicate
    case persistenceOwnership
    case persistenceMalformed
    case persistenceDomain
    case persistenceSchema
    case persistenceWorkspace
    case persistenceInUse
    case persistenceInvalidWorkspace
    case persistenceLocation
    case persistenceQuarantine
    case persistenceAtomic
    case persistenceCounter

    static func classify(_ error: Error) -> Self {
        guard let error = error as? PersistenceError else {
            return .nonCloudNonPersistence
        }
        return switch error {
        case .openFailure: .persistenceOpen
        case .saveFailure: .persistenceSave
        case .missing: .persistenceMissing
        case .missingPendingMutation: .persistenceMissingMutation
        case .duplicateID: .persistenceDuplicate
        case .ownershipMismatch: .persistenceOwnership
        case .malformedRepresentation: .persistenceMalformed
        case .domainInvariant: .persistenceDomain
        case .unsupportedRecordSchema: .persistenceSchema
        case .workspaceMismatch: .persistenceWorkspace
        case .workspaceInUse: .persistenceInUse
        case .invalidWorkspace: .persistenceInvalidWorkspace
        case .invalidStoreLocation: .persistenceLocation
        case .invalidQuarantineMetadata: .persistenceQuarantine
        case .atomicMutationFailure: .persistenceAtomic
        case .counterOverflow: .persistenceCounter
        }
    }

    var label: String {
        switch self {
        case let .cloud(code): "cloud-\(code)"
        case .nonCloudNonPersistence: "non-cloud-non-persistence"
        case .persistenceOpen: "persistence-open"
        case .persistenceSave: "persistence-save"
        case .persistenceMissing: "persistence-missing"
        case .persistenceMissingMutation: "persistence-missing-mutation"
        case .persistenceDuplicate: "persistence-duplicate"
        case .persistenceOwnership: "persistence-ownership"
        case .persistenceMalformed: "persistence-malformed"
        case .persistenceDomain: "persistence-domain"
        case .persistenceSchema: "persistence-schema"
        case .persistenceWorkspace: "persistence-workspace"
        case .persistenceInUse: "persistence-in-use"
        case .persistenceInvalidWorkspace: "persistence-invalid-workspace"
        case .persistenceLocation: "persistence-location"
        case .persistenceQuarantine: "persistence-quarantine"
        case .persistenceAtomic: "persistence-atomic"
        case .persistenceCounter: "persistence-counter"
        }
    }
}

/// Debug-only, content-free synchronization breadcrumbs for device validation.
///
/// Messages intentionally contain only lifecycle categories and aggregate
/// counts. Record identifiers, account identifiers, titles, and task text are
/// never accepted by this API.
enum SyncDiagnostics {
#if DEBUG
    private static let logger = Logger(
        subsystem: "studio.cuatro.tildone",
        category: "CloudKitSync"
    )
#endif

    static func checkpointStarted(pendingCount: Int) {
#if DEBUG
        logger.debug("checkpoint-started pending=\(pendingCount, privacy: .public)")
#endif
    }

    static func fetched(modificationCount: Int, deletionCount: Int) {
#if DEBUG
        logger.debug(
            "fetched-records modifications=\(modificationCount, privacy: .public) deletions=\(deletionCount, privacy: .public)"
        )
#endif
    }

    static func sent(savedCount: Int, failedCount: Int) {
#if DEBUG
        logger.debug(
            "sent-records saved=\(savedCount, privacy: .public) failed=\(failedCount, privacy: .public)"
        )
#endif
    }

    static func accountChanged(category: SyncAccountChangeDiagnosticCategory) {
#if DEBUG
        logger.notice("account-change category=\(category.rawValue, privacy: .public)")
#endif
    }

    static func statusChanged(_ status: SyncStatus) {
#if DEBUG
        logger.debug(
            "status availability=\(status.availability.rawValue, privacy: .public) activity=\(status.activity.rawValue, privacy: .public) pending=\(status.pendingMutationCount, privacy: .public) issue=\(status.issue?.rawValue ?? "none", privacy: .public)"
        )
#endif
    }

    static func failed(category: SyncFailureDiagnosticCategory) {
#if DEBUG
        logger.error("sync-failure category=\(category.label, privacy: .public)")
#endif
    }

    static func quarantined(category: QuarantineCategory) {
#if DEBUG
        logger.error("quarantined-record category=\(category.rawValue, privacy: .public)")
#endif
    }
}
