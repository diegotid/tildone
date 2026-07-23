//
//  SyncPipeline.swift
//  Tildone
//
import Foundation
import TildoneDomain
import TildonePersistence

/// Durable outbox and deterministic merge bridge. Tests can drive this actor
/// without CloudKit, an Apple Account, or a network.
public actor SyncPipeline {
    private let repository: TildoneRepository
    private let beforeOutboundClaim: @Sendable () async -> Void

    public init(repository: TildoneRepository) {
        self.repository = repository
        beforeOutboundClaim = {}
    }

    init(
        repository: TildoneRepository,
        beforeOutboundClaim: @escaping @Sendable () async -> Void
    ) {
        self.repository = repository
        self.beforeOutboundClaim = beforeOutboundClaim
    }

    public func pendingCount() async throws -> Int {
        try await repository.pendingMutations().count
    }

    public func pendingRecordNames() async throws -> [String] {
        try await repository.pendingMutations().compactMap { mutation in
            switch mutation.targetKind {
            case .note: NoteID(string: mutation.targetStableID)?.recordName
            case .task: TaskID(string: mutation.targetStableID)?.recordName
            }
        }
    }

    public func prepareOutboundMutation(
        recordName: String,
        at date: Date
    ) async throws -> SyncOutboundMutation? {
        let target: (PersistedEntityKind, String)
        if let id = NoteID(recordName: recordName) {
            target = (.note, id.stringValue)
        } else if let id = TaskID(recordName: recordName) {
            target = (.task, id.stringValue)
        } else {
            return nil
        }
        await beforeOutboundClaim()
        guard let prepared = try await repository.preparePendingMutation(
            targetKind: target.0,
            targetStableID: target.1,
            at: date
        ) else {
            return nil
        }
        let record: SyncRecord = switch prepared.payload {
        case let .note(note): .note(note)
        case let .task(task): .task(task)
        }
        return SyncOutboundMutation(mutationID: prepared.mutationID, record: record)
    }

    public func acknowledge(_ mutationIDs: Set<UUID>) async throws {
        try await repository.acknowledgeMutations(ids: mutationIDs)
    }

    @discardableResult
    public func apply(_ records: [SyncRecord], at date: Date) async throws -> RemoteMergeResult {
        var changed = false
        var generated = 0
        // Parents first makes a same-batch parent tombstone authoritative even
        // when CloudKit delivered child modifications before it.
        for record in records where record.kind == .note {
            guard case let .note(note) = record else { continue }
            let result = try await repository.mergeRemoteNote(note, at: date)
            changed = changed || result.changed
            generated += result.generatedTombstoneMutationCount
        }
        for record in records where record.kind == .task {
            guard case let .task(task) = record else { continue }
            let result = try await repository.mergeRemoteTask(task, at: date)
            changed = changed || result.changed
            generated += result.generatedTombstoneMutationCount
        }
        return RemoteMergeResult(changed: changed, generatedTombstoneMutationCount: generated)
    }

    public func applyPhysicalDeletion(recordName: String, at date: Date) async throws {
        try await repository.tombstoneAfterRemotePhysicalDeletion(
            recordName: recordName,
            at: date
        )
    }
}
