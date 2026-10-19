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
    @Published private(set) var store: MacSharedStore? {
        didSet {
            pausedPendingCountRevision &+= 1
            oldValue?.setLocalChangeHandler(nil)
            store?.setLocalChangeHandler { [weak self] in
                self?.refreshPausedPendingCount()
            }
            store?.setUndoEnabled(!Self.requiresAttention(syncStatus))
        }
    }
    enum StartupAccountState: Equatable { case idle, checking, waiting, unresolved }
    @Published private(set) var startupAccountState: StartupAccountState = .idle
    @Published private(set) var error: Error?
    @Published private(set) var syncStatus: SyncStatus = .disabled {
        didSet {
            store?.setUndoEnabled(!Self.requiresAttention(syncStatus))
        }
    }
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
    private var pausedPendingCountRevision: UInt64 = 0
    private var accountChangeObserver: NSObjectProtocol?
    private var accountValidationRevision: UInt64 = 0
    private var startupStatusHasBeenVisible = false
    private var startupRevision: UInt64 = 0
    private var startupTask: Swift.Task<Void, Never>?
    private var startupLocalOpenTask: Swift.Task<TildoneRepository, Error>?
    private var startupWaitTask: Swift.Task<Void, Never>?
    private var startupWaitNanoseconds: UInt64 = 2_000_000_000
#if DEBUG
    private var isolatedStartupResolver: (() async -> CloudAccountSnapshot)?
    private var isolatedStartupAccountRepository: ((UUID) async throws -> TildoneRepository)?
    private var isolatedStartupBeforePresentation: (() async -> Void)?
#endif
#if DEBUG
    private let qualificationRefreshFault = SyncQualificationFaultInjector()
    private var isolatedAccountSnapshot: CloudAccountSnapshot?
#endif

    init(
        transportStateStore: SyncTransportStateStore = SyncTransportStateStore(),
        defaults: UserDefaults = .standard
    ) {
        self.transportStateStore = transportStateStore
        self.localAdoptionStateStore = MacLocalAdoptionStateStore(defaults: defaults)
        self.noteLocationChoiceStore = MacNoteLocationChoiceStore(defaults: defaults)
        // Account privacy must not depend on a running CKSyncEngine. Pausing
        // destroys that coordinator, but the presented account can still change.
        accountChangeObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Swift.Task { @MainActor [weak self] in
                await self?.handleAccountChangeNotification()
            }
        }
    }

    deinit {
        startupTask?.cancel()
        startupWaitTask?.cancel()
        startupLocalOpenTask?.cancel()
        statusTask?.cancel()
        if let accountChangeObserver {
            NotificationCenter.default.removeObserver(accountChangeObserver)
        }
    }

#if DEBUG
    /// Hosted tests provide their own repositories and account identity. This
    /// cannot run in a normal app process or construct a sync coordinator.
    static func isolatedPresentation(
        localRepository: TildoneRepository,
        accountRepository: TildoneRepository,
        workspaceID: UUID,
        defaults: UserDefaults,
        status: SyncStatus,
        resolvedAccount: CloudAccountSnapshot? = nil
    ) async throws -> MacSharedStoreBootstrapper {
        precondition(isTestProcess && !transportEnabledByDefault)
        let model = MacSharedStoreBootstrapper(
            transportStateStore: SyncTransportStateStore(defaults: defaults),
            defaults: defaults
        )
        model.localRepository = localRepository
        model.accountRepository = accountRepository
        model.accountWorkspaceID = workspaceID
        model.isolatedAccountSnapshot = resolvedAccount ?? CloudAccountSnapshot(state: .available, workspaceID: workspaceID)
        model.hasResolvedAccountWorkspace = true
        model.transportState = .paused
        let choice = model.noteLocationChoiceStore.choice(for: workspaceID)
        let localHasContent = try await localRepository.hasSyncContent()
        let accountHasContent = try await accountRepository.hasSyncContent()
        model.hasUnadoptedLocalWorkspace = localHasContent && choice == nil
        model.hasNotesOnMacAndICloud = localHasContent && accountHasContent
        model.canAdoptLocalWorkspace = model.hasUnadoptedLocalWorkspace && !accountHasContent
        let usesAccount = MacWorkspaceSelectionPolicy.usesAccountWorkspace(
            localNeedsAdoption: model.hasUnadoptedLocalWorkspace, explicitChoice: choice
        )
        model.selectedRepository = usesAccount ? accountRepository : localRepository
        model.isUsingAccountWorkspace = usesAccount
        model.isUsingNotesOnMacByChoice = !usesAccount && choice == .thisMac
        let store = MacSharedStore(repository: usesAccount ? accountRepository : localRepository)
        try await store.reload()
        model.store = store
        model.syncStatus = status
        return model
    }
