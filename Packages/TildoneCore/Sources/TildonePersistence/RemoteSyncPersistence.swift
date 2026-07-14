//
//  RemoteSyncPersistence.swift
//  Tildone
//
//  Transport-neutral persistence operations used by TildoneSync.
//
import Foundation
import SwiftData
import TildoneDomain

public struct RemoteMergeResult: Hashable, Sendable {
    public let changed: Bool
    public let generatedTombstoneMutationCount: Int

    public init(changed: Bool, generatedTombstoneMutationCount: Int) {
        self.changed = changed
        self.generatedTombstoneMutationCount = generatedTombstoneMutationCount
    }
}

public extension TildoneRepository {
    /// Returns every syncable note, including lifecycle tombstones.
    func allSyncNotes() throws -> [Note] {
        try readContext().fetch(FetchDescriptor<StoredNote>()).map {
            try StoredDomainMapping.note(from: $0)
        }.sorted { $0.id < $1.id }
    }

    /// Returns every syncable task, including lifecycle tombstones and valid
    /// orphans whose parent has not arrived yet.
    func allSyncTasks() throws -> [Task] {
        try readContext().fetch(FetchDescriptor<StoredTask>()).map {
            try StoredDomainMapping.task(from: $0)
        }.sorted { $0.id < $1.id }
    }

    func hasSyncContent() throws -> Bool {
        let context = readContext()
        return try context.fetchCount(FetchDescriptor<StoredNote>()) > 0 ||
            context.fetchCount(FetchDescriptor<StoredTask>()) > 0
    }

    /// Applies one remote note without creating echo work. If the winning note
    /// is deleted, active children are tombstoned locally and those new child
    /// tombstones are queued so every replica eventually observes them.
    func mergeRemoteNote(_ remote: Note, at date: Date) throws -> RemoteMergeResult {
        guard remote.schemaVersion == Note.currentSchemaVersion,
              date.timeIntervalSinceReferenceDate.isFinite else {
            throw PersistenceError.unsupportedRecordSchema(.note, remote.schemaVersion)
        }
        let context = mutationContext()
        let metadata = try workspaceMetadata(in: context)
        try observeRemoteVersions(in: remote, metadata: metadata)
        let id = remote.id.stringValue
        let rows = try context.fetch(FetchDescriptor<StoredNote>(
            predicate: #Predicate { $0.stableID == id }
        ))
        guard rows.count <= 1 else { throw PersistenceError.duplicateID(.note, id) }

        let merged: Note
        let changed: Bool
        if let row = rows.first {
            let local = try StoredDomainMapping.note(from: row)
            do { merged = try local.merged(with: remote) }
            catch { throw PersistenceError.domainInvariant }
            changed = merged != local
            if changed { try StoredDomainMapping.update(row, from: merged) }
        } else {
            merged = remote
            changed = true
            context.insert(try StoredDomainMapping.storedNote(from: remote))
        }

        var generated = 0
        if merged.lifecycle == .deleted {
            let noteID = merged.id.stringValue
            let children = try context.fetch(FetchDescriptor<StoredTask>(
                predicate: #Predicate { $0.noteStableID == noteID }
            ))
            for child in children {
                var task = try StoredDomainMapping.task(from: child, expectedNoteID: merged.id)
                guard task.lifecycle == .active else { continue }
                let stamp = try nextRemoteNormalizationStamp(metadata, observing: maxVersion(in: task))
                do { try task.delete(version: stamp) }
                catch { throw PersistenceError.domainInvariant }
                try StoredDomainMapping.update(child, from: task)
                try enqueueSyncMutation(.task, stableID: task.id.stringValue, sequence: stamp.logicalCounter, at: date, in: context)
                generated += 1
            }
        }
        try save(context)
        return RemoteMergeResult(changed: changed || generated > 0, generatedTombstoneMutationCount: generated)
    }

