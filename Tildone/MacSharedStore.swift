//
//  MacSharedStore.swift
//  Tildone
//
//  Mac presentation adapter for immutable TildoneDomain snapshots.
//

import CloudKit
import CryptoKit
import Foundation
import SwiftUI
import TildoneDomain
import TildonePersistence
import TildoneSync

struct MacNoteSnapshot: Identifiable {
    let note: TildoneDomain.Note
    let tasks: [TildoneDomain.Task]

    var id: NoteID { note.id }
    var createdAt: Date { note.createdAt }
    var title: String? { note.title }
    var color: NoteColor { note.color }
    var isEmpty: Bool { tasks.isEmpty && title == nil }
    var isComplete: Bool { !tasks.isEmpty && tasks.allSatisfy(\.isCompleted) }
    var isDeletable: Bool { isEmpty || isComplete }
    var pendingTasks: [Task] { tasks.filter { !$0.isCompleted } }
    var completedAt: Date? {
        guard isComplete else { return nil }
        return tasks.compactMap(\.completedAt).max()
    }

    /// Retains the released window-autosave key for migrated notes.
    var legacyWindowKey: String { createdAt.ISO8601Format() }
}

@MainActor
final class MacSharedStore: ObservableObject {
    @Published private(set) var notes: [MacNoteSnapshot] = []

    private let repository: TildoneRepository
    private var syncCoordinator: TildoneSyncCoordinator?

    init(repository: TildoneRepository) {
        self.repository = repository
    }

    func attachSyncCoordinator(_ coordinator: TildoneSyncCoordinator?) {
        syncCoordinator = coordinator
    }

    func reload() async throws {
        let domainNotes = try await repository.visibleNotes()
        var snapshots: [MacNoteSnapshot] = []
        snapshots.reserveCapacity(domainNotes.count)
        for note in domainNotes {
            snapshots.append(MacNoteSnapshot(note: note, tasks: try await repository.orderedTasks(in: note.id)))
        }
        notes = snapshots
    }

