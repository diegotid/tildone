//
//  TildoneSyncCoordinator.swift
//  Tildone
//
import CloudKit
import Foundation
import TildoneDomain
import TildonePersistence

public final class TildoneSyncCoordinator: CKSyncEngineDelegate, @unchecked Sendable {
    public typealias AccountChangeHandler = @Sendable (SyncAccountChange) -> Void
    public typealias RemoteChangeHandler = @Sendable () async -> Void

    public let statusModel: SyncStatusModel

    private let repository: TildoneRepository
    private let pipeline: SyncPipeline
    private let mapper = CloudKitRecordMapper()
    private let coordinatorState: SyncCoordinatorState
    private let now: @Sendable () -> Date
    private let onAccountChange: AccountChangeHandler
    private let onRemoteChange: RemoteChangeHandler
    private var engine: CKSyncEngine?

    public init(
        repository: TildoneRepository,
        container: CKContainer = CKContainer(identifier: TildoneCloudSchema.containerIdentifier),
        statusModel: SyncStatusModel = SyncStatusModel(),
        now: @escaping @Sendable () -> Date = { Date() },
        onAccountChange: @escaping AccountChangeHandler = { _ in },
        onRemoteChange: @escaping RemoteChangeHandler = {}
    ) async throws {
        let workspace = try await repository.workspaceSnapshot()
        guard workspace.identityKind == "account", workspace.opaqueWorkspaceID != nil else {
            throw PersistenceError.workspaceMismatch
        }
        self.repository = repository
        pipeline = SyncPipeline(repository: repository)
        self.statusModel = statusModel
        self.now = now
        self.onAccountChange = onAccountChange
        self.onRemoteChange = onRemoteChange

        let persistent = SyncPersistentState(data: workspace.futureSyncEngineState)
        coordinatorState = SyncCoordinatorState(persistent: persistent, repository: repository)
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: persistent.decodedEngineSerialization,
            delegate: self
        )
        configuration.automaticallySync = true
        configuration.subscriptionID = TildoneCloudSchema.subscriptionIdentifier
        engine = CKSyncEngine(configuration)
        try await bootstrapPendingChanges()
    }

    /// Starts an immediate checkpoint while leaving normal scheduling to
    /// CKSyncEngine. Editing never waits for this method.
    public func start() async {
        guard let engine, !(await coordinatorState.isFrozen()) else {
            await refreshStatus(activity: .attentionNeeded, issue: .zoneReset)
            return
        }
        do {
            try await refreshPendingEngineChanges()
            await refreshStatus(activity: .syncing)
            try await engine.sendChanges()
            try await engine.fetchChanges(
                CKSyncEngine.FetchChangesOptions(scope: .zoneIDs([TildoneCloudSchema.zoneID]))
            )
        } catch {
            await apply(error: error)
        }
    }

    public func stop() async {
        await coordinatorState.freeze()
        await engine?.cancelOperations()
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
        switch event {
        case let .stateUpdate(update):
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
            if changes.deletions.contains(where: { $0.zoneID == TildoneCloudSchema.zoneID }) {
                await freezeForZoneReset()
            }

        case let .fetchedRecordZoneChanges(changes):
            await handleFetchedRecordZoneChanges(changes)

        case let .sentDatabaseChanges(changes):
            await handleSentDatabaseChanges(changes)

        case let .sentRecordZoneChanges(changes):
            await handleSentRecordZoneChanges(changes, syncEngine: syncEngine)

        case .willFetchChanges, .willFetchRecordZoneChanges, .willSendChanges:
            await refreshStatus(activity: .syncing)

        case .didFetchRecordZoneChanges:
            break

        case .didFetchChanges, .didSendChanges:
            await markCheckpointComplete()

        @unknown default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        guard !(await coordinatorState.isFrozen()) else { return nil }
        let pending = syncEngine.state.pendingRecordZoneChanges.filter {
            context.options.scope.contains($0)
        }
        var records: [CKRecord] = []
        var stale: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in pending {
            guard case let .saveRecord(recordID) = change,
                  recordID.zoneID == TildoneCloudSchema.zoneID else { continue }
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
    func bootstrapPendingChanges() async throws {
        guard let engine else { return }
        let persistent = await coordinatorState.snapshot()
        if persistent.zoneResetRequired {
            await statusModel.set(SyncStatus(
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
        }
        try await refreshPendingEngineChanges()
        await refreshStatus(activity: .idle)
    }

    func refreshPendingEngineChanges() async throws {
        guard let engine, !(await coordinatorState.isFrozen()) else { return }
        let recordIDs = try await pipeline.pendingRecordNames().map {
            CKRecord.ID(recordName: $0, zoneID: TildoneCloudSchema.zoneID)
        }
        engine.state.add(pendingRecordZoneChanges: recordIDs.map { .saveRecord($0) })
    }

    func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange.ChangeType) async {
        switch change {
        case .signIn:
            await refreshStatus(activity: .syncing)
            onAccountChange(.signedIn)
        case .signOut:
            await coordinatorState.freeze()
            await engine?.cancelOperations()
            await refreshStatus(
                availability: .accountChanged,
                activity: .attentionNeeded,
                issue: .accountChanged
            )
            onAccountChange(.signedOut)
        case .switchAccounts:
            await coordinatorState.freeze()
            await engine?.cancelOperations()
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
        var decoded: [SyncRecord] = []
        for modification in event.modifications {
            let record = modification.record
            guard record.recordID.zoneID == TildoneCloudSchema.zoneID else { continue }
            do {
                decoded.append(try mapper.syncRecord(from: record))
                try await coordinatorState.storeSystemFields(record)
            } catch let error as CloudRecordMappingError {
                await quarantine(record: record, mappingError: error)
            } catch {
                await apply(error: error)
            }
        }
        do {
            if !decoded.isEmpty {
                _ = try await pipeline.apply(decoded, at: now())
            }
            for deletion in event.deletions where deletion.recordID.zoneID == TildoneCloudSchema.zoneID {
                try? await pipeline.applyPhysicalDeletion(
                    recordName: deletion.recordID.recordName,
                    at: now()
                )
            }
            if !decoded.isEmpty || !event.deletions.isEmpty {
                try await refreshPendingEngineChanges()
                await onRemoteChange()
            }
        } catch {
            await apply(error: error)
        }
    }

    func handleSentDatabaseChanges(
        _ event: CKSyncEngine.Event.SentDatabaseChanges
    ) async {
        if event.savedZones.contains(where: { $0.zoneID == TildoneCloudSchema.zoneID }) {
            do { try await coordinatorState.markZoneCreated() }
            catch { await apply(error: error) }
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
        var acknowledgements: Set<UUID> = []
        for record in event.savedRecords where record.recordID.zoneID == TildoneCloudSchema.zoneID {
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
                    let remote = try mapper.syncRecord(from: serverRecord)
                    _ = try await pipeline.apply([remote], at: now())
                    try await coordinatorState.storeSystemFields(serverRecord)
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(serverRecord.recordID)])
                    await onRemoteChange()
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

        if category == .unsupportedSchema {
            await coordinatorState.freeze()
            await engine?.cancelOperations()
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
        await engine?.cancelOperations()
        await refreshStatus(
            availability: .zoneResetRequired,
            activity: .attentionNeeded,
            issue: .zoneReset
        )
    }

    func markCheckpointComplete() async {
        let pending = (try? await pipeline.pendingCount()) ?? 0
        await statusModel.set(SyncStatus(
            availability: .available,
            activity: pending == 0 ? .idle : .syncing,
            pendingMutationCount: pending,
            lastSuccessfulSyncAt: now(),
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
        await statusModel.set(SyncStatus(
            availability: availability,
            activity: activity,
            pendingMutationCount: pending,
            lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
            issue: issue
        ))
    }

    func apply(error: Error) async {
        guard let cloudError = error as? CKError else {
            await refreshStatus(activity: .attentionNeeded, issue: .unknown)
            return
        }
        switch cloudError.code {
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
}