    /// Applies one remote task without echoing ordinary field changes. A task
    /// delivered after its parent tombstone is normalized into a newer local
    /// tombstone and queued, preventing stale child resurrection.
    func mergeRemoteTask(_ remote: Task, at date: Date) throws -> RemoteMergeResult {
        guard remote.schemaVersion == Task.currentSchemaVersion,
              date.timeIntervalSinceReferenceDate.isFinite else {
            throw PersistenceError.unsupportedRecordSchema(.task, remote.schemaVersion)
        }
        let context = mutationContext()
        let metadata = try workspaceMetadata(in: context)
        try observeRemoteVersions(in: remote, metadata: metadata)
        let id = remote.id.stringValue
        let rows = try context.fetch(FetchDescriptor<StoredTask>(
            predicate: #Predicate { $0.stableID == id }
        ))
        guard rows.count <= 1 else { throw PersistenceError.duplicateID(.task, id) }

        var merged: Task
        var changed: Bool
        if let row = rows.first {
            let local = try StoredDomainMapping.task(from: row)
            do { merged = try local.merged(with: remote) }
            catch { throw PersistenceError.domainInvariant }
            changed = merged != local
            if changed { try StoredDomainMapping.update(row, from: merged) }
        } else {
            merged = remote
            changed = true
            context.insert(try StoredDomainMapping.storedTask(from: remote))
        }

        var generated = 0
        let noteID = merged.noteID.stringValue
        let parents = try context.fetch(FetchDescriptor<StoredNote>(
            predicate: #Predicate { $0.stableID == noteID }
        ))
        guard parents.count <= 1 else { throw PersistenceError.duplicateID(.note, noteID) }
        if let parent = parents.first,
           try StoredDomainMapping.note(from: parent).lifecycle == .deleted,
           merged.lifecycle == .active {
            let stamp = try nextRemoteNormalizationStamp(metadata, observing: maxVersion(in: merged))
            do { try merged.delete(version: stamp) }
            catch { throw PersistenceError.domainInvariant }
            guard let stored = try context.fetch(FetchDescriptor<StoredTask>(
                predicate: #Predicate { $0.stableID == id }
            )).first else { throw PersistenceError.missing(.task, id) }
            try StoredDomainMapping.update(stored, from: merged)
            try enqueueSyncMutation(.task, stableID: id, sequence: stamp.logicalCounter, at: date, in: context)
            generated = 1
            changed = true
        }
        try save(context)
        return RemoteMergeResult(changed: changed, generatedTombstoneMutationCount: generated)
    }

    /// Explicit adoption/seeding operation. It is intentionally separate from
    /// repository construction so a local-only workspace is never uploaded just
    /// because an iCloud account becomes available.
    func enqueueAllSyncContent(at date: Date) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw PersistenceError.domainInvariant
        }
        let context = mutationContext()
        let metadata = try workspaceMetadata(in: context)
        for note in try context.fetch(FetchDescriptor<StoredNote>()) {
            let domain = try StoredDomainMapping.note(from: note)
            let sequence = maxVersion(in: domain).logicalCounter
            try enqueueSyncMutation(.note, stableID: domain.id.stringValue, sequence: sequence, at: date, in: context)
        }
        for task in try context.fetch(FetchDescriptor<StoredTask>()) {
            let domain = try StoredDomainMapping.task(from: task)
            let sequence = maxVersion(in: domain).logicalCounter
            try enqueueSyncMutation(.task, stableID: domain.id.stringValue, sequence: sequence, at: date, in: context)
        }
        _ = metadata
        try save(context)
    }

    /// Deterministically merges exact domain values into an account workspace
    /// and queues a stable-ID seed. This is safe to retry after interruption,
    /// but callers must still gate it behind explicit adoption approval.
    func adoptSyncContent(notes: [Note], tasks: [Task], at date: Date) throws {
        let snapshot = try workspaceSnapshot()
        guard snapshot.identityKind == "account" else {
            throw PersistenceError.workspaceMismatch
        }
        for note in notes { _ = try mergeRemoteNote(note, at: date) }
        for task in tasks { _ = try mergeRemoteTask(task, at: date) }
        try enqueueAllSyncContent(at: date)
    }

    /// Once an activated legacy workspace has been adopted, automatic rollback
    /// is no longer safe. Fresh stores have no legacy marker and need no marker.
    func markCloudSeedingBegun(at date: Date) throws {
        let context = mutationContext()
        let states = try context.fetch(FetchDescriptor<LegacyMigrationState>())
        guard states.count <= 1 else { throw LegacyMigrationPersistenceError.invalidState }
        guard let state = states.first else { return }
        guard LegacyMigrationPhase(rawValue: state.phaseRawValue) == .eligibleForCutover,
              LegacyMigrationActivationState(rawValue: state.activationStateRawValue) == .activated else {
            throw LegacyMigrationPersistenceError.invalidState
        }
        if state.cloudSeedingEverBegun { return }
        state.cloudSeedingEverBegun = true
        state.updatedAt = date
        try save(context)
    }

    /// Converts an unexpected physical CloudKit deletion into the model's
    /// durable lifecycle tombstone. Cloud records are normally never deleted;
    /// this path exists for compatibility and defensive recovery.
    func tombstoneAfterRemotePhysicalDeletion(recordName: String, at date: Date) throws {
        let context = mutationContext()
        let metadata = try workspaceMetadata(in: context)
        if let noteID = NoteID(recordName: recordName) {
            let id = noteID.stringValue
            let rows = try context.fetch(FetchDescriptor<StoredNote>(
                predicate: #Predicate { $0.stableID == id }
            ))
            guard rows.count <= 1 else { throw PersistenceError.duplicateID(.note, id) }
            guard let row = rows.first else { return }
            var note = try StoredDomainMapping.note(from: row)
            guard note.lifecycle == .active else { return }
            let stamp = try nextRemoteNormalizationStamp(metadata, observing: maxVersion(in: note))
            do { try note.delete(version: stamp) }
            catch { throw PersistenceError.domainInvariant }
            try StoredDomainMapping.update(row, from: note)
            try enqueueSyncMutation(.note, stableID: id, sequence: stamp.logicalCounter, at: date, in: context)
            let children = try context.fetch(FetchDescriptor<StoredTask>(
                predicate: #Predicate { $0.noteStableID == id }
            ))
            for child in children {
                var task = try StoredDomainMapping.task(from: child, expectedNoteID: noteID)
                guard task.lifecycle == .active else { continue }
                let childStamp = try nextRemoteNormalizationStamp(
                    metadata,
                    observing: maxVersion(in: task)
                )
                do { try task.delete(version: childStamp) }
                catch { throw PersistenceError.domainInvariant }
                try StoredDomainMapping.update(child, from: task)
                try enqueueSyncMutation(
                    .task,
                    stableID: task.id.stringValue,
                    sequence: childStamp.logicalCounter,
                    at: date,
                    in: context
                )
            }
        } else if let taskID = TaskID(recordName: recordName) {
            let id = taskID.stringValue
            let rows = try context.fetch(FetchDescriptor<StoredTask>(
                predicate: #Predicate { $0.stableID == id }
            ))
            guard rows.count <= 1 else { throw PersistenceError.duplicateID(.task, id) }
            guard let row = rows.first else { return }
            var task = try StoredDomainMapping.task(from: row)
            guard task.lifecycle == .active else { return }
            let stamp = try nextRemoteNormalizationStamp(metadata, observing: maxVersion(in: task))
            do { try task.delete(version: stamp) }
            catch { throw PersistenceError.domainInvariant }
            try StoredDomainMapping.update(row, from: task)
            try enqueueSyncMutation(.task, stableID: id, sequence: stamp.logicalCounter, at: date, in: context)
        } else {
            return
        }
        try save(context)
    }
}