    /// Removes empty windows left behind by an interrupted or forced quit before
    /// the desktop reconciles persisted notes. Completed notes are intentionally
    /// retained here so their visible grace period is owned by `Note`.
    func prepareForPresentation() async throws {
        try await reload()
        let emptyNoteIDs = notes.lazy.filter(\.isEmpty).map(\.id)
        guard !emptyNoteIDs.isEmpty else { return }
        for id in emptyNoteIDs {
            try await repository.deleteNote(id: id)
        }
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

    func note(_ id: NoteID) -> MacNoteSnapshot? {
        notes.first { $0.id == id }
    }

    func createNote(createdAt: Date = Date()) async throws -> MacNoteSnapshot {
        let id = NoteID()
        _ = try await repository.createNote(
            id: id,
            createdAt: createdAt,
            title: nil,
            color: NoteColor.current()
        )
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
        guard let note = note(id) else { throw PersistenceError.domainInvariant }
        return note
    }

    func renameNote(_ id: NoteID, to title: String?) async throws {
        _ = try await repository.renameNote(id: id, to: title, editedAt: Date())
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

    func setColor(_ color: NoteColor, for id: NoteID) async throws {
        _ = try await repository.setNoteColor(id: id, color: color)
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

    func addTask(
        to noteID: NoteID,
        text: String,
        insertingAt position: Int? = nil,
        createdAt: Date = Date()
    ) async throws -> Task {
        let tasks = try await repository.orderedTasks(in: noteID)
        let insertionIndex = min(max(position ?? tasks.count, 0), tasks.count)
        let lower = insertionIndex > 0 ? tasks[insertionIndex - 1].orderToken : nil
        let upper = insertionIndex < tasks.count ? tasks[insertionIndex].orderToken : nil
        let task = try await repository.addTask(
            id: TaskID(),
            to: noteID,
            createdAt: createdAt,
            text: text,
            orderToken: try OrderToken.between(lower, upper)
        )
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
        return task
    }

    func editTask(_ id: TaskID, text: String) async throws {
        _ = try await repository.editTask(id: id, text: text)
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

    func setTaskCompletion(_ id: TaskID, completed: Bool) async throws {
        _ = try await repository.setTaskCompletion(
            id: id,
            completion: completed ? .completed(at: Date()) : .incomplete
        )
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

    @discardableResult
    func moveTask(_ id: TaskID, in noteID: NoteID, to destination: Int) async throws -> Bool {
        var reordered = try await repository.orderedTasks(in: noteID)
        guard (0...reordered.count).contains(destination),
              let originalIndex = reordered.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let moved = reordered.remove(at: originalIndex)
        let adjustedDestination = destination > originalIndex ? destination - 1 : destination
        reordered.insert(moved, at: adjustedDestination)
        guard adjustedDestination != originalIndex else { return false }

        let lower = adjustedDestination > 0 ? reordered[adjustedDestination - 1].orderToken : nil
        let upper = adjustedDestination + 1 < reordered.count
            ? reordered[adjustedDestination + 1].orderToken
            : nil
        _ = try await repository.moveTask(id: id, to: try OrderToken.between(lower, upper))
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
        return true
    }

    func deleteTask(_ id: TaskID) async throws {
        try await repository.deleteTask(id: id)
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

    func deleteNote(_ id: NoteID) async throws {
        try await repository.deleteNote(id: id)
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

    func cleanEmptyTasks(in noteID: NoteID) async throws {
        for task in try await repository.orderedTasks(in: noteID) where task.text.isEmpty {
            try await repository.deleteTask(id: task.id)
        }
        try await reload()
        await syncCoordinator?.notifyLocalChanges()
    }

}

enum MacSharedStoreBootstrapError: Error, LocalizedError {
    case legacySourceMissing
    case unverifiedSharedStore
    case cloudAccountChanged

    var errorDescription: String? {
        switch self {
        case .legacySourceMissing:
            "The legacy Tildone store could not be found for migration."
        case .unverifiedSharedStore:
            "The shared Tildone store is not eligible for activation."
        case .cloudAccountChanged:
            "The iCloud account changed. Reopen Tildone to show the notes for the right account."
        }
    }
}

enum MacRemoteRefreshHandler {
    static func run(
        migrateColors: () async throws -> Void,
        reloadSnapshots: () async throws -> Void
    ) async throws {
        try await migrateColors()
        try await reloadSnapshots()
    }
}

private struct MacLocalAdoptionStateStore {
    private static let keyPrefix = "localWorkspaceAdoptionFingerprint."

    let defaults: UserDefaults

    func fingerprint(for workspaceID: UUID) -> String? {
        defaults.string(forKey: Self.keyPrefix + workspaceID.uuidString.lowercased())
    }

    func setFingerprint(_ fingerprint: String, for workspaceID: UUID) {
        defaults.set(fingerprint, forKey: Self.keyPrefix + workspaceID.uuidString.lowercased())
    }
}

enum MacWorkspaceSelectionPolicy {
    /// An unadopted local workspace remains active even when the account
    /// workspace already contains data. A workspace-mode change follows only
    /// an explicit, eligible adoption confirmation.
    static func usesAccountWorkspace(localNeedsAdoption: Bool) -> Bool {
        !localNeedsAdoption
    }

    static func canAdoptLocalWorkspace(
        localNeedsAdoption: Bool,
        accountHasContent: Bool
    ) -> Bool {
        localNeedsAdoption && !accountHasContent
    }
}

@MainActor
final class MacSharedStoreBootstrapper: ObservableObject {
    @Published private(set) var store: MacSharedStore?
    @Published private(set) var error: Error?
    @Published private(set) var syncStatus: SyncStatus = .disabled
    @Published private(set) var transportState: SyncTransportState = .active
    @Published private(set) var hasResolvedAccountWorkspace = false
    @Published private(set) var isUsingAccountWorkspace = false
    @Published private(set) var hasUnadoptedLocalWorkspace = false
    @Published private(set) var canAdoptLocalWorkspace = false
    @Published private(set) var adoptionCompletedAwaitingRelaunch = false
    @Published private(set) var isTransportActionInProgress = false

    private let transportStateStore: SyncTransportStateStore
    private let localAdoptionStateStore: MacLocalAdoptionStateStore
    private var localRepository: TildoneRepository?
    private var accountRepository: TildoneRepository?
    private var selectedRepository: TildoneRepository?
    private var accountWorkspaceID: UUID?
    private var cloudContainer: CKContainer?
    private var syncCoordinator: TildoneSyncCoordinator?
    private var statusTask: Swift.Task<Void, Never>?

    init(
        transportStateStore: SyncTransportStateStore = SyncTransportStateStore(),
        defaults: UserDefaults = .standard
    ) {
        self.transportStateStore = transportStateStore
        self.localAdoptionStateStore = MacLocalAdoptionStateStore(defaults: defaults)
    }

    deinit { statusTask?.cancel() }

    static var transportEnabledByDefault: Bool {
        TransportDefaultPolicy.isEnabled(
            buildMode: compiledBuildMode,
            isTestProcess: isTestProcess
        )
    }

    var canControlTransport: Bool {
        Self.transportEnabledByDefault && hasResolvedAccountWorkspace && isUsingAccountWorkspace
    }

    func start() {
        guard store == nil, error == nil else { return }
        Swift.Task {
            do {
                let localRepository = try await (Self.isTestProcess
                    ? TildoneRepository(descriptor: .inMemory())
                    : Self.openRepository())
                self.localRepository = localRepository
                if Self.isTestProcess {
                    let store = MacSharedStore(repository: localRepository)
                    try await store.prepareForPresentation()
                    self.selectedRepository = localRepository
                    self.store = store
                    return
                }

                let container = CKContainer(identifier: TildoneCloudSchema.containerIdentifier)
                self.cloudContainer = container
                let account = await CloudAccountResolver().resolve(container: container)
                guard account.state == .available, let workspaceID = account.workspaceID else {
                    self.syncStatus = Self.status(for: account.state)
                    let store = MacSharedStore(repository: localRepository)
                    try await store.prepareForPresentation()
                    self.selectedRepository = localRepository
                    self.store = store
                    return
                }

                let base = try Self.applicationSupportDirectory()
                let accountRepository = try TildoneRepository(descriptor: .persistent(
                    baseDirectory: base,
                    workspace: .account(workspaceID)
                ))
                try await Self.migrateSharedNoteColors(in: accountRepository)
                self.accountRepository = accountRepository
                self.accountWorkspaceID = workspaceID
                self.hasResolvedAccountWorkspace = true
                self.transportState = transportStateStore.state(for: workspaceID)

                let localHasContent = try await localRepository.hasSyncContent()
                let accountHasContent = try await accountRepository.hasSyncContent()
                let localFingerprint = localHasContent
                    ? try await Self.contentFingerprint(repository: localRepository)
                    : nil
                let localNeedsAdoption = localFingerprint.map {
                    localAdoptionStateStore.fingerprint(for: workspaceID) != $0
                } ?? false
                self.hasUnadoptedLocalWorkspace = localNeedsAdoption
                self.canAdoptLocalWorkspace = MacWorkspaceSelectionPolicy.canAdoptLocalWorkspace(
                    localNeedsAdoption: localNeedsAdoption,
                    accountHasContent: accountHasContent
                )
                let selectedRepository = MacWorkspaceSelectionPolicy.usesAccountWorkspace(
                    localNeedsAdoption: localNeedsAdoption
                ) ? accountRepository : localRepository
                self.selectedRepository = selectedRepository
                self.isUsingAccountWorkspace = selectedRepository === accountRepository

                let store = MacSharedStore(repository: selectedRepository)
                try await store.prepareForPresentation()
                self.store = store
                guard Self.transportEnabledByDefault else {
                    self.syncStatus = .disabled
                    return
                }
                guard selectedRepository === accountRepository else {
                    self.syncStatus = SyncStatus(
                        availability: .adoptionRequired,
                        activity: .attentionNeeded
                    )
                    return
                }
                guard SyncTransportActivationPolicy.shouldActivate(
                    enabledByDefault: Self.transportEnabledByDefault,
                    persistedState: transportState
                ) else {
                    self.syncStatus = await pausedStatus(repository: accountRepository)
                    return
                }
                try await startCoordinator(
                    repository: accountRepository,
                    workspaceID: workspaceID,
                    container: container,
                    store: store
                )
            } catch {
                self.error = error
            }
        }
    }

    func pauseTransport() {
        guard canControlTransport,
              transportState == .active,
              let workspaceID = accountWorkspaceID,
              let repository = accountRepository else { return }
        transportStateStore.set(.paused, for: workspaceID)
        transportState = .paused
        isTransportActionInProgress = true
        statusTask?.cancel()
        statusTask = nil
        store?.attachSyncCoordinator(nil)
        let coordinator = syncCoordinator
        syncCoordinator = nil
        Swift.Task {
            await coordinator?.pause()
            let paused = await pausedStatus(repository: repository)
            if !Self.requiresAttention(syncStatus) { syncStatus = paused }
            isTransportActionInProgress = false
        }
    }

    func resumeTransport() {
        guard canControlTransport,
              transportState == .paused,
              let workspaceID = accountWorkspaceID,
              let repository = accountRepository,
              let container = cloudContainer,
              let store else { return }
        isTransportActionInProgress = true
        Swift.Task {
            let account = await CloudAccountResolver().resolve(container: container)
            guard account.state == .available, account.workspaceID == workspaceID else {
                invalidateForAccountChange()
                isTransportActionInProgress = false
                return
            }
            transportStateStore.set(.active, for: workspaceID)
            transportState = .active
            do {
                try await startCoordinator(
                    repository: repository,
                    workspaceID: workspaceID,
                    container: container,
                    store: store
                )
            } catch {
                syncStatus = SyncStatus(
                    availability: .available,
                    activity: .attentionNeeded,
                    pendingMutationCount: (try? await repository.pendingMutations().count) ?? 0,
                    lastSuccessfulSyncAt: syncStatus.lastSuccessfulSyncAt,
                    issue: .unknown
                )
            }
            isTransportActionInProgress = false
        }
    }

    func syncNow() {
        guard transportState == .active, let syncCoordinator else { return }
        Swift.Task { await syncCoordinator.start() }
    }

    /// Confirmation is owned by the calling UI. This operation only copies an
    /// existing local-only workspace into an empty account workspace, retains
    /// the source, and waits for relaunch before selecting the account mode.
    func adoptLocalWorkspaceAfterConfirmation() {
        guard canAdoptLocalWorkspace,
              !isTransportActionInProgress,
              let localRepository,
              let accountRepository,
              let accountWorkspaceID else { return }
        isTransportActionInProgress = true
        Swift.Task {
            do {
                guard !(try await accountRepository.hasSyncContent()) else {
                    canAdoptLocalWorkspace = false
                    throw PersistenceError.workspaceMismatch
                }
                try await accountRepository.adoptSyncContent(
                    notes: try await localRepository.allSyncNotes(),
                    tasks: try await localRepository.allSyncTasks(),
                    at: Date()
                )
                try await localRepository.markCloudSeedingBegun(at: Date())
                let fingerprint = try await Self.contentFingerprint(repository: localRepository)
                localAdoptionStateStore.setFingerprint(fingerprint, for: accountWorkspaceID)
                canAdoptLocalWorkspace = false
                hasUnadoptedLocalWorkspace = false
                adoptionCompletedAwaitingRelaunch = true
            } catch {
                syncStatus = SyncStatus(
                    availability: .adoptionRequired,
                    activity: .attentionNeeded,
                    issue: .unknown
                )
            }
            isTransportActionInProgress = false
        }
    }

    private static func contentFingerprint(repository: TildoneRepository) async throws -> String {
        struct Snapshot: Encodable {
            let notes: [TildoneDomain.Note]
            let tasks: [TildoneDomain.Task]
        }

        let snapshot = Snapshot(
            notes: try await repository.allSyncNotes().sorted { $0.id < $1.id },
            tasks: try await repository.allSyncTasks().sorted { $0.id < $1.id }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(snapshot))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func openRepository(
        baseDirectory: URL? = nil,
        legacySourceURL: URL? = nil
    ) async throws -> TildoneRepository {
        let repository = try await openRepositoryBeforeColorMigration(
            baseDirectory: baseDirectory,
            legacySourceURL: legacySourceURL
        )
        try await migrateSharedNoteColors(in: repository)
        return repository
    }

    private static func openRepositoryBeforeColorMigration(
        baseDirectory: URL?,
        legacySourceURL: URL?
    ) async throws -> TildoneRepository {
        let base = try (baseDirectory ?? applicationSupportDirectory())
        let descriptor = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .localOnly)
        var repository: TildoneRepository? = try TildoneRepository(descriptor: descriptor)

        do {
            let migration = try await repository!.legacyMigrationSnapshot()
            if migration.phase == .eligibleForCutover,
               migration.activationState == .verifiedNotActivated,
               !migration.cloudSeedingEverBegun {
                _ = try await repository!.activateVerifiedLegacyMigration(at: Date())
                return repository!
            }
            guard migration.phase == .eligibleForCutover,
                  migration.activationState == .activated else {
                repository = nil
                return try await migrateAndActivate(
                    descriptor: descriptor,
                    sourceURL: legacySourceURL ?? LegacyStoreFileSet.releasedShippingURL()
                )
            }
            return repository!
        } catch LegacyMigrationPersistenceError.stateMissing {
            let existingNotes = try await repository!.visibleNotes()
            let sourceURL = legacySourceURL ?? LegacyStoreFileSet.releasedShippingURL()
            if !FileManager.default.fileExists(atPath: sourceURL.path) {
                guard existingNotes.isEmpty else { throw MacSharedStoreBootstrapError.unverifiedSharedStore }
                return repository!
            }
            repository = nil
            return try await migrateAndActivate(descriptor: descriptor, sourceURL: sourceURL)
        }
    }

    private static func migrateSharedNoteColors(in repository: TildoneRepository) async throws {
        let notes = try await repository.allSyncNotes()
        let localColors = Dictionary(uniqueKeysWithValues: notes.compactMap { note in
            NoteColor.legacyLocalColor(for: note.id).map { (note.id, $0) }
        })
        try await repository.migrateMissingNoteColors(
            colorsByNoteID: localColors,
            defaultColor: NoteColor.current(),
            authority: .legacyMac
        )
    }

    private static func migrateAndActivate(
        descriptor: PersistenceStoreDescriptor,
        sourceURL: URL
    ) async throws -> TildoneRepository {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw MacSharedStoreBootstrapError.legacySourceMissing
        }
        let destination = try TildoneRepository.storeURL(for: descriptor)
        guard let destination else { throw PersistenceError.invalidStoreLocation }
        let result = try await LegacyMigrationCoordinator(
            sourceURL: sourceURL,
            destinationURL: destination
        ).migrate()
        guard result.eligibleForCutover,
              !result.activated,
              !result.cloudSeedingEverBegun else {
            throw MacSharedStoreBootstrapError.unverifiedSharedStore
        }
        let repository = try TildoneRepository(descriptor: descriptor)
        _ = try await repository.activateVerifiedLegacyMigration(at: Date())
        return repository
    }

    private static func applicationSupportDirectory() throws -> URL {
        guard let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PersistenceError.invalidStoreLocation
        }
        return directory
    }

    private static var isTestProcess: Bool {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        return environment["TILDONE_TEST_USE_IN_MEMORY_SHARED"] == "1" ||
            ProcessInfo.processInfo.arguments.contains("--tildone-ui-test") ||
            environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestBundlePath"] != nil ||
            environment["XCInjectBundleInto"] != nil ||
            NSClassFromString("XCTestCase") != nil
#else
        false
#endif
    }

    private static var compiledBuildMode: TransportBuildMode {
#if DEBUG
        .debug
#else
        .release
#endif
    }

    private func startCoordinator(
        repository: TildoneRepository,
        workspaceID: UUID,
        container: CKContainer,
        store: MacSharedStore
    ) async throws {
        statusTask?.cancel()
        let coordinator = try await TildoneSyncCoordinator(
            repository: repository,
            container: container,
            clientPlatform: .mac,
            onAccountChange: { [weak self] change in
                guard change.requiresWorkspaceInvalidation else { return }
                Swift.Task { @MainActor in self?.invalidateForAccountChange() }
            },
            onRemoteChange: { [weak store, repository] in
                try await MacRemoteRefreshHandler.run(
                    migrateColors: {
                        try await Self.migrateSharedNoteColors(in: repository)
                    },
                    reloadSnapshots: {
                        try await store?.reload()
                    }
                )
            }
        )
        syncCoordinator = coordinator
        store.attachSyncCoordinator(coordinator)
        statusTask = Swift.Task { [weak self, weak coordinator] in
            guard let coordinator else { return }
            for await status in await coordinator.statusModel.updates() {
                guard !Swift.Task.isCancelled else { return }
                guard self?.accountWorkspaceID == workspaceID,
                      self?.transportState == .active else { return }
                self?.syncStatus = status
            }
        }
        await coordinator.start()
    }

    private func pausedStatus(repository: TildoneRepository) async -> SyncStatus {
        SyncStatus(
            availability: .available,
            activity: .paused,
            pendingMutationCount: (try? await repository.pendingMutations().count) ?? 0,
            lastSuccessfulSyncAt: syncStatus.lastSuccessfulSyncAt,
            activeDeviceSummary: syncStatus.activeDeviceSummary,
            issue: nil
        )
    }

    private func invalidateForAccountChange() {
        statusTask?.cancel()
        statusTask = nil
        store?.attachSyncCoordinator(nil)
        syncCoordinator = nil
        selectedRepository = nil
        isUsingAccountWorkspace = false
        store = nil
        syncStatus = SyncStatus(
            availability: .accountChanged,
            activity: .attentionNeeded,
            issue: .accountChanged
        )
        error = MacSharedStoreBootstrapError.cloudAccountChanged
    }

    private static func requiresAttention(_ status: SyncStatus) -> Bool {
        status.activity == .attentionNeeded || [
            .adoptionRequired,
            .accountChanged,
            .zoneResetRequired,
            .incompatibleRemoteData
        ].contains(status.availability)
    }

    private static func status(for account: CloudAccountState) -> SyncStatus {
        switch account {
        case .available:
            SyncStatus(availability: .available, activity: .idle)
        case .noAccount:
            SyncStatus(availability: .noAccount, activity: .idle)
        case .restricted:
            SyncStatus(availability: .restricted, activity: .attentionNeeded, issue: .permission)
        case .temporarilyUnavailable, .couldNotDetermine:
            SyncStatus(
                availability: .temporarilyUnavailable,
                activity: .offline,
                issue: .service
            )
        }
    }
}
