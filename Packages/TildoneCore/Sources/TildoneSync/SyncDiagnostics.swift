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

enum SyncCheckpointPhase: String {
    case fetch
    case send
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
public enum SyncDiagnostics {
    public enum QualificationPhase: String {
        case checkpoint
        case fetched
        case sent
        case paused
        case pausedLaunch = "paused-launch"
        case pausedMutation = "paused-mutation"
    }

    public static func inspectQualificationState(
        in repository: TildoneRepository, phase: QualificationPhase
    ) async {
#if DEBUG
        await SyncQualificationAudit.inspect(in: repository, phase: phase)
#endif
    }

    public enum Boundary: String {
        case refreshFailureInjected = "refresh-failure-injected"
        case scheduled
        case prepared
        case acknowledged
        case merged
        case presented
        case fetchStarted = "fetch-started"
        case sendStarted = "send-started"
        case zoneFetchStarted = "zone-fetch-started"
        case zoneSendCompleted = "zone-send-completed"
        case engineCreated = "engine-created"
        case automaticSchedulingEnabled = "automatic-scheduling-enabled"
        case pauseCompleted = "pause-completed"
        case noteFocusCheckpointRequested = "note-focus-checkpoint-requested"
        case appActivationCheckpointRequested = "app-activation-checkpoint-requested"
        case appResignedActive = "app-resigned-active"
        case macActiveAtCoordinatorStart = "mac-active-at-coordinator-start"
        case explicitCheckpointRequested = "explicit-checkpoint-requested"
        case resumeRequested = "resume-requested"
        case fetchReasonManual = "fetch-reason-manual"
        case fetchReasonScheduled = "fetch-reason-scheduled"
        case fetchReasonUnknown = "fetch-reason-unknown"
        case unfetchedZoneCount = "unfetched-zone-count"
        case fetchedDatabaseModificationCount = "fetched-database-modification-count"
        case fetchedDatabaseDeletionCount = "fetched-database-deletion-count"
        case fixtureNoteStored = "fixture-note-stored"
        case fixtureTaskStored = "fixture-task-stored"
        case fixtureTaskVisible = "fixture-task-visible"
        case fixtureTaskPending = "fixture-task-pending"
        case fixtureTaskAttempted = "fixture-task-attempted"
        case fixtureTaskSystemFields = "fixture-task-system-fields"
        case fixtureTaskPresented = "fixture-task-presented"
        case fixtureInspectionFailed = "fixture-inspection-failed"
        case qualificationInspectionFailed = "qualification-inspection-failed"
    }

    /// Counts and fixed categories only. This deliberately cannot accept record
    /// names, workspace IDs, payloads, or error descriptions.
    public static func boundary(_ boundary: Boundary, count: Int) {
#if DEBUG
        logger.debug("sync-boundary stage=\(boundary.rawValue, privacy: .public) count=\(count, privacy: .public)")
        if ProcessInfo.processInfo.arguments.contains("--inspect-retained-qualification-fixture") ||
            ProcessInfo.processInfo.arguments.contains("--inspect-stage12-synthetic-state") {
            // The explicitly requested device console receives the same
            // content-free breadcrumb, without broad OS activity logging.
            print("TildoneQualification stage=\(boundary.rawValue) count=\(count)")
        }
#endif
    }

    /// Read-only inspection of the previously labelled synthetic fixture. No
    /// record IDs or content leave this method; it never creates or repairs it.
    /// The opt-in launch argument is inert in Release.
    public static func inspectRetainedFixture(in repository: TildoneRepository) async {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--inspect-retained-qualification-fixture") else { return }
        do {
            let notes = try await repository.allSyncNotes().filter { $0.title == "Stage12 Device Check" }
            let noteIDs = Set(notes.map(\.id))
            let visibleNoteIDs = Set(notes.filter { $0.lifecycle == .active }.map(\.id))
            let tasks = try await repository.allSyncTasks().filter {
                noteIDs.contains($0.noteID) && $0.text == "Paused count repair"
            }
            let taskIDs = Set(tasks.map { $0.id.stringValue })
            let pending = try await repository.pendingMutations(includeSuperseded: true).filter {
                taskIDs.contains($0.targetStableID)
            }
            let state = SyncPersistentState(data: try await repository.workspaceSnapshot().futureSyncEngineState)
            boundary(.fixtureNoteStored, count: notes.count)
            boundary(.fixtureTaskStored, count: tasks.count)
            boundary(.fixtureTaskVisible, count: tasks.filter {
                $0.lifecycle == .active && visibleNoteIDs.contains($0.noteID)
            }.count)
            boundary(.fixtureTaskPending, count: pending.count)
            boundary(.fixtureTaskAttempted, count: pending.filter { $0.attemptCount > 0 }.count)
            boundary(.fixtureTaskSystemFields, count: tasks.filter {
                state.systemRecord(named: $0.id.recordName) != nil
            }.count)
        } catch {
            boundary(.fixtureInspectionFailed, count: 1)
        }
#endif
    }

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

    static func phaseStarted(_ phase: SyncCheckpointPhase) {
#if DEBUG
        logger.debug("checkpoint-phase-started phase=\(phase.rawValue, privacy: .public)")
#endif
    }

    static func phaseCompleted(
        _ phase: SyncCheckpointPhase,
        elapsedSeconds: TimeInterval
    ) {
#if DEBUG
        logger.debug(
            "checkpoint-phase-completed phase=\(phase.rawValue, privacy: .public) elapsed-seconds=\(elapsedSeconds, privacy: .public)"
        )
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