private extension TildoneRepository {
    func observeRemoteVersions(in note: Note, metadata: WorkspaceMetadata) throws {
        try observe([
            note.titleVersion, note.lifecycleVersion, note.lastMeaningfulEditVersion
        ], metadata: metadata)
    }

    func observeRemoteVersions(in task: Task, metadata: WorkspaceMetadata) throws {
        try observe([
            task.textVersion, task.completionVersion, task.orderVersion, task.lifecycleVersion
        ], metadata: metadata)
    }

    func observe(_ stamps: [VersionStamp], metadata: WorkspaceMetadata) throws {
        let highest = stamps.map(\.logicalCounter).max() ?? 0
        guard highest <= UInt64(Int64.max) else { throw PersistenceError.counterOverflow }
        metadata.logicalCounter = max(metadata.logicalCounter, Int64(highest))
    }

    func nextRemoteNormalizationStamp(
        _ metadata: WorkspaceMetadata,
        observing stamp: VersionStamp
    ) throws -> VersionStamp {
        guard let replica = ReplicaID(string: metadata.replicaID) else {
            throw PersistenceError.workspaceMismatch
        }
        let current = max(UInt64(metadata.logicalCounter), stamp.logicalCounter)
        guard current < UInt64(Int64.max) else { throw PersistenceError.counterOverflow }
        metadata.logicalCounter = Int64(current + 1)
        return VersionStamp(logicalCounter: current + 1, replicaID: replica)
    }

    func maxVersion(in note: Note) -> VersionStamp {
        max(max(note.titleVersion, note.lifecycleVersion), note.lastMeaningfulEditVersion)
    }

    func maxVersion(in task: Task) -> VersionStamp {
        max(max(task.textVersion, task.completionVersion), max(task.orderVersion, task.lifecycleVersion))
    }

    func enqueueSyncMutation(
        _ kind: PersistedEntityKind,
        stableID: String,
        sequence: UInt64,
        at date: Date,
        in context: ModelContext
    ) throws {
        guard sequence > 0, sequence <= UInt64(Int64.max) else {
            throw PersistenceError.counterOverflow
        }
        let rawKind = kind.rawValue
        let active = try context.fetch(FetchDescriptor<PendingMutation>(
            predicate: #Predicate {
                $0.targetKindRawValue == rawKind &&
                $0.targetStableID == stableID &&
                $0.supersededByMutationID == nil
            }
        ))
        let newID = UUID().uuidString.lowercased()
        if active.contains(where: { UInt64($0.sequence) >= sequence }) {
            return
        }
        for row in active {
            if row.attemptCount == 0 {
                context.delete(row)
            } else {
                row.supersededByMutationID = newID
            }
        }
        context.insert(PendingMutation(
            mutationID: newID,
            targetKindRawValue: rawKind,
            targetStableID: stableID,
            sequence: Int64(sequence),
            createdAt: date
        ))
    }
}
