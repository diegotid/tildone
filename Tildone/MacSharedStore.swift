//
//  MacSharedStore.swift
//  Tildone
//
//  Mac presentation adapter for immutable TildoneDomain snapshots.
//

import CloudKit
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
    var isEmpty: Bool { tasks.isEmpty && title == nil }
    var isComplete: Bool { !tasks.isEmpty && tasks.allSatisfy(\.isCompleted) }
    var isDeletable: Bool { isEmpty || isComplete }
    var pendingTasks: [Task] { tasks.filter { !$0.isCompleted } }

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

    func attachSyncCoordinator(_ coordinator: TildoneSyncCoordinator) {
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

    func note(_ id: NoteID) -> MacNoteSnapshot? {
        notes.first { $0.id == id }
    }

    func createNote(createdAt: Date = Date()) async throws -> MacNoteSnapshot {
        let id = NoteID()
        _ = try await repository.createNote(id: id, createdAt: createdAt, title: nil)
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

    func deleteDeletableNotes() async throws {
        for note in notes where note.isDeletable {
            try await repository.deleteNote(id: note.id)
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
            "The iCloud account changed. Relaunch Tildone to open the correct private workspace."
        }
    }
}

@MainActor
final class MacSharedStoreBootstrapper: ObservableObject {
    @Published private(set) var store: MacSharedStore?
    @Published private(set) var error: Error?
    @Published private(set) var syncStatus: SyncStatus = .disabled

    func start() {
        guard store == nil, error == nil else { return }
        Swift.Task {
            do {
                let localRepository = try await (Self.isTestProcess
                    ? TildoneRepository(descriptor: .inMemory())
                    : Self.openRepository())
                if !Self.syncFeatureEnabled || Self.isTestProcess {
                    let store = MacSharedStore(repository: localRepository)
                    try await store.reload()
                    self.store = store
                    return
                }

                let container = CKContainer(identifier: TildoneCloudSchema.containerIdentifier)
                let account = await CloudAccountResolver().resolve(container: container)
                guard account.state == .available, let workspaceID = account.workspaceID else {
                    self.syncStatus = Self.status(for: account.state)
                    let store = MacSharedStore(repository: localRepository)
                    try await store.reload()
                    self.store = store
                    return
                }

                let base = try Self.applicationSupportDirectory()
                let accountRepository = try TildoneRepository(descriptor: .persistent(
                    baseDirectory: base,
                    workspace: .account(workspaceID)
                ))
                if try await localRepository.hasSyncContent() {
                    if Self.localWorkspaceAdoptionEnabled {
                        try await accountRepository.adoptSyncContent(
                            notes: try await localRepository.allSyncNotes(),
                            tasks: try await localRepository.allSyncTasks(),
                            at: Date()
                        )
                        try await localRepository.markCloudSeedingBegun(at: Date())
                    } else if !(try await accountRepository.hasSyncContent()) {
                        self.syncStatus = SyncStatus(
                            availability: .adoptionRequired,
                            activity: .idle
                        )
                        let store = MacSharedStore(repository: localRepository)
                        try await store.reload()
                        self.store = store
                        return
                    }
                }

                let store = MacSharedStore(repository: accountRepository)
                try await store.reload()
                let coordinator = try await TildoneSyncCoordinator(
                    repository: accountRepository,
                    container: container,
                    onAccountChange: { [weak self] change in
                        guard change.requiresWorkspaceInvalidation else { return }
                        Swift.Task { @MainActor in
                            self?.store = nil
                            self?.error = MacSharedStoreBootstrapError.cloudAccountChanged
                        }
                    },
                    onRemoteChange: { [weak store] in
                        try? await store?.reload()
                    }
                )
                store.attachSyncCoordinator(coordinator)
                self.store = store
                Swift.Task { [weak self] in
                    for await status in await coordinator.statusModel.updates() {
                        self?.syncStatus = status
                    }
                }
                await coordinator.start()
            } catch {
                self.error = error
            }
        }
    }

    static func openRepository(
        baseDirectory: URL? = nil,
        legacySourceURL: URL? = nil
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


    private static var syncFeatureEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["TILDONE_ENABLE_CLOUDKIT_SYNC"] == "1"
#else
        false
#endif
    }

    /// Explicit development-only approval for the unresolved local-only to
    /// account-workspace adoption policy. Merely signing into iCloud never
    /// uploads local-only notes.
    private static var localWorkspaceAdoptionEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["TILDONE_ALLOW_LOCAL_WORKSPACE_ADOPTION"] == "1"
#else
        false
#endif
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
