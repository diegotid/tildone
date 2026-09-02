//
//  TildoneSyncCoordinator.swift
//  Tildone
//
import CloudKit
import Foundation
import TildoneDomain
import TildonePersistence

enum TildoneSyncBatchPolicy {
    /// CloudKit's maximum combined record saves and deletes per request.
    static let maximumRecordChanges = 250

    static func bounded<T>(_ changes: [T]) -> ArraySlice<T> {
        changes.prefix(maximumRecordChanges)
    }
}

enum SyncStatusLatchPolicy {
    static func resolve(
        requested: SyncStatus,
        current: SyncStatus,
        zoneResetRequired: Bool,
        fullReconciliationRequired: Bool = false,
        coordinatorFrozen: Bool = false
    ) -> SyncStatus {
        if zoneResetRequired, requested.availability == .available {
            return SyncStatus(
                availability: .zoneResetRequired,
                activity: .attentionNeeded,
                pendingMutationCount: requested.pendingMutationCount,
                lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
                activeDeviceSummary: requested.activeDeviceSummary ?? current.activeDeviceSummary,
                issue: .zoneReset
            )
        }
        if coordinatorFrozen, current.activity == .attentionNeeded {
            return SyncStatus(
                availability: current.availability,
                activity: .attentionNeeded,
                pendingMutationCount: requested.pendingMutationCount,
                lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
                activeDeviceSummary: requested.activeDeviceSummary ?? current.activeDeviceSummary,
                issue: current.issue ?? .unknown
            )
        }
        guard fullReconciliationRequired, requested.availability == .available else {
            return requested
        }
        return SyncStatus(
            availability: .available,
            activity: requested.activity == .idle ? .syncing : requested.activity,
            pendingMutationCount: requested.pendingMutationCount,
            lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
            activeDeviceSummary: requested.activeDeviceSummary ?? current.activeDeviceSummary,
            issue: requested.issue
        )
    }
}

enum SyncFetchRecoveryPolicy {
    static func requiresFullReconciliation(_ code: CKError.Code) -> Bool {
        code == .partialFailure || code == .changeTokenExpired
    }
}

enum SyncZoneBootstrapPolicy {
    static func shouldScheduleRecordChanges(
        zoneCreated: Bool,
        zoneResetRequired: Bool
    ) -> Bool {
        zoneCreated && !zoneResetRequired
    }

    static func shouldLatchMissingZone(zoneCreated: Bool) -> Bool {
        zoneCreated
    }
}

public final class TildoneSyncCoordinator: CKSyncEngineDelegate, @unchecked Sendable {
    public typealias AccountChangeHandler = @Sendable (SyncAccountChange) -> Void
    public typealias RemoteChangeHandler = @Sendable (RemoteContentChange) async throws -> Void

    public let statusModel: SyncStatusModel

    private let repository: TildoneRepository
    private let database: CKDatabase
    private let pipeline: SyncPipeline
    private let mapper = CloudKitRecordMapper()
    private let coordinatorState: SyncCoordinatorState
    private let now: @Sendable () -> Date
    private let clientReplicaID: ReplicaID
    private let clientPlatform: SyncClientPlatform
    private let onAccountChange: AccountChangeHandler
    private let onRemoteChange: RemoteChangeHandler
    private var engine: CKSyncEngine?

    public init(
        repository: TildoneRepository,
        container: CKContainer = CKContainer(identifier: TildoneCloudSchema.containerIdentifier),
        statusModel: SyncStatusModel = SyncStatusModel(),
        now: @escaping @Sendable () -> Date = { Date() },
        clientPlatform: SyncClientPlatform,
        onAccountChange: @escaping AccountChangeHandler = { _ in },
        onRemoteChange: @escaping RemoteChangeHandler = { _ in }
    ) async throws {
        let workspace = try await repository.workspaceSnapshot()
        guard workspace.identityKind == "account", workspace.opaqueWorkspaceID != nil else {
            throw PersistenceError.workspaceMismatch
        }
        self.repository = repository
        database = container.privateCloudDatabase
        pipeline = SyncPipeline(repository: repository)
        self.statusModel = statusModel
        self.now = now
        clientReplicaID = workspace.replicaID
        self.clientPlatform = clientPlatform
        self.onAccountChange = onAccountChange
        self.onRemoteChange = onRemoteChange

        var persistent = SyncPersistentState(data: workspace.futureSyncEngineState)
        if persistent.prepareForFullReconciliationIfNeeded() {
            try await repository.storeFutureSyncEngineState(persistent.encoded())
        }
        coordinatorState = SyncCoordinatorState(persistent: persistent, repository: repository)
        if persistent.fullReconciliationRequired {
            // Defer engine creation until start(), so the required nil-state
            // fetch cannot race an automatically started legacy engine.
            engine = nil
        } else {
            var configuration = CKSyncEngine.Configuration(
                database: database,
                stateSerialization: persistent.decodedEngineSerialization,
                delegate: self
            )
            configuration.automaticallySync = true
            configuration.subscriptionID = TildoneCloudSchema.subscriptionIdentifier
            engine = CKSyncEngine(configuration)
            try await bootstrapPendingChanges()
        }
    }