#endif

    static var transportEnabledByDefault: Bool {
        TransportDefaultPolicy.isEnabled(
            buildMode: compiledBuildMode,
            isTestProcess: isTestProcess
        )
    }

    static var cloudKitEnvironment: CloudKitEnvironment {
        compiledBuildMode.cloudKitEnvironment
    }

    var canControlTransport: Bool {
        Self.transportEnabledByDefault && hasResolvedAccountWorkspace && isUsingAccountWorkspace
    }

    var showsStartupAccountStatus: Bool {
        store == nil && error == nil &&
            (startupAccountState == .waiting || startupAccountState == .unresolved ||
             (startupAccountState == .checking && startupStatusHasBeenVisible))
    }

    var showsCoordinatorWindow: Bool { error != nil || showsStartupAccountStatus }

    func retryStartupAccount() {
        guard store == nil, error == nil,
              startupAccountState == .waiting || startupAccountState == .unresolved else { return }
        // Supersede the logical attempt. The SDK request may still reply later;
        // its revision cannot publish anything after this explicit retry.
        startupRevision &+= 1
        startupTask?.cancel()
        startupTask = nil
        startupWaitTask?.cancel()
        startupWaitTask = nil
        start()
    }

    /// Notifications supersede an unfinished startup before an old reply can
    /// choose a workspace. Application activation alone does not start another
    /// request while the authoritative account check is still pending.
    func handleAccountChangeNotification() async {
        if store == nil, startupTask != nil {
            startupRevision &+= 1
            startupTask?.cancel()
            startupTask = nil
            startupWaitTask?.cancel()
            startupWaitTask = nil
            startupStatusHasBeenVisible = true
            startupAccountState = .unresolved
            return
        }
        await revalidateAccountPresentation()
    }

    private func isCurrentStartup(_ revision: UInt64) -> Bool {
        startupRevision == revision && !Swift.Task.isCancelled
    }

    private var hasIsolatedStartupResolver: Bool {
#if DEBUG
        Self.isTestProcess && isolatedStartupResolver != nil
#else
        false
#endif
    }

#if DEBUG
    /// Explicit in-memory startup dependencies; no CloudKit container exists
    /// in this test path, and transport remains off in the hosted process.
    static func isolatedStartup(
        localRepository: TildoneRepository,
        resolveAccount: @escaping () async -> CloudAccountSnapshot,
        openAccount: @escaping (UUID) async throws -> TildoneRepository,
        defaults: UserDefaults,
        waitNanoseconds: UInt64 = 0,
        beforePresentation: (() async -> Void)? = nil
    ) -> MacSharedStoreBootstrapper {
        precondition(isTestProcess && !transportEnabledByDefault)
        let model = MacSharedStoreBootstrapper(
            transportStateStore: SyncTransportStateStore(defaults: defaults), defaults: defaults
        )
        model.localRepository = localRepository
        model.isolatedStartupResolver = resolveAccount
        model.isolatedStartupAccountRepository = openAccount
        model.isolatedStartupBeforePresentation = beforePresentation
        model.startupWaitNanoseconds = waitNanoseconds
        return model
    }
