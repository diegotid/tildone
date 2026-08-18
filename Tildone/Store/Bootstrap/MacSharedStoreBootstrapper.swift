//
//  MacSharedStoreBootstrapper.swift
//  Tildone
//

import CloudKit
import Foundation
import SwiftUI
import TildoneDomain
import TildonePersistence
import TildoneSync

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
    @Published private(set) var hasNotesOnMacAndICloud = false
    @Published private(set) var isUsingNotesOnMacByChoice = false
    @Published private(set) var didJustChooseNotesOnMac = false
    @Published private(set) var resolutionActionFailed = false
    @Published private(set) var isTransportActionInProgress = false

    private let transportStateStore: SyncTransportStateStore
    private let localAdoptionStateStore: MacLocalAdoptionStateStore
    private let noteLocationChoiceStore: MacNoteLocationChoiceStore
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
        self.noteLocationChoiceStore = MacNoteLocationChoiceStore(defaults: defaults)
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
                    ? try await MacNoteResolutionService.fingerprint(repository: localRepository)
                    : nil
                let localNeedsAdoption = localFingerprint.map {
                    localAdoptionStateStore.fingerprint(for: workspaceID) != $0
                } ?? false
                let explicitChoice = noteLocationChoiceStore.choice(for: workspaceID)
                self.hasUnadoptedLocalWorkspace = localNeedsAdoption && explicitChoice == nil
                self.canAdoptLocalWorkspace = MacWorkspaceSelectionPolicy.canAdoptLocalWorkspace(
                    localNeedsAdoption: hasUnadoptedLocalWorkspace,
                    accountHasContent: accountHasContent
                )
                self.hasNotesOnMacAndICloud = localHasContent && accountHasContent
                let selectedRepository = MacWorkspaceSelectionPolicy.usesAccountWorkspace(
                    localNeedsAdoption: localNeedsAdoption,
                    explicitChoice: explicitChoice
                ) ? accountRepository : localRepository
                self.selectedRepository = selectedRepository
                self.isUsingAccountWorkspace = selectedRepository === accountRepository
                self.isUsingNotesOnMacByChoice = selectedRepository === localRepository &&
                    explicitChoice == .thisMac

                let store = MacSharedStore(repository: selectedRepository)
                try await store.prepareForPresentation()
                self.store = store
                guard Self.transportEnabledByDefault else {
                    self.syncStatus = .disabled
                    return
                }
                guard selectedRepository === accountRepository else {
                    self.syncStatus = hasUnadoptedLocalWorkspace
                        ? SyncStatus(availability: .adoptionRequired, activity: .attentionNeeded)
                        : .disabled
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

    /// Confirmation is owned by the calling UI. Every action preserves both
    /// repositories. Combining uses the established deterministic merge rules;
    /// choosing a location only changes which repository is presented.
    func resolveNotesAfterConfirmation(
        _ action: MacNoteResolutionAction,
        requiresEmptyAccount: Bool = false
    ) {
        guard !isTransportActionInProgress,
              let localRepository,
              let accountRepository,
              let accountWorkspaceID,
              let container = cloudContainer else { return }
        isTransportActionInProgress = true
        didJustChooseNotesOnMac = false
        resolutionActionFailed = false
        let wasUsingAccountWorkspace = isUsingAccountWorkspace
        Swift.Task {
            do {
                switch action {
                case .useThisMac:
                    try await selectRepository(
                        localRepository,
                        isAccountRepository: false,
                        workspaceID: accountWorkspaceID,
                        container: container
                    )
                    noteLocationChoiceStore.set(.thisMac, for: accountWorkspaceID)
                    didJustChooseNotesOnMac = true
                case .useICloud:
                    guard await revalidateAccount(workspaceID: accountWorkspaceID, container: container) else {
                        isTransportActionInProgress = false
                        return
                    }
                    try await selectRepository(
                        accountRepository,
                        isAccountRepository: true,
                        workspaceID: accountWorkspaceID,
                        container: container
                    )
                    noteLocationChoiceStore.set(.iCloud, for: accountWorkspaceID)
                case .combine:
                    guard await revalidateAccount(workspaceID: accountWorkspaceID, container: container) else {
                        isTransportActionInProgress = false
                        return
                    }
                    await stopCoordinatorForRepositoryTransition()
                    if requiresEmptyAccount, try await accountRepository.hasSyncContent() {
                        hasNotesOnMacAndICloud = try await localRepository.hasSyncContent()
                        canAdoptLocalWorkspace = false
                        throw MacNoteResolutionError.accountNoLongerEmpty
                    }
                    let fingerprint = try await MacNoteResolutionService.combine(
                        localRepository: localRepository,
                        accountRepository: accountRepository,
                        at: Date()
                    )
                    localAdoptionStateStore.setFingerprint(fingerprint, for: accountWorkspaceID)
                    hasNotesOnMacAndICloud = true
                    try await selectRepository(
                        accountRepository,
                        isAccountRepository: true,
                        workspaceID: accountWorkspaceID,
                        container: container
                    )
                    noteLocationChoiceStore.set(.iCloud, for: accountWorkspaceID)
                }
                hasUnadoptedLocalWorkspace = false
                canAdoptLocalWorkspace = false
            } catch {
                resolutionActionFailed = true
                if wasUsingAccountWorkspace {
                    try? await selectRepository(
                        accountRepository,
                        isAccountRepository: true,
                        workspaceID: accountWorkspaceID,
                        container: container
                    )
                }
                if !isUsingNotesOnMacByChoice && !isUsingAccountWorkspace {
                    syncStatus = SyncStatus(
                        availability: .adoptionRequired,
                        activity: .attentionNeeded,
                        issue: .unknown
                    )
                }
            }
            isTransportActionInProgress = false
        }
    }

    func dismissNotesOnMacNotice() {
        didJustChooseNotesOnMac = false
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

    private func revalidateAccount(workspaceID: UUID, container: CKContainer) async -> Bool {
        let account = await CloudAccountResolver().resolve(container: container)
        guard account.state == .available, account.workspaceID == workspaceID else {
            await stopCoordinatorForRepositoryTransition()
            invalidateForAccountChange()
            return false
        }
        return true
    }

    private func stopCoordinatorForRepositoryTransition() async {
        statusTask?.cancel()
        statusTask = nil
        store?.attachSyncCoordinator(nil)
        let coordinator = syncCoordinator
        syncCoordinator = nil
        await coordinator?.stop()
    }

    private func selectRepository(
        _ repository: TildoneRepository,
        isAccountRepository: Bool,
        workspaceID: UUID,
        container: CKContainer
    ) async throws {
        let nextStore: MacSharedStore
        if selectedRepository === repository, let store {
            nextStore = store
        } else {
            nextStore = MacSharedStore(repository: repository)
        }
        // A user-requested location change must only reload the selected
        // repository. It must not run startup cleanup or mutate either set.
        try await nextStore.reload()

        await stopCoordinatorForRepositoryTransition()
        selectedRepository = repository
        isUsingAccountWorkspace = isAccountRepository
        isUsingNotesOnMacByChoice = !isAccountRepository
        store = nextStore

        guard isAccountRepository else {
            syncStatus = .disabled
            return
        }
        guard Self.transportEnabledByDefault else {
            syncStatus = .disabled
            return
        }
        guard SyncTransportActivationPolicy.shouldActivate(
            enabledByDefault: Self.transportEnabledByDefault,
            persistedState: transportState
        ) else {
            syncStatus = await pausedStatus(repository: repository)
            return
        }
        try await startCoordinator(
            repository: repository,
            workspaceID: workspaceID,
            container: container,
            store: nextStore
        )
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
        let wasPresentingAccount = isUsingAccountWorkspace
        accountRepository = nil
        accountWorkspaceID = nil
        hasResolvedAccountWorkspace = false
        hasUnadoptedLocalWorkspace = false
        canAdoptLocalWorkspace = false
        hasNotesOnMacAndICloud = false
        isUsingAccountWorkspace = false
        if wasPresentingAccount {
            selectedRepository = nil
            store = nil
            error = MacSharedStoreBootstrapError.cloudAccountChanged
        }
        syncStatus = SyncStatus(
            availability: .accountChanged,
            activity: .attentionNeeded,
            issue: .accountChanged
        )
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
