//
//  MacSharedStore.swift
//  Tildone
//
//  Mac presentation adapter for immutable TildoneDomain snapshots.
//

import Foundation
import SwiftUI
import TildoneDomain
import TildonePersistence

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

    init(repository: TildoneRepository) {
        self.repository = repository
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
        guard let note = note(id) else { throw PersistenceError.domainInvariant }
        return note
    }

    func renameNote(_ id: NoteID, to title: String?) async throws {
        _ = try await repository.renameNote(id: id, to: title, editedAt: Date())
        try await reload()
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
        return task
    }

    func editTask(_ id: TaskID, text: String) async throws {
        _ = try await repository.editTask(id: id, text: text)
        try await reload()
    }

    func setTaskCompletion(_ id: TaskID, completed: Bool) async throws {
        _ = try await repository.setTaskCompletion(
            id: id,
            completion: completed ? .completed(at: Date()) : .incomplete
        )
        try await reload()
    }

    func deleteTask(_ id: TaskID) async throws {
        try await repository.deleteTask(id: id)
        try await reload()
    }

    func deleteNote(_ id: NoteID) async throws {
        try await repository.deleteNote(id: id)
        try await reload()
    }

    func cleanEmptyTasks(in noteID: NoteID) async throws {
        for task in try await repository.orderedTasks(in: noteID) where task.text.isEmpty {
            try await repository.deleteTask(id: task.id)
        }
        try await reload()
    }

    func deleteDeletableNotes() async throws {
        for note in notes where note.isDeletable {
            try await repository.deleteNote(id: note.id)
        }
        try await reload()
    }
}

enum MacSharedStoreBootstrapError: Error, LocalizedError {
    case legacySourceMissing
    case unverifiedSharedStore

    var errorDescription: String? {
        switch self {
        case .legacySourceMissing:
            "The legacy Tildone store could not be found for migration."
        case .unverifiedSharedStore:
            "The shared Tildone store is not eligible for activation."
        }
    }
}

@MainActor
final class MacSharedStoreBootstrapper: ObservableObject {
    @Published private(set) var store: MacSharedStore?
    @Published private(set) var error: Error?

    func start() {
        guard store == nil, error == nil else { return }
        Swift.Task {
            do {
                let repository = try await (Self.isTestProcess
                    ? TildoneRepository(descriptor: .inMemory())
                    : Self.openRepository())
                let store = MacSharedStore(repository: repository)
                try await store.reload()
                self.store = store
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
                  migration.activationState == .activated,
                  !migration.cloudSeedingEverBegun else {
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
}
