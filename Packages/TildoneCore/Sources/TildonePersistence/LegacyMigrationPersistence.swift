//
//  LegacyMigrationPersistence.swift
//  Tildone
//
//  Created by OpenAI Codex on 7/13/26.
//
import Foundation
import SwiftData
import TildoneDomain

public extension TildoneRepository {
    static let currentSharedSchemaVersion = 2

    func prepareLegacyMigration(
        formatVersion: Int,
        sourceFingerprint: LegacySourceFingerprint,
        sourceCounts: LegacyMigrationCounts,
        at date: Date
    ) throws -> LegacyMigrationSnapshot {
        guard formatVersion > 0,
              Self.validDigest(sourceFingerprint.identityDigest),
              Self.validDigest(sourceFingerprint.contentDigest),
              sourceFingerprint.fileCount > 0,
              sourceFingerprint.totalByteCount > 0,
              sourceFingerprint.totalByteCount <= UInt64(Int64.max),
              Self.validCounts(sourceCounts),
              date.timeIntervalSinceReferenceDate.isFinite else {
            throw LegacyMigrationPersistenceError.invalidFingerprint
        }
        let context = mutationContext()
        let existing = try context.fetch(FetchDescriptor<LegacyMigrationState>())
        guard existing.count <= 1 else { throw LegacyMigrationPersistenceError.invalidState }
        if let state = existing.first {
            let snapshot = try Self.snapshot(state, mappingCount: try context.fetchCount(FetchDescriptor<LegacyIdentityMapping>()))
            guard snapshot.migrationFormatVersion == formatVersion else {
                throw LegacyMigrationPersistenceError.incompatibleExistingState(.migrationVersionMismatch)
            }
            if snapshot.sourceFingerprint.identityDigest != sourceFingerprint.identityDigest {
                throw LegacyMigrationPersistenceError.incompatibleExistingState(.differentSource)
            }
            if snapshot.sourceFingerprint.contentDigest != sourceFingerprint.contentDigest ||
                snapshot.sourceFingerprint.fileCount != sourceFingerprint.fileCount ||
                snapshot.sourceFingerprint.totalByteCount != sourceFingerprint.totalByteCount ||
                snapshot.sourceCounts != sourceCounts {
                throw LegacyMigrationPersistenceError.incompatibleExistingState(.sourceChanged)
            }
            if snapshot.phase == .failed {
                throw LegacyMigrationPersistenceError.incompatibleExistingState(.priorFailedDestination)
            }
            return snapshot
        }

        let noteCount = try context.fetchCount(FetchDescriptor<StoredNote>())
        let taskCount = try context.fetchCount(FetchDescriptor<StoredTask>())
        let mutationCount = try context.fetchCount(FetchDescriptor<PendingMutation>())
        let mappingCount = try context.fetchCount(FetchDescriptor<LegacyIdentityMapping>())
        guard noteCount == 0, taskCount == 0, mutationCount == 0, mappingCount == 0 else {
            throw LegacyMigrationPersistenceError.destinationNotEmpty
        }
        let metadata = try workspaceMetadata(in: context)
        let replica = try Self.validMigrationReplica(metadata.replicaID)
        context.insert(LegacyMigrationState(
            migrationFormatVersion: formatVersion,
            sourceFingerprint: sourceFingerprint,
            sourceCounts: sourceCounts,
            migrationReplicaID: replica.stringValue,
            now: date
        ))
        try saveMigration(context)
        return try legacyMigrationSnapshot()
    }

    func legacyMigrationSnapshot() throws -> LegacyMigrationSnapshot {
        let context = readContext()
        let rows = try context.fetch(FetchDescriptor<LegacyMigrationState>())
        guard rows.count == 1, let state = rows.first else {
            throw LegacyMigrationPersistenceError.stateMissing
        }
        return try Self.snapshot(
            state,
            mappingCount: try context.fetchCount(FetchDescriptor<LegacyIdentityMapping>())
        )
    }