#endif

    private func resolveStartupAccount() async -> CloudAccountSnapshot {
#if DEBUG
        if Self.isTestProcess, let isolatedStartupResolver {
            return await isolatedStartupResolver()
        }
#endif
        let container = CKContainer(identifier: TildoneCloudSchema.containerIdentifier)
        cloudContainer = container
        return await CloudAccountResolver(environment: Self.cloudKitEnvironment).resolve(container: container)
    }

    private func openStartupAccount(_ workspaceID: UUID) async throws -> TildoneRepository {
#if DEBUG
        if Self.isTestProcess, let isolatedStartupAccountRepository {
            return try await isolatedStartupAccountRepository(workspaceID)
        }
#endif
        return try TildoneRepository(descriptor: .persistent(
            baseDirectory: Self.applicationSupportDirectory(), workspace: .account(workspaceID)
        ))
    }

    private func revealAccountWait(after revision: UInt64) {
        startupAccountState = .checking
        let delay = startupWaitNanoseconds
        startupWaitTask?.cancel()
        startupWaitTask = Swift.Task { [weak self] in
            do { try await Swift.Task.sleep(nanoseconds: delay) }
            catch { return }
            guard let self, isCurrentStartup(revision), startupAccountState == .checking else { return }
            startupStatusHasBeenVisible = true
            startupAccountState = .waiting
        }
    }

    func start() {
        guard store == nil, error == nil, startupTask == nil else { return }
        startupRevision &+= 1
        let revision = startupRevision
        startupAccountState = startupStatusHasBeenVisible ? .checking : .idle
        startupTask = Swift.Task {
            defer {
                if startupRevision == revision {
                    startupTask = nil
                    startupWaitTask?.cancel()
                    startupWaitTask = nil
                }
            }
            do {
                let local: TildoneRepository
                if let localRepository { local = localRepository }
                else {
                    // Reuse one local opening operation if an account-change
                    // notification supersedes startup while migration awaits.
                    if startupLocalOpenTask == nil {
                        startupLocalOpenTask = Swift.Task {
                            try await (Self.isTestProcess
                                ? TildoneRepository(descriptor: .inMemory())
                                : Self.openRepository())
                        }
                    }
                    local = try await startupLocalOpenTask!.value
                    guard isCurrentStartup(revision) else { return }
                    localRepository = local
                    startupLocalOpenTask = nil
                }
                if Self.isTestProcess && !hasIsolatedStartupResolver {
                    let next = MacSharedStore(repository: local)
                    try await next.prepareForPresentation(whileValid: { self.isCurrentStartup(revision) })
                    guard isCurrentStartup(revision) else { return }
                    selectedRepository = local
                    store = next
                    return
                }

                revealAccountWait(after: revision)
                let account = await resolveStartupAccount()
                guard isCurrentStartup(revision) else { return }
                startupWaitTask?.cancel()
                startupWaitTask = nil
                switch account.state {
                case .temporarilyUnavailable, .couldNotDetermine:
                    startupStatusHasBeenVisible = true
                    startupAccountState = .unresolved
                    return
                case .available where account.workspaceID == nil:
                    startupStatusHasBeenVisible = true
                    startupAccountState = .unresolved
                    return
                default: break
                }
                startupAccountState = .idle
                guard account.state == .available, let workspaceID = account.workspaceID else {
                    let next = MacSharedStore(repository: local)
                    try await next.prepareForPresentation(whileValid: { self.isCurrentStartup(revision) })
                    guard isCurrentStartup(revision) else { return }
                    syncStatus = Self.status(for: account.state)
                    selectedRepository = local
                    store = next
                    return
                }

                let accountRepository = try await openStartupAccount(workspaceID)
                guard isCurrentStartup(revision) else { return }
                try await Self.migrateSharedNoteColors(in: accountRepository)
                guard isCurrentStartup(revision) else { return }
                let localHasContent = try await local.hasSyncContent()
                guard isCurrentStartup(revision) else { return }
                let accountHasContent = try await accountRepository.hasSyncContent()
                guard isCurrentStartup(revision) else { return }
                let localFingerprint = localHasContent
                    ? try await MacNoteResolutionService.fingerprint(repository: local)
                    : nil
                guard isCurrentStartup(revision) else { return }
                let localNeedsAdoption = localFingerprint.map {
                    localAdoptionStateStore.fingerprint(for: workspaceID) != $0
                } ?? false
                let explicitChoice = noteLocationChoiceStore.choice(for: workspaceID)
                let unadopted = localNeedsAdoption && explicitChoice == nil
                let selected = MacWorkspaceSelectionPolicy.usesAccountWorkspace(
                    localNeedsAdoption: localNeedsAdoption, explicitChoice: explicitChoice
                ) ? accountRepository : local
#if DEBUG
                if Self.isTestProcess, let isolatedStartupBeforePresentation {
                    await isolatedStartupBeforePresentation()
                    guard isCurrentStartup(revision) else { return }
                }
#endif
                let next = MacSharedStore(repository: selected)
                try await next.prepareForPresentation(whileValid: { self.isCurrentStartup(revision) })
                guard isCurrentStartup(revision) else { return }
                // Publish the chosen identity and presentation together only
                // after every awaited preparation has kept this attempt current.
                self.accountRepository = accountRepository
                accountWorkspaceID = workspaceID
                hasResolvedAccountWorkspace = true
                transportState = transportStateStore.state(for: workspaceID)
                hasUnadoptedLocalWorkspace = unadopted
                canAdoptLocalWorkspace = MacWorkspaceSelectionPolicy.canAdoptLocalWorkspace(
                    localNeedsAdoption: unadopted, accountHasContent: accountHasContent
                )
                hasNotesOnMacAndICloud = localHasContent && accountHasContent
                selectedRepository = selected
                isUsingAccountWorkspace = selected === accountRepository
                isUsingNotesOnMacByChoice = selected === local && explicitChoice == .thisMac
#if DEBUG
                if Self.isTestProcess { isolatedAccountSnapshot = account }
#endif
                store = next
                guard Self.transportEnabledByDefault else { syncStatus = .disabled; return }
                guard selected === accountRepository else {
                    syncStatus = hasUnadoptedLocalWorkspace
                        ? SyncStatus(availability: .adoptionRequired, activity: .attentionNeeded) : .disabled
                    return
                }
                guard SyncTransportActivationPolicy.shouldActivate(
                    enabledByDefault: Self.transportEnabledByDefault, persistedState: transportState
                ) else {
                    let status = await pausedStatus(repository: accountRepository)
                    guard isCurrentStartup(revision), self.accountWorkspaceID == workspaceID else { return }
                    syncStatus = status
                    await SyncDiagnostics.inspectQualificationState(in: accountRepository, phase: .pausedLaunch)
                    return
                }
                guard let container = cloudContainer else { return }
                try await startCoordinator(
                    repository: accountRepository, workspaceID: workspaceID,
                    container: container, store: next
                )
            } catch {
                guard isCurrentStartup(revision) else { return }
                startupAccountState = .idle
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
        pausedPendingCountRevision &+= 1
        isTransportActionInProgress = true
        statusTask?.cancel()
        statusTask = nil
        store?.attachSyncCoordinator(nil)
        let coordinator = syncCoordinator
        syncCoordinator = nil
        if !Self.requiresAttention(syncStatus) {
            syncStatus = SyncStatus(
                availability: syncStatus.availability, activity: .paused,
                pendingMutationCount: syncStatus.pendingMutationCount,
                lastSuccessfulSyncAt: syncStatus.lastSuccessfulSyncAt,
                activeDeviceSummary: syncStatus.activeDeviceSummary, issue: syncStatus.issue
            )
        }
        Swift.Task {
            await coordinator?.pause()
            guard transportState == .paused, accountWorkspaceID == workspaceID,
                  accountRepository === repository else { return }
            refreshPausedPendingCount()
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
        SyncDiagnostics.boundary(.resumeRequested, count: 1)
        isTransportActionInProgress = true
        Swift.Task {
            let account = await CloudAccountResolver(environment: Self.cloudKitEnvironment)
                .resolve(container: container)
            guard account.state == .available, account.workspaceID == workspaceID else {
                invalidateForAccountChange()
                isTransportActionInProgress = false
                return
            }
            transportStateStore.set(.active, for: workspaceID)
            transportState = .active
            pausedPendingCountRevision &+= 1
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
        SyncDiagnostics.boundary(.explicitCheckpointRequested, count: 1)
        Swift.Task { await syncCoordinator.start() }
    }

    func refreshAccountAndSync() {
        Swift.Task { [weak self] in
            guard let self else { return }
            await revalidateAccountPresentation()
            syncNow()
        }
    }

    /// Checks identity without starting transport or changing durable work.
    /// Transient service uncertainty is not a confirmed account transition.
    func revalidateAccountPresentation() async {
        guard let workspaceID = accountWorkspaceID else { return }
        accountValidationRevision &+= 1
        let revision = accountValidationRevision
        let account = await resolveAccount(container: cloudContainer)
        guard accountValidationRevision == revision, accountWorkspaceID == workspaceID else { return }
        switch account.state {
        case .available:
            guard let currentID = account.workspaceID, currentID != workspaceID else { return }
        case .noAccount, .restricted:
            break
        case .temporarilyUnavailable, .couldNotDetermine:
            return
        }
        await stopCoordinatorForRepositoryTransition()
        guard accountValidationRevision == revision, accountWorkspaceID == workspaceID else { return }
        invalidateForAccountChange()
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
              let accountWorkspaceID else { return }
        let container = cloudContainer
        guard container != nil || hasIsolatedAccountContext else { return }
        store?.discardUndo()
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
            let sourceURL = legacySourceURL ?? LegacyStoreFileSet.releasedShippingURL()
            if !FileManager.default.fileExists(atPath: sourceURL.path) {
                try await MacLocalStoreActivationReceipt.validateOrCreate(
                    for: repository!, descriptor: descriptor
                )
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
        let environment = ProcessInfo.processInfo.environment
        return environment["TILDONE_TEST_USE_IN_MEMORY_SHARED"] == "1" ||
            ProcessInfo.processInfo.arguments.contains("--tildone-ui-test") ||
            environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestBundlePath"] != nil ||
            environment["XCInjectBundleInto"] != nil ||
            NSClassFromString("XCTestCase") != nil
    }

    private static var compiledBuildMode: TransportBuildMode {
#if DEBUG
        .debug
#else
        .release
#endif
    }

    private func resolveAccount(container: CKContainer?) async -> CloudAccountSnapshot {
#if DEBUG
        if Self.isTestProcess, let isolatedAccountSnapshot {
            return isolatedAccountSnapshot
        }
#endif
        guard let container else {
            return CloudAccountSnapshot(state: .couldNotDetermine, workspaceID: nil)
        }
        return await CloudAccountResolver(environment: Self.cloudKitEnvironment).resolve(container: container)
    }

    private var hasIsolatedAccountContext: Bool {
#if DEBUG
        Self.isTestProcess && isolatedAccountSnapshot != nil
#else
        false
#endif
    }

    private func revalidateAccount(workspaceID: UUID, container: CKContainer?) async -> Bool {
        let account = await resolveAccount(container: container)
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
        container: CKContainer?
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
        guard let container else { throw PersistenceError.invalidWorkspace }
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
        guard accountWorkspaceID == workspaceID, accountRepository === repository,
              selectedRepository === repository, self.store === store,
              transportState == .active else { return }
        let startupSessionRevision = startupRevision
        statusTask?.cancel()
#if DEBUG
        let qualificationRefreshFault = self.qualificationRefreshFault
#endif
        let coordinator = try await TildoneSyncCoordinator(
            repository: repository,
            container: container,
            clientPlatform: .mac,
            onAccountChange: { [weak self] change in
                guard change.requiresWorkspaceInvalidation else { return }
                Swift.Task { @MainActor in self?.invalidateForAccountChange() }
            },
            onRemoteChange: { [weak store, repository] remoteChange in
                try await MacRemoteRefreshHandler.run(
                    remoteChange: remoteChange,
                    invalidateUndo: { records in
                        await store?.discardUndoIfAffected(by: records)
                    },
                    migrateColors: {
                        try await Self.migrateSharedNoteColors(in: repository)
                    },
                    reloadSnapshots: {
#if DEBUG
                        try await qualificationRefreshFault.check(
                            in: repository, changedRecords: remoteChange.changedRecords
                        )
#endif
                        try await store?.reloadAfterRemoteChange()
                    }
                )
            }
        )
        guard startupRevision == startupSessionRevision,
              accountWorkspaceID == workspaceID, accountRepository === repository,
              selectedRepository === repository, self.store === store,
              transportState == .active else {
            await coordinator.pause()
            return
        }
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
        SyncDiagnostics.boundary(
            .macActiveAtCoordinatorStart,
            count: NSApplication.shared.isActive ? 1 : 0
        )
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

    private func refreshPausedPendingCount() {
        guard transportState == .paused, isUsingAccountWorkspace,
              let workspaceID = accountWorkspaceID, let repository = accountRepository,
              selectedRepository === repository else { return }
        // Never reconstruct transport just to display work saved while paused.
        pausedPendingCountRevision &+= 1
        let revision = pausedPendingCountRevision
        Swift.Task { [weak self] in
            let result: Result<Int, Error>
            do { result = .success(try await repository.pendingMutations().count) }
            catch { result = .failure(error) }
            guard let self, transportState == .paused, isUsingAccountWorkspace,
                  accountWorkspaceID == workspaceID, accountRepository === repository,
                  selectedRepository === repository, pausedPendingCountRevision == revision else { return }
            let current = syncStatus
            switch result {
            case let .success(pending):
                syncStatus = SyncStatus(
                    availability: current.availability, activity: current.activity,
                    pendingMutationCount: pending,
                    lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
                    activeDeviceSummary: current.activeDeviceSummary, issue: current.issue
                )
                await SyncDiagnostics.inspectQualificationState(in: repository, phase: .pausedMutation)
            case .failure:
                syncStatus = SyncStatus(
                    availability: current.availability, activity: .attentionNeeded,
                    pendingMutationCount: current.pendingMutationCount,
                    lastSuccessfulSyncAt: current.lastSuccessfulSyncAt,
                    activeDeviceSummary: current.activeDeviceSummary, issue: current.issue ?? .unknown
                )
            }
        }
    }

    private func invalidateForAccountChange() {
        startupRevision &+= 1
        startupTask?.cancel()
        startupTask = nil
        startupWaitTask?.cancel()
        startupWaitTask = nil
        startupAccountState = .idle
        accountValidationRevision &+= 1
        pausedPendingCountRevision &+= 1
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