    /// Source-compatible adapter for clients that only need a refresh signal.
    /// New clients can use `RemoteChangeHandler` to invalidate record-scoped
    /// presentation state before refreshing.
    public convenience init(
        repository: TildoneRepository,
        container: CKContainer = CKContainer(identifier: TildoneCloudSchema.containerIdentifier),
        statusModel: SyncStatusModel = SyncStatusModel(),
        now: @escaping @Sendable () -> Date = { Date() },
        clientPlatform: SyncClientPlatform,
        onAccountChange: @escaping AccountChangeHandler = { _ in },
        onRemoteChange: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await self.init(
            repository: repository,
            container: container,
            statusModel: statusModel,
            now: now,
            clientPlatform: clientPlatform,
            onAccountChange: onAccountChange,
            onRemoteChange: { _ in try await onRemoteChange() }
        )
    }

    /// Starts an immediate checkpoint while leaving normal scheduling to
    /// CKSyncEngine. Editing never waits for this method.
    public func start() async {
        await runCheckpoint(retryAfterRecovery: true)
    }

    private func runCheckpoint(retryAfterRecovery: Bool) async {
        if await coordinatorState.requiresFullReconciliation() {
            do {
                try await rebuildEngineForFullReconciliation()
            } catch {
                await apply(error: error)
                return
            }
        }
        guard let engine, !(await coordinatorState.isFrozen()) else {
            await refreshStatus(activity: .attentionNeeded, issue: .zoneReset)
            return
        }
        do {
            try await refreshPendingEngineChanges()
            SyncDiagnostics.checkpointStarted(pendingCount: try await pipeline.pendingCount())
            await refreshStatus(activity: .syncing)
            try await engine.sendChanges()
        } catch {
            await apply(error: error)
            return
        }

        guard engine === self.engine, !(await coordinatorState.isFrozen()) else { return }
        do {
            let persistent = await coordinatorState.snapshot()
            if SyncZoneBootstrapPolicy.shouldScheduleRecordChanges(
                zoneCreated: persistent.zoneCreated,
                zoneResetRequired: persistent.zoneResetRequired
            ) {
                try await engine.fetchChanges(
                    CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([TildoneCloudSchema.zoneID]))
                )
            }
        } catch {
            if await requireFullReconciliation(forFetchError: error), retryAfterRecovery {
                await runCheckpoint(retryAfterRecovery: false)
            }
        }
    }

    public func stop() async {
        await coordinatorState.freeze()
        await engine?.cancelOperations()
    }

    /// Freezes this coordinator instance and cancels its CloudKit operations.
    /// The repository, durable outbox, tombstones, system fields, and serialized
    /// engine envelope are intentionally left untouched. Resume constructs a
    /// new coordinator from that same workspace state.
    public func pause() async {
        await coordinatorState.freeze()
        await engine?.cancelOperations()
        let current = await statusModel.snapshot()
        let pending = (try? await pipeline.pendingCount()) ?? current.pendingMutationCount
        let retainsAttention = current.activity == .attentionNeeded || [
            .adoptionRequired,
            .accountChanged,
            .zoneResetRequired,
            .incompatibleRemoteData
        ].contains(current.availability)
        await statusModel.set(SyncStatus(
            availability: retainsAttention ? current.availability : .available,
            activity: retainsAttention ? .attentionNeeded : .paused,
            pendingMutationCount: pending,
            lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
            activeDeviceSummary: current.activeDeviceSummary,
            issue: current.issue
        ))
    }

    /// Call after a local repository mutation. Duplicate additions are harmless
    /// because CKSyncEngine pending changes are value-deduplicated.
    public func notifyLocalChanges() async {
        do {
            try await refreshPendingEngineChanges()
            await refreshStatus(activity: .syncing)
        } catch {
            await apply(error: error)
        }
    }

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncEngine === engine else { return }
        // Cancellation can race an already-delivered engine callback. Once
        // frozen, ignore every data/checkpoint event so pausing cannot apply a
        // fetch, serialize a newer checkpoint, or acknowledge durable outbox
        // work. Account changes still propagate to preserve account isolation.
        if await coordinatorState.isFrozen() {
            switch event {
            case .accountChange:
                break
            default:
                return
            }
        }
        switch event {
        case let .stateUpdate(update):
            guard !(await coordinatorState.isFrozen()) else { break }
            do {
                try await coordinatorState.updateEngineSerialization(
                    update.stateSerialization
                )
            } catch {
                await apply(error: error)
            }

        case let .accountChange(change):
            await handleAccountChange(change.changeType)

        case let .fetchedDatabaseChanges(changes):
            let persistent = await coordinatorState.snapshot()
            if SyncZoneBootstrapPolicy.shouldLatchMissingZone(
                zoneCreated: persistent.zoneCreated
            ), changes.deletions.contains(where: { $0.zoneID == TildoneCloudSchema.zoneID }) {
                await freezeForZoneReset()
            }

        case let .fetchedRecordZoneChanges(changes):
            await handleFetchedRecordZoneChanges(changes)

        case let .sentDatabaseChanges(changes):
            await handleSentDatabaseChanges(changes)

        case let .sentRecordZoneChanges(changes):
            await handleSentRecordZoneChanges(changes, syncEngine: syncEngine)

        case .willFetchChanges:
            await coordinatorState.beginFetch()
            await refreshStatus(activity: .syncing)

        case .willFetchRecordZoneChanges, .willSendChanges:
            await refreshStatus(activity: .syncing)

        case .didFetchRecordZoneChanges:
            break

        case .didFetchChanges:
            do {
                try await coordinatorState.completeFetch()
                await markFetchCheckpointComplete()
            } catch {
                await apply(error: error)
            }

        case .didSendChanges:
            await markSendCheckpointComplete()

        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !(await coordinatorState.isFrozen()) else { return nil }
        let persistent = await coordinatorState.snapshot()
        guard SyncZoneBootstrapPolicy.shouldScheduleRecordChanges(
            zoneCreated: persistent.zoneCreated,
            zoneResetRequired: persistent.zoneResetRequired
        ) else { return nil }
        let pending = TildoneSyncBatchPolicy.bounded(
            syncEngine.state.pendingRecordZoneChanges.filter {
                context.options.scope.contains($0)
            }
        )
        var records: [CKRecord] = []
        var stale: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in pending {
            guard case let .saveRecord(recordID) = change,
                  recordID.zoneID == TildoneCloudSchema.zoneID else { continue }
            if let replicaID = SyncClientRegistration.replicaID(
                recordName: recordID.recordName
            ) {
                guard replicaID == clientReplicaID else {
                    stale.append(change)
                    continue
                }
                let systemRecord = await coordinatorState.systemRecord(
                    named: recordID.recordName
                )
                records.append(mapper.clientRecord(
                    replicaID: clientReplicaID,
                    platform: clientPlatform,
                    reusing: systemRecord
                ))
                continue
            }
            do {
                guard let mutation = try await pipeline.prepareOutboundMutation(
                    recordName: recordID.recordName,
                    at: now()
                ) else {
                    stale.append(change)
                    continue
                }
                let systemRecord = await coordinatorState.systemRecord(named: recordID.recordName)
                records.append(mapper.record(from: mutation.record, reusing: systemRecord))
                await coordinatorState.markInFlight(
                    recordName: recordID.recordName,
                    mutationID: mutation.mutationID
                )
            } catch {
                await apply(error: error)
            }
        }
        if !stale.isEmpty { syncEngine.state.remove(pendingRecordZoneChanges: stale) }
        guard !records.isEmpty else { return nil }
        return CKSyncEngine.RecordZoneChangeBatch(recordsToSave: records, atomicByZone: false)
    }
}