    /// Makes a completed side-by-side import the authoritative local store.
    /// This is intentionally a narrow, durable transition: callers cannot
    /// activate a partial import, and activation never starts cloud seeding or
    /// changes the retained legacy source/mapping evidence.
    func activateVerifiedLegacyMigration(at date: Date) throws -> LegacyMigrationSnapshot {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw LegacyMigrationPersistenceError.invalidState
        }
        let context = mutationContext()
        let state = try requireMigrationState(in: context)
        guard try Self.phase(state.phaseRawValue) == .eligibleForCutover,
              LegacyMigrationActivationState(rawValue: state.activationStateRawValue) == .verifiedNotActivated,
              !state.cloudSeedingEverBegun else {
            throw LegacyMigrationPersistenceError.invalidState
        }
        state.activationStateRawValue = LegacyMigrationActivationState.activated.rawValue
        state.updatedAt = date
        try refreshMigrationProgress(state, in: context)
        try saveMigration(context)
        return try Self.snapshot(
            state,
            mappingCount: try context.fetchCount(FetchDescriptor<LegacyIdentityMapping>())
        )
    }

    func advanceLegacyMigration(to phase: LegacyMigrationPhase, at date: Date) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw LegacyMigrationPersistenceError.invalidState
        }
        let context = mutationContext()
        let state = try requireMigrationState(in: context)
        let current = try Self.phase(state.phaseRawValue)
        if current == phase { return }
        guard Self.allowedTransition(from: current, to: phase) else {
            throw LegacyMigrationPersistenceError.invalidState
        }
        state.phaseRawValue = phase.rawValue
        state.failureCategoryRawValue = nil
        state.updatedAt = date
        switch phase {
        case .sourceInspected, .destinationPrepared, .copyCompleted, .verified, .eligibleForCutover:
            state.lastCompletedPhaseRawValue = phase.rawValue
        default:
            break
        }
        if phase == .copyCompleted { state.copyCompletedAt = date }
        if phase == .verified {
            state.verifiedAt = date
            state.activationStateRawValue = LegacyMigrationActivationState.verifiedNotActivated.rawValue
        }
        if phase == .eligibleForCutover {
            state.eligibleAt = date
            state.activationStateRawValue = LegacyMigrationActivationState.verifiedNotActivated.rawValue
        }
        guard !state.cloudSeedingEverBegun else {
            throw LegacyMigrationPersistenceError.invalidState
        }
        try refreshMigrationProgress(state, in: context)
        try saveMigration(context)
    }

    func recordLegacyMigrationFailure(
        _ category: LegacyMigrationFailureCategory,
        at date: Date
    ) throws {
        let context = mutationContext()
        let state = try requireMigrationState(in: context)
        state.phaseRawValue = LegacyMigrationPhase.failed.rawValue
        state.failureCategoryRawValue = category.rawValue
        state.updatedAt = date
        try refreshMigrationProgress(state, in: context)
        try saveMigration(context)
    }

    /// Explicit operator action. Failed evidence is retained; no rows are
    /// deleted or replaced. The importer must revalidate the source before it
    /// invokes this method.
    func resumeFailedLegacyMigration(at date: Date) throws {
        let context = mutationContext()
        let state = try requireMigrationState(in: context)
        guard try Self.phase(state.phaseRawValue) == .failed else { return }
        let resumePhase = try Self.phase(state.lastCompletedPhaseRawValue)
        state.phaseRawValue = resumePhase.rawValue
        state.failureCategoryRawValue = nil
        state.updatedAt = date
        try saveMigration(context)
    }

    func prepareLegacyMappings(_ requests: [LegacyMappingRequest], at date: Date) throws -> [LegacyMappingSnapshot] {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw LegacyMigrationPersistenceError.invalidState
        }
        var requestKeys: Set<String> = []
        guard requests.allSatisfy({ Self.validMappingRequest($0) && requestKeys.insert($0.legacyKey).inserted }) else {
            throw LegacyMigrationPersistenceError.invalidMapping("invalid")
        }
        let context = mutationContext()
        let state = try requireMigrationState(in: context)
        let phase = try Self.phase(state.phaseRawValue)
        guard phase == .destinationPrepared || phase == .copyInProgress else {
            throw LegacyMigrationPersistenceError.invalidState
        }
        let metadata = try workspaceMetadata(in: context)
        let replica = try Self.validMigrationReplica(state.migrationReplicaID)
        guard metadata.replicaID == replica.stringValue else {
            throw LegacyMigrationPersistenceError.invalidState
        }

        var results: [LegacyMappingSnapshot] = []
        var allocatedStableIDs = Set(
            try context.fetch(FetchDescriptor<LegacyIdentityMapping>()).compactMap(\.stableID)
        )
        for request in requests {
            let matches = try mappings(legacyKey: request.legacyKey, in: context)
            guard matches.count <= 1 else {
                throw LegacyMigrationPersistenceError.invalidMapping(request.legacyKey)
            }
            if let existing = matches.first {
                let snapshot = try Self.mappingSnapshot(existing)
                guard snapshot.entityKind == request.entityKind,
                      snapshot.classification == request.classification,
                      snapshot.ownerLegacyKey == request.ownerLegacyKey,
                      snapshot.visibleOrder == request.visibleOrder else {
                    throw LegacyMigrationPersistenceError.invalidMapping(request.legacyKey)
                }
                results.append(snapshot)
                continue
            }

            let imported = request.classification == .userContent
            let versionCount = imported ? (request.entityKind == .note ? 3 : 4) : 0
            var firstCounter: Int64?
            var stableID: String?
            if imported {
                guard metadata.logicalCounter <= Int64.max - Int64(versionCount) else {
                    throw PersistenceError.counterOverflow
                }
                firstCounter = metadata.logicalCounter + 1
                metadata.logicalCounter += Int64(versionCount)
                repeat {
                    stableID = request.entityKind == .note ? NoteID().stringValue : TaskID().stringValue
                } while allocatedStableIDs.contains(stableID!)
                allocatedStableIDs.insert(stableID!)
            }
            let row = LegacyIdentityMapping(
                legacyKey: request.legacyKey,
                entityKindRawValue: request.entityKind.rawValue,
                classificationRawValue: request.classification.rawValue,
                stableID: stableID,
                ownerLegacyKey: request.ownerLegacyKey,
                visibleOrder: request.visibleOrder,
                firstVersionCounter: firstCounter,
                versionCount: versionCount
            )
            context.insert(row)
            results.append(try Self.mappingSnapshot(row))
        }
        state.phaseRawValue = LegacyMigrationPhase.copyInProgress.rawValue
        state.updatedAt = date
        state.logicalCounterProgress = metadata.logicalCounter
        try saveMigration(context)
        return results
    }

    func legacyMapping(for legacyKey: String) throws -> LegacyMappingSnapshot {
        let context = readContext()
        let rows = try mappings(legacyKey: legacyKey, in: context)
        guard rows.count == 1, let row = rows.first else {
            throw LegacyMigrationPersistenceError.missingMapping(legacyKey)
        }
        return try Self.mappingSnapshot(row)
    }

    func importLegacyNotes(_ imports: [LegacyImportedNote], at date: Date) throws {
        let context = mutationContext()
        let state = try requireCopyState(in: context)
        let replica = try Self.validMigrationReplica(state.migrationReplicaID)
        for imported in imports {
            guard imported.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  imported.lastMeaningfulEditAt.timeIntervalSinceReferenceDate.isFinite else {
                throw LegacyMigrationPersistenceError.importedValueMismatch(imported.legacyKey)
            }
            let mapping = try requireUserMapping(imported.legacyKey, kind: .note, in: context)
            guard let stableID = mapping.stableID,
                  let noteID = NoteID(string: stableID),
                  let first = mapping.firstVersionCounter,
                  mapping.versionCount == 3 else {
                throw LegacyMigrationPersistenceError.invalidMapping(imported.legacyKey)
            }
            let note = Note(
                id: noteID,
                createdAt: imported.createdAt,
                title: imported.title,
                titleVersion: VersionStamp(logicalCounter: first, replicaID: replica),
                lifecycle: .active,
                lifecycleVersion: VersionStamp(logicalCounter: first + 1, replicaID: replica),
                lastMeaningfulEditAt: imported.lastMeaningfulEditAt,
                lastMeaningfulEditVersion: VersionStamp(logicalCounter: first + 2, replicaID: replica)
            )
            let existing = try storedNotes(stableID: stableID, in: context)
            guard existing.count <= 1 else { throw PersistenceError.duplicateID(.note, stableID) }
            if let existing = existing.first {
                guard try StoredDomainMapping.note(from: existing) == note else {
                    throw LegacyMigrationPersistenceError.importedValueMismatch(imported.legacyKey)
                }
            } else {
                context.insert(try StoredDomainMapping.storedNote(from: note))
            }
        }
        state.updatedAt = date
        try refreshMigrationProgress(state, in: context)
        try saveMigration(context)
    }

    func importLegacyTasks(_ imports: [LegacyImportedTask], at date: Date) throws {
        let context = mutationContext()
        let state = try requireCopyState(in: context)
        let replica = try Self.validMigrationReplica(state.migrationReplicaID)
        for imported in imports {
            guard imported.createdAt.timeIntervalSinceReferenceDate.isFinite,
                  imported.completedAt?.timeIntervalSinceReferenceDate.isFinite != false else {
                throw LegacyMigrationPersistenceError.importedValueMismatch(imported.legacyKey)
            }
            let mapping = try requireUserMapping(imported.legacyKey, kind: .task, in: context)
            let ownerMapping = try requireUserMapping(imported.ownerLegacyKey, kind: .note, in: context)
            guard mapping.ownerLegacyKey == imported.ownerLegacyKey,
                  let stableID = mapping.stableID,
                  let taskID = TaskID(string: stableID),
                  let ownerIDString = ownerMapping.stableID,
                  let ownerID = NoteID(string: ownerIDString),
                  let first = mapping.firstVersionCounter,
                  mapping.versionCount == 4 else {
                throw LegacyMigrationPersistenceError.invalidMapping(imported.legacyKey)
            }
            guard try storedNotes(stableID: ownerIDString, in: context).count == 1 else {
                throw LegacyMigrationPersistenceError.importedValueMismatch(imported.ownerLegacyKey)
            }
            let completion: CompletionState = imported.completedAt.map(CompletionState.completed) ?? .incomplete
            let task = Task(
                id: taskID,
                noteID: ownerID,
                createdAt: imported.createdAt,
                text: imported.text,
                textVersion: VersionStamp(logicalCounter: first, replicaID: replica),
                completion: completion,
                completionVersion: VersionStamp(logicalCounter: first + 1, replicaID: replica),
                orderToken: imported.orderToken,
                orderVersion: VersionStamp(logicalCounter: first + 2, replicaID: replica),
                lifecycle: .active,
                lifecycleVersion: VersionStamp(logicalCounter: first + 3, replicaID: replica)
            )
            let existing = try storedTasks(stableID: stableID, in: context)
            guard existing.count <= 1 else { throw PersistenceError.duplicateID(.task, stableID) }
            if let existing = existing.first {
                guard try StoredDomainMapping.task(from: existing) == task else {
                    throw LegacyMigrationPersistenceError.importedValueMismatch(imported.legacyKey)
                }
            } else {
                context.insert(try StoredDomainMapping.storedTask(from: task))
            }
        }
        state.updatedAt = date
        try refreshMigrationProgress(state, in: context)
        try saveMigration(context)
    }

    func legacyMigrationAudit() throws -> LegacyMigrationAudit {
        let context = readContext()
        let notes = try context.fetch(FetchDescriptor<StoredNote>())
        let tasks = try context.fetch(FetchDescriptor<StoredTask>())
        let mappings = try context.fetch(FetchDescriptor<LegacyIdentityMapping>())
        let pendingCount = try context.fetchCount(FetchDescriptor<PendingMutation>())
        let metadata = try workspaceMetadata(in: context)
        let mappedIDs = mappings.compactMap(\.stableID)
        return LegacyMigrationAudit(
            noteCount: notes.count,
            taskCount: tasks.count,
            mappingCount: mappings.count,
            pendingMutationCount: pendingCount,
            duplicateNoteIDs: Set(notes.map(\.stableID)).count != notes.count,
            duplicateTaskIDs: Set(tasks.map(\.stableID)).count != tasks.count,
            duplicateMappedStableIDs: Set(mappedIDs).count != mappedIDs.count,
            destinationSchemaVersion: metadata.sharedSchemaVersion
        )
    }
}