private extension TildoneSyncCoordinator {
    func rebuildEngineForFullReconciliation() async throws {
        let previousEngine = engine
        engine = nil
        await previousEngine?.cancelOperations()

        let persistent = await coordinatorState.snapshot()
        guard persistent.fullReconciliationRequired,
              !persistent.zoneResetRequired,
              !(await coordinatorState.isFrozen()) else { return }
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: nil,
            delegate: self
        )
        configuration.automaticallySync = true
        configuration.subscriptionID = TildoneCloudSchema.subscriptionIdentifier
        engine = CKSyncEngine(configuration)
        try await bootstrapPendingChanges()
    }

    func bootstrapPendingChanges() async throws {
        guard let engine else { return }
        let persistent = await coordinatorState.snapshot()
        if persistent.zoneResetRequired {
            await publishStatus(SyncStatus(
                availability: .zoneResetRequired,
                activity: .attentionNeeded,
                pendingMutationCount: try await pipeline.pendingCount(),
                issue: .zoneReset
            ))
            return
        }
        if !persistent.zoneCreated {
            let zone = CKRecordZone(zoneID: TildoneCloudSchema.zoneID)
            engine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
        } else {
            try await refreshPendingEngineChanges()
        }
        await refreshStatus(activity: .idle)
    }

    func refreshPendingEngineChanges() async throws {
        guard let engine, !(await coordinatorState.isFrozen()) else { return }
        let persistent = await coordinatorState.snapshot()
        guard SyncZoneBootstrapPolicy.shouldScheduleRecordChanges(
            zoneCreated: persistent.zoneCreated,
            zoneResetRequired: persistent.zoneResetRequired
        ) else { return }
        let recordIDs = try await pipeline.pendingRecordNames().map {
            CKRecord.ID(recordName: $0, zoneID: TildoneCloudSchema.zoneID)
        }
        var changes = recordIDs.map { CKSyncEngine.PendingRecordZoneChange.saveRecord($0) }
        let ownRegistration = persistent.clientRegistration(replicaID: clientReplicaID)
        if SyncClientActivityPolicy.shouldRefresh(registration: ownRegistration, at: now()) {
            let clientRecordID = CKRecord.ID(
                recordName: SyncClientRegistration(
                    replicaID: clientReplicaID,
                    platform: clientPlatform,
                    lastSeenAt: .distantPast
                ).recordName,
                zoneID: TildoneCloudSchema.zoneID
            )
            changes.append(.saveRecord(clientRecordID))
        }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange.ChangeType) async {
        switch change {
        case .signIn:
            SyncDiagnostics.accountChanged(category: .signedIn)
            do {
                // CKSyncEngine clears its pending engine changes when the
                // account changes. Rehydrate them from Tildone's durable
                // outbox so an initial sign-in event cannot strand local work.
                try await bootstrapPendingChanges()
            } catch {
                await apply(error: error)
            }
            onAccountChange(.signedIn)
        case .signOut:
            SyncDiagnostics.accountChanged(category: .signedOut)
            await coordinatorState.freeze()
            scheduleEngineCancellation()
            await refreshStatus(
                availability: .accountChanged,
                activity: .attentionNeeded,
                issue: .accountChanged
            )
            onAccountChange(.signedOut)
        case .switchAccounts:
            SyncDiagnostics.accountChanged(category: .switched)
            await coordinatorState.freeze()
            scheduleEngineCancellation()
            await refreshStatus(
                availability: .accountChanged,
                activity: .attentionNeeded,
                issue: .accountChanged
            )
            onAccountChange(.switched)
        @unknown default:
            break
        }
    }

    func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges
    ) async {
        SyncDiagnostics.fetched(
            modificationCount: event.modifications.count,
            deletionCount: event.deletions.count
        )
        var decoded: [SyncRecord] = []
        var clientRegistrationsChanged = false
        for modification in event.modifications {
            let record = modification.record
            guard record.recordID.zoneID == TildoneCloudSchema.zoneID else { continue }
            do {
                if record.recordType == TildoneCloudSchema.clientRecordType {
                    let registration = try mapper.clientRegistration(
                        from: record,
                        observedAt: record.modificationDate ?? now()
                    )
                    clientRegistrationsChanged = try await coordinatorState
                        .storeClientRegistration(registration, record: record) ||
                        clientRegistrationsChanged
                } else {
                    decoded.append(try mapper.syncRecord(from: record))
                    try await coordinatorState.storeSystemFields(record)
                }
            } catch let error as CloudRecordMappingError {
                await quarantine(record: record, mappingError: error)
            } catch {
                await apply(error: error)
            }
        }
        do {
            var changedRecords: Set<DomainRecordID> = []
            if !decoded.isEmpty {
                let result = try await pipeline.apply(decoded, at: now())
                changedRecords.formUnion(result.changedRecords)
            }
            for deletion in event.deletions where deletion.recordID.zoneID == TildoneCloudSchema.zoneID {
                if SyncClientRegistration.replicaID(
                    recordName: deletion.recordID.recordName
                ) != nil {
                    clientRegistrationsChanged = try await coordinatorState
                        .removeClientRegistration(recordName: deletion.recordID.recordName) ||
                        clientRegistrationsChanged
                } else {
                    changedRecords.formUnion(try await pipeline.applyPhysicalDeletion(
                        recordName: deletion.recordID.recordName,
                        at: now()
                    ))
                }
            }
            if !decoded.isEmpty || !event.deletions.isEmpty {
                if !decoded.isEmpty || event.deletions.contains(where: {
                    SyncClientRegistration.replicaID(recordName: $0.recordID.recordName) == nil
                }) {
                    try await onRemoteChange(RemoteContentChange(
                        changedRecords: changedRecords
                    ))
                }
                // The presentation callback may perform an idempotent local
                // schema backfill for a legacy record. Refresh afterwards so
                // any outbox work created by that backfill is scheduled in
                // this same checkpoint.
                try await refreshPendingEngineChanges()
            }
            if clientRegistrationsChanged {
                await publishStatus(await statusModel.snapshot())
            }
        } catch {
            await apply(error: error)
        }
    }

    func handleSentDatabaseChanges(
        _ event: CKSyncEngine.Event.SentDatabaseChanges
    ) async {
        if event.savedZones.contains(where: { $0.zoneID == TildoneCloudSchema.zoneID }) {
            do {
                if try await coordinatorState.markZoneCreated() {
                    try await refreshPendingEngineChanges()
                    await refreshStatus(activity: .syncing)
                }
            } catch {
                await apply(error: error)
            }
        }
        for failure in event.failedZoneSaves where failure.zone.zoneID == TildoneCloudSchema.zoneID {
            await apply(error: failure.error)
        }
        if event.deletedZoneIDs.contains(TildoneCloudSchema.zoneID) {
            await freezeForZoneReset()
        }
    }

    func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        SyncDiagnostics.sent(
            savedCount: event.savedRecords.count,
            failedCount: event.failedRecordSaves.count
        )
        var acknowledgements: Set<UUID> = []
        for record in event.savedRecords where record.recordID.zoneID == TildoneCloudSchema.zoneID {
            if record.recordType == TildoneCloudSchema.clientRecordType {
                do {
                    let registration = try mapper.clientRegistration(
                        from: record,
                        observedAt: record.modificationDate ?? now()
                    )
                    _ = try await coordinatorState.storeClientRegistration(
                        registration,
                        record: record
                    )
                } catch let mappingError as CloudRecordMappingError {
                    await quarantine(record: record, mappingError: mappingError)
                } catch {
                    await apply(error: error)
                }
                continue
            }
            if let mutation = await coordinatorState.takeInFlight(
                recordName: record.recordID.recordName
            ) {
                acknowledgements.insert(mutation)
            }
            do { try await coordinatorState.storeSystemFields(record) }
            catch { await apply(error: error) }
        }
        if !acknowledgements.isEmpty {
            do { try await pipeline.acknowledge(acknowledgements) }
            catch { await apply(error: error) }
        }

        for failure in event.failedRecordSaves {
            let error = failure.error
            if error.code == .serverRecordChanged,
               let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                do {
                    if serverRecord.recordType == TildoneCloudSchema.clientRecordType {
                        let registration = try mapper.clientRegistration(
                            from: serverRecord,
                            observedAt: serverRecord.modificationDate ?? now()
                        )
                        _ = try await coordinatorState.storeClientRegistration(
                            registration,
                            record: serverRecord
                        )
                    } else {
                        let remote = try mapper.syncRecord(from: serverRecord)
                        let result = try await pipeline.apply([remote], at: now())
                        try await coordinatorState.storeSystemFields(serverRecord)
                        try await onRemoteChange(RemoteContentChange(
                            changedRecords: result.changedRecords
                        ))
                    }
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(serverRecord.recordID)])
                } catch let mappingError as CloudRecordMappingError {
                    await quarantine(record: serverRecord, mappingError: mappingError)
                } catch {
                    await apply(error: error)
                }
            } else if error.code == .zoneNotFound {
                await freezeForZoneReset()
            } else {
                // Keep only the failed record scheduled. Successful siblings
                // have already been acknowledged above.
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
                await apply(error: error)
            }
        }
        do { try await refreshPendingEngineChanges() }
        catch { await apply(error: error) }
    }

    func quarantine(record: CKRecord, mappingError: CloudRecordMappingError) async {
        let kind: QuarantinedRecordKind
        let identifier: String
        switch record.recordType {
        case TildoneCloudSchema.noteRecordType where NoteID(recordName: record.recordID.recordName) != nil:
            kind = .note
            identifier = record.recordID.recordName
        case TildoneCloudSchema.taskRecordType where TaskID(recordName: record.recordID.recordName) != nil:
            kind = .task
            identifier = record.recordID.recordName
        case TildoneCloudSchema.clientRecordType
            where SyncClientRegistration.replicaID(recordName: record.recordID.recordName) != nil:
            kind = .client
            identifier = record.recordID.recordName
        default:
            kind = .unknown
            identifier = "unknown-" + UUID().uuidString.lowercased()
        }

        let category: QuarantineCategory
        let schema: Int?
        switch mappingError {
        case let .unsupportedSchema(_, version):
            category = .unsupportedSchema
            schema = version
        case .malformedIdentifier:
            category = .malformedIdentifier
            schema = nil
        case .unsupportedRecordType:
            category = .unsupportedRecordType
            schema = nil
        case let .invalidField(_, field), let .missingField(_, field):
            if field.localizedCaseInsensitiveContains("version") {
                category = .invalidVersion
            } else if field == "lifecycle" {
                category = .invalidLifecycle
            } else if field == "orderToken" {
                category = .invalidOrderToken
            } else if field == "noteID" {
                category = .invalidOwnership
            } else if field == "completedAt" || field == "isCompleted" {
                category = .invalidCompletion
            } else {
                category = .invalidVersion
            }
            schema = nil
        case .wrongZone:
            category = .unsupportedRecordType
            schema = nil
        }
        SyncDiagnostics.quarantined(category: category)
        do {
            try await repository.quarantine(
                recordKind: kind,
                opaqueRecordID: identifier,
                category: category,
                recordSchemaVersion: schema,
                at: now()
            )
        } catch {
            await apply(error: error)
            return
        }

        if kind == .client {
            await publishStatus(await statusModel.snapshot())
        } else if category == .unsupportedSchema {
            await coordinatorState.freeze()
            scheduleEngineCancellation()
            await refreshStatus(
                availability: .incompatibleRemoteData,
                activity: .attentionNeeded,
                issue: .futureSchema
            )
        } else {
            await refreshStatus(activity: .attentionNeeded, issue: .malformedRemoteRecord)
        }
    }

    func freezeForZoneReset() async {
        do { try await coordinatorState.freezeForZoneReset() }
        catch { await apply(error: error) }
        scheduleEngineCancellation()
        await refreshStatus(
            availability: .zoneResetRequired,
            activity: .attentionNeeded,
            issue: .zoneReset
        )
    }

    func markFetchCheckpointComplete() async {
        // A local persistence/presentation refresh failure freezes this
        // coordinator so a later CKSyncEngine completion callback cannot
        // overwrite attention with a healthy checkpoint.
        guard !(await coordinatorState.isFrozen()) else { return }
        let pending = (try? await pipeline.pendingCount()) ?? 0
        await publishStatus(SyncStatus(
            availability: .available,
            activity: pending == 0 ? .idle : .syncing,
            pendingMutationCount: pending,
            lastSuccessfulSyncAt: now(),
            activeDeviceSummary: nil,
            issue: nil
        ))
    }

    func markSendCheckpointComplete() async {
        guard !(await coordinatorState.isFrozen()) else { return }
        let current = await statusModel.snapshot()
        let pending = (try? await pipeline.pendingCount()) ?? current.pendingMutationCount
        await publishStatus(SyncStatus(
            availability: .available,
            activity: pending == 0 ? .idle : .syncing,
            pendingMutationCount: pending,
            lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
            activeDeviceSummary: current.activeDeviceSummary,
            issue: nil
        ))
    }

    func refreshStatus(
        availability: SyncAvailability = .available,
        activity: SyncActivity,
        issue: SyncIssue? = nil
    ) async {
        let current = await statusModel.snapshot()
        let pending = (try? await pipeline.pendingCount()) ?? current.pendingMutationCount
        let status = SyncStatus(
            availability: availability,
            activity: activity,
            pendingMutationCount: pending,
            lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
            activeDeviceSummary: current.activeDeviceSummary,
            issue: issue
        )
        await publishStatus(status)
    }

    func publishStatus(_ requested: SyncStatus) async {
        let current = await statusModel.snapshot()
        let persistent = await coordinatorState.snapshot()
        let activeDeviceSummary = SyncClientActivityPolicy.activeDeviceSummary(
            registrations: persistent.clientRegistrationsByReplicaID,
            currentReplicaID: clientReplicaID,
            currentPlatform: clientPlatform,
            at: now()
        )
        let annotated = SyncStatus(
            availability: requested.availability,
            activity: requested.activity,
            pendingMutationCount: requested.pendingMutationCount,
            lastSuccessfulSyncAt: requested.lastSuccessfulSyncAt,
            activeDeviceSummary: activeDeviceSummary,
            issue: requested.issue
        )
        let status = SyncStatusLatchPolicy.resolve(
            requested: annotated,
            current: current,
            zoneResetRequired: persistent.zoneResetRequired,
            fullReconciliationRequired: persistent.fullReconciliationRequired,
            coordinatorFrozen: await coordinatorState.isFrozen()
        )
        guard status != current else { return }
        await statusModel.set(status)
        SyncDiagnostics.statusChanged(status)
    }

    func apply(error: Error) async {
        guard let cloudError = error as? CKError else {
            SyncDiagnostics.failed(category: .classify(error))
            // A local persistence failure while processing fetched changes
            // must not be followed by a newer serialized engine checkpoint.
            // Freeze only this coordinator instance; relaunch restores the
            // last durable checkpoint and can redeliver idempotently.
            await coordinatorState.freeze()
            scheduleEngineCancellation()
            await refreshStatus(activity: .attentionNeeded, issue: .unknown)
            return
        }
        SyncDiagnostics.failed(category: .cloud(cloudError.code.rawValue))
        switch cloudError.code {
        case .operationCancelled:
            // CKSyncEngine cancels an in-flight manual checkpoint when the
            // coordinator is paused, stopped, or superseded. Its durable
            // outbox remains intact, so this is not user-actionable.
            guard !(await coordinatorState.isFrozen()) else { return }
            let pending = (try? await pipeline.pendingCount()) ?? 0
            await refreshStatus(activity: pending == 0 ? .idle : .syncing)
        case .networkFailure, .networkUnavailable:
            await refreshStatus(activity: .offline, issue: .network)
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            await refreshStatus(activity: .offline, issue: .service)
        case .quotaExceeded:
            await refreshStatus(activity: .attentionNeeded, issue: .quotaExceeded)
        case .notAuthenticated, .permissionFailure, .managedAccountRestricted:
            await refreshStatus(activity: .attentionNeeded, issue: .permission)
        case .accountTemporarilyUnavailable:
            await refreshStatus(
                availability: .temporarilyUnavailable,
                activity: .offline,
                issue: .service
            )
        case .zoneNotFound, .userDeletedZone:
            await freezeForZoneReset()
        default:
            await refreshStatus(activity: .attentionNeeded, issue: .unknown)
        }
    }

    func requireFullReconciliation(forFetchError error: Error) async -> Bool {
        guard let cloudError = error as? CKError,
              SyncFetchRecoveryPolicy.requiresFullReconciliation(cloudError.code) else {
            await apply(error: error)
            return false
        }
        SyncDiagnostics.failed(category: .cloud(cloudError.code.rawValue))
        do {
            try await coordinatorState.requireFullReconciliation()
            let current = await statusModel.snapshot()
            await publishStatus(SyncStatus(
                availability: .available,
                activity: .attentionNeeded,
                pendingMutationCount: (try? await pipeline.pendingCount()) ??
                    current.pendingMutationCount,
                lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
                activeDeviceSummary: current.activeDeviceSummary,
                issue: .unknown
            ))
            return true
        } catch {
            await apply(error: error)
            return false
        }
    }

    /// CKSyncEngine forbids awaiting an operation that can re-enter its
    /// delegate while a delegate callback is still on the stack.
    func scheduleEngineCancellation() {
        guard let engine else { return }
        Swift.Task.detached {
            await engine.cancelOperations()
        }
    }

}