private extension TildoneRepository {
    static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) ||
                (UInt8(ascii: "a")...UInt8(ascii: "f")).contains($0)
        }
    }

    static func validCounts(_ counts: LegacyMigrationCounts) -> Bool {
        [
            counts.eligibleNotes, counts.eligibleTasks, counts.excludedSystemNotes,
            counts.excludedSystemTasks, counts.excludedTransientTasks
        ].allSatisfy { $0 >= 0 }
    }

    static func validMappingRequest(_ request: LegacyMappingRequest) -> Bool {
        guard validDigest(request.legacyKey) else { return false }
        switch (request.entityKind, request.classification) {
        case (.note, .userContent), (.note, .excludedSystemNote):
            return request.ownerLegacyKey == nil && request.visibleOrder == nil
        case (.task, .userContent), (.task, .excludedSystemTask), (.task, .excludedTransientEmptyTask):
            return request.ownerLegacyKey.map(validDigest) == true && request.visibleOrder.map { $0 >= 0 } == true
        default:
            return false
        }
    }

    static func validMigrationReplica(_ value: String) throws -> ReplicaID {
        guard let replica = ReplicaID(string: value), replica.stringValue == value else {
            throw LegacyMigrationPersistenceError.invalidState
        }
        return replica
    }

    static func phase(_ rawValue: String) throws -> LegacyMigrationPhase {
        guard let phase = LegacyMigrationPhase(rawValue: rawValue) else {
            throw LegacyMigrationPersistenceError.invalidState
        }
        return phase
    }

    static func allowedTransition(from: LegacyMigrationPhase, to: LegacyMigrationPhase) -> Bool {
        switch (from, to) {
        case (.notStarted, .sourceInspected),
             (.sourceInspected, .destinationPrepared),
             (.destinationPrepared, .copyInProgress),
             (.copyInProgress, .copyCompleted),
             (.copyCompleted, .verificationInProgress),
             (.verificationInProgress, .verified),
             (.verified, .eligibleForCutover): true
        default: false
        }
    }

    static func snapshot(_ state: LegacyMigrationState, mappingCount: Int) throws -> LegacyMigrationSnapshot {
        guard state.singletonKey == "legacy-migration",
              state.migrationFormatVersion > 0,
              validDigest(state.sourceIdentityDigest), validDigest(state.sourceContentDigest),
              state.sourceFileCount > 0, state.sourceTotalByteCount > 0,
              state.destinationSchemaVersion == currentSharedSchemaVersion,
              state.logicalCounterProgress >= 0,
              state.startedAt.timeIntervalSinceReferenceDate.isFinite,
              state.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              state.copyCompletedAt?.timeIntervalSinceReferenceDate.isFinite != false,
              state.verifiedAt?.timeIntervalSinceReferenceDate.isFinite != false,
              state.eligibleAt?.timeIntervalSinceReferenceDate.isFinite != false,
              let activation = LegacyMigrationActivationState(rawValue: state.activationStateRawValue) else {
            throw LegacyMigrationPersistenceError.invalidState
        }
        let currentPhase = try phase(state.phaseRawValue)
        let lastCompleted = try phase(state.lastCompletedPhaseRawValue)
        // Cloud seeding is an irreversible but valid post-activation state. It
        // must not make a verified local migration unreadable on subsequent
        // launches; it only rules out rolling that destination back.
        if state.cloudSeedingEverBegun {
            guard currentPhase == .eligibleForCutover, activation == .activated else {
                throw LegacyMigrationPersistenceError.invalidState
            }
        }
        let failure = try state.failureCategoryRawValue.map {
            guard let value = LegacyMigrationFailureCategory(rawValue: $0) else {
                throw LegacyMigrationPersistenceError.invalidState
            }
            return value
        }
        let replica = try validMigrationReplica(state.migrationReplicaID)
        return LegacyMigrationSnapshot(
            migrationFormatVersion: state.migrationFormatVersion,
            phase: currentPhase,
            lastCompletedPhase: lastCompleted,
            failureCategory: failure,
            sourceFingerprint: LegacySourceFingerprint(
                identityDigest: state.sourceIdentityDigest,
                contentDigest: state.sourceContentDigest,
                fileCount: state.sourceFileCount,
                totalByteCount: UInt64(state.sourceTotalByteCount)
            ),
            destinationSchemaVersion: state.destinationSchemaVersion,
            sourceCounts: LegacyMigrationCounts(
                eligibleNotes: state.sourceEligibleNoteCount,
                eligibleTasks: state.sourceEligibleTaskCount,
                excludedSystemNotes: state.sourceSystemNoteCount,
                excludedSystemTasks: state.sourceSystemTaskCount,
                excludedTransientTasks: state.sourceTransientTaskCount
            ),
            destinationNoteCount: state.destinationNoteCount,
            destinationTaskCount: state.destinationTaskCount,
            mappingCount: mappingCount,
            migrationReplicaID: replica,
            logicalCounterProgress: UInt64(state.logicalCounterProgress),
            startedAt: state.startedAt,
            updatedAt: state.updatedAt,
            copyCompletedAt: state.copyCompletedAt,
            verifiedAt: state.verifiedAt,
            eligibleAt: state.eligibleAt,
            activationState: activation,
            cloudSeedingEverBegun: state.cloudSeedingEverBegun
        )
    }

    static func mappingSnapshot(_ row: LegacyIdentityMapping) throws -> LegacyMappingSnapshot {
        guard validDigest(row.legacyKey),
              let kind = LegacyMigrationEntityKind(rawValue: row.entityKindRawValue),
              let classification = LegacyMigrationClassification(rawValue: row.classificationRawValue),
              row.ownerLegacyKey.map(validDigest) != false,
              row.visibleOrder.map({ $0 >= 0 }) != false,
              row.versionCount >= 0 else {
            throw LegacyMigrationPersistenceError.invalidMapping("invalid")
        }
        if classification == .userContent {
            guard let stableID = row.stableID, let first = row.firstVersionCounter, first > 0,
                  (kind == .note
                    ? NoteID(string: stableID)?.stringValue == stableID
                    : TaskID(string: stableID)?.stringValue == stableID),
                  row.versionCount == (kind == .note ? 3 : 4) else {
                throw LegacyMigrationPersistenceError.invalidMapping(row.legacyKey)
            }
        } else if row.stableID != nil || row.firstVersionCounter != nil || row.versionCount != 0 {
            throw LegacyMigrationPersistenceError.invalidMapping(row.legacyKey)
        }
        return LegacyMappingSnapshot(
            legacyKey: row.legacyKey,
            entityKind: kind,
            classification: classification,
            stableID: row.stableID,
            ownerLegacyKey: row.ownerLegacyKey,
            visibleOrder: row.visibleOrder,
            firstVersionCounter: row.firstVersionCounter.map(UInt64.init),
            versionCount: row.versionCount
        )
    }

    func requireMigrationState(in context: ModelContext) throws -> LegacyMigrationState {
        let rows = try context.fetch(FetchDescriptor<LegacyMigrationState>())
        guard rows.count == 1, let state = rows.first else {
            throw LegacyMigrationPersistenceError.stateMissing
        }
        _ = try Self.snapshot(
            state,
            mappingCount: try context.fetchCount(FetchDescriptor<LegacyIdentityMapping>())
        )
        return state
    }

    func requireCopyState(in context: ModelContext) throws -> LegacyMigrationState {
        let state = try requireMigrationState(in: context)
        guard try Self.phase(state.phaseRawValue) == .copyInProgress else {
            throw LegacyMigrationPersistenceError.invalidState
        }
        return state
    }

    func mappings(legacyKey: String, in context: ModelContext) throws -> [LegacyIdentityMapping] {
        try context.fetch(FetchDescriptor<LegacyIdentityMapping>(
            predicate: #Predicate { $0.legacyKey == legacyKey }
        ))
    }

    func requireUserMapping(
        _ legacyKey: String,
        kind: LegacyMigrationEntityKind,
        in context: ModelContext
    ) throws -> LegacyMappingSnapshot {
        let rows = try mappings(legacyKey: legacyKey, in: context)
        guard rows.count == 1, let row = rows.first else {
            throw LegacyMigrationPersistenceError.missingMapping(legacyKey)
        }
        let mapping = try Self.mappingSnapshot(row)
        guard mapping.entityKind == kind, mapping.classification == .userContent else {
            throw LegacyMigrationPersistenceError.invalidMapping(legacyKey)
        }
        return mapping
    }

    func storedNotes(stableID: String, in context: ModelContext) throws -> [StoredNote] {
        try context.fetch(FetchDescriptor<StoredNote>(predicate: #Predicate { $0.stableID == stableID }))
    }

    func storedTasks(stableID: String, in context: ModelContext) throws -> [StoredTask] {
        try context.fetch(FetchDescriptor<StoredTask>(predicate: #Predicate { $0.stableID == stableID }))
    }

    func refreshMigrationProgress(_ state: LegacyMigrationState, in context: ModelContext) throws {
        state.destinationNoteCount = try context.fetchCount(FetchDescriptor<StoredNote>())
        state.destinationTaskCount = try context.fetchCount(FetchDescriptor<StoredTask>())
        state.logicalCounterProgress = try workspaceMetadata(in: context).logicalCounter
    }

    func saveMigration(_ context: ModelContext) throws {
        do { try save(context) }
        catch { throw LegacyMigrationPersistenceError.saveFailure }
    }
}

#if DEBUG
public enum LegacyMigrationCorruptionField: Sendable {
    case noteTitle
    case taskText
    case taskOwnership
    case taskCompletion
    case taskOrderToken
    case taskOrderVersion
    case mappingStableID
    case taskCount
    case taskVersion
    case systemClassification
}

public extension TildoneRepository {
    /// Debug-only destructive probe for verification tests. It is unavailable
    /// to Release builds and cannot resolve a store path on its own.
    func corruptLegacyMigrationDestinationForTesting(_ field: LegacyMigrationCorruptionField) throws {
        let context = mutationContext()
        let notes = try context.fetch(FetchDescriptor<StoredNote>())
        let tasks = try context.fetch(FetchDescriptor<StoredTask>())
        let mappings = try context.fetch(FetchDescriptor<LegacyIdentityMapping>())
        switch field {
        case .noteTitle:
            guard let note = notes.first else { throw LegacyMigrationPersistenceError.invalidState }
            note.title = "corrupted"
        case .taskText:
            guard let task = tasks.first else { throw LegacyMigrationPersistenceError.invalidState }
            task.text = "corrupted"
        case .taskOwnership:
            guard let task = tasks.first else { throw LegacyMigrationPersistenceError.invalidState }
            task.noteStableID = NoteID().stringValue
        case .taskCompletion:
            guard let task = tasks.first else { throw LegacyMigrationPersistenceError.invalidState }
            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? Date(timeIntervalSince1970: 123) : nil
        case .taskOrderToken:
            guard let task = tasks.first else { throw LegacyMigrationPersistenceError.invalidState }
            task.orderTokenRawValue = "z"
        case .taskOrderVersion:
            guard let task = tasks.first else { throw LegacyMigrationPersistenceError.invalidState }
            task.orderVersionCounter += 1
            let metadata = try workspaceMetadata(in: context)
            metadata.logicalCounter = max(metadata.logicalCounter, task.orderVersionCounter)
        case .mappingStableID:
            guard let mapping = mappings.first(where: { $0.stableID != nil }) else {
                throw LegacyMigrationPersistenceError.invalidState
            }
            mapping.stableID = mapping.entityKindRawValue == LegacyMigrationEntityKind.note.rawValue
                ? NoteID().stringValue : TaskID().stringValue
        case .taskCount:
            guard let task = tasks.first else { throw LegacyMigrationPersistenceError.invalidState }
            context.delete(task)
        case .taskVersion:
            guard let task = tasks.first else { throw LegacyMigrationPersistenceError.invalidState }
            task.textVersionCounter += 1
            let metadata = try workspaceMetadata(in: context)
            metadata.logicalCounter = max(metadata.logicalCounter, task.textVersionCounter)
        case .systemClassification:
            guard let mapping = mappings.first(where: {
                $0.classificationRawValue == LegacyMigrationClassification.excludedSystemNote.rawValue
            }) else { throw LegacyMigrationPersistenceError.invalidState }
            mapping.classificationRawValue = LegacyMigrationClassification.userContent.rawValue
            mapping.stableID = NoteID().stringValue
            let metadata = try workspaceMetadata(in: context)
            mapping.firstVersionCounter = metadata.logicalCounter + 1
            mapping.versionCount = 3
            metadata.logicalCounter += 3
        }
        try context.save()
    }
}
#endif
