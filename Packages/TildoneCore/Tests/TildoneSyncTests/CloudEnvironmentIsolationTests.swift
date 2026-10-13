import CloudKit
import XCTest
import TildoneDomain
import TildonePersistence
@testable import TildoneSync

/// Local synthetic stores only. No account resolution or CloudKit operation.
final class CloudEnvironmentIsolationTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private struct Snapshot: Equatable {
        let notes: [TildoneDomain.Note]
        let tasks: [TildoneDomain.Task]
        let pending: [PendingMutationSnapshot]
        let workspace: WorkspaceSnapshot
    }

    private func workspace(_ environment: CloudKitEnvironment) -> UUID {
        CloudAccountResolver.opaqueWorkspaceID(
            containerIdentifier: TildoneCloudSchema.containerIdentifier,
            userRecordName: "same-private-user",
            environment: environment
        )
    }

    func testDevelopmentKeepsHistoricalIdentityWhileProductionHasItsOwnNamespace() throws {
        let historicalID = try XCTUnwrap(UUID(uuidString: "70ee2ce0-3b5e-5589-8620-ce2407eaeba1"))
        XCTAssertEqual(workspace(.development), historicalID)
        XCTAssertEqual(CloudAccountResolver.opaqueWorkspaceID(
            containerIdentifier: TildoneCloudSchema.containerIdentifier,
            userRecordName: "same-private-user"
        ), historicalID)
        XCTAssertNotEqual(workspace(.production), historicalID)
        XCTAssertEqual(workspace(.production), workspace(.production))
        XCTAssertNotEqual(workspace(.production), CloudAccountResolver.opaqueWorkspaceID(
            containerIdentifier: TildoneCloudSchema.containerIdentifier,
            userRecordName: "another-private-user", environment: .production
        ))
    }

    func testReleaseSelectsProductionWithoutEnablingTransport() {
        XCTAssertEqual(TransportBuildMode.debug.cloudKitEnvironment, .development)
        XCTAssertEqual(TransportBuildMode.release.cloudKitEnvironment, .production)
        for testProcess in [false, true] {
            XCTAssertFalse(TransportDefaultPolicy.isEnabled(buildMode: .release, isTestProcess: testProcess))
        }
        XCTAssertFalse(TransportDefaultPolicy.isEnabled(buildMode: .debug, isTestProcess: true))
    }

    func testSamePrivateUserCannotShareStoresEngineStateOrTransportPreferences() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TildoneEnvironmentIsolation-\(UUID().uuidString)", isDirectory: true
        )
        let suite = "TildoneEnvironmentIsolation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let development = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .account(workspace(.development)))
        let production = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .account(workspace(.production)))
        let developmentURL = try XCTUnwrap(TildoneRepository.storeURL(for: development))
        let productionURL = try XCTUnwrap(TildoneRepository.storeURL(for: production))
        XCTAssertNotEqual(developmentURL, productionURL)
        XCTAssertTrue(developmentURL.path.hasSuffix("accounts/70ee2ce0-3b5e-5589-8620-ce2407eaeba1/tildone-shared.sqlite"))
        let before = try await populateDevelopment(development)

        let preference = SyncTransportStateStore(defaults: defaults)
        preference.set(.paused, for: workspace(.development))
        XCTAssertEqual(preference.state(for: workspace(.production)), .active)
        preference.set(.paused, for: workspace(.production))
        preference.set(.active, for: workspace(.development))
        XCTAssertEqual(preference.state(for: workspace(.production)), .paused)

        let emptyProduction = try await read(production)
        XCTAssertTrue(emptyProduction.notes.isEmpty)
        XCTAssertTrue(emptyProduction.tasks.isEmpty)
        XCTAssertTrue(emptyProduction.pending.isEmpty)
        XCTAssertNil(emptyProduction.workspace.futureSyncEngineState)
        XCTAssertNotEqual(emptyProduction.workspace.replicaID, before.workspace.replicaID)

        // Even an explicitly supplied wrong path must reject its ownership.
        do {
            _ = try TildoneRepository(descriptor: .temporaryMigration(
                storeURL: developmentURL, workspace: .account(workspace(.production))
            ))
            XCTFail("Production identity must not admit a Development store")
        } catch {
            XCTAssertEqual(error as? PersistenceError, .workspaceMismatch)
        }
        let after = try await read(development)
        XCTAssertTrue(after == before, "Development content, versions, pending work and engine state must stay unchanged")
    }

    func testExplicitSyntheticTransferRetriesAfterPartialCopyAndReopensWithoutDevelopmentReceipts() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TildoneEnvironmentTransfer-\(UUID().uuidString)", isDirectory: true
        )
        let development = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .account(workspace(.development)))
        let production = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .account(workspace(.production)))
        let source = try await populateDevelopment(development)
        let firstNote = try XCTUnwrap(source.notes.first)
        try await writePartialTransfer(firstNote, to: production)
        let partial = try await read(production)
        XCTAssertEqual(partial.notes.count, 1)
        XCTAssertNil(partial.workspace.futureSyncEngineState)

        try await transfer(source, to: production)
        let firstReopen = try await read(production)
        XCTAssertTrue(firstReopen.notes == source.notes, "All note fields and version stamps must survive the copy")
        XCTAssertTrue(firstReopen.tasks == source.tasks, "All task fields, formatting, indentation and tombstones must survive the copy")
        XCTAssertNil(firstReopen.workspace.futureSyncEngineState)
        XCTAssertNotEqual(firstReopen.workspace.replicaID, source.workspace.replicaID)
        XCTAssertEqual(firstReopen.pending.count, source.notes.count + source.tasks.count)
        XCTAssertTrue(firstReopen.pending.allSatisfy { $0.attemptCount == 0 && $0.lastAttemptAt == nil })
        XCTAssertTrue(Set(firstReopen.pending.map(\.id)).isDisjoint(with: Set(source.pending.map(\.id))))

        try await transfer(source, to: production)
        let retriedReopen = try await read(production)
        XCTAssertTrue(retriedReopen.notes == firstReopen.notes)
        XCTAssertTrue(retriedReopen.tasks == firstReopen.tasks)
        XCTAssertEqual(retriedReopen.pending.count, firstReopen.pending.count)
        XCTAssertNil(retriedReopen.workspace.futureSyncEngineState)
        let sourceReopen = try await read(development)
        XCTAssertTrue(sourceReopen == source, "Transfer must retain the original source and its full pending/engine state")
    }

    private func populateDevelopment(_ descriptor: PersistenceStoreDescriptor) async throws -> Snapshot {
        let date = self.date
        let repository = try TildoneRepository(descriptor: descriptor, now: { date })
        let note = NoteID(UUID())
        let memo = NoteID(UUID())
        let deleted = NoteID(UUID())
        _ = try await repository.createNote(id: note, createdAt: date, title: "Synthetic transfer")
        _ = try await repository.setNoteColor(id: note, color: .purple)
        let task = TaskID(UUID())
        _ = try await repository.addTask(id: task, to: note, createdAt: date,
            text: "Synthetic café 你好", orderToken: OrderToken(rawValue: "m"))
        _ = try await repository.editTask(id: task, richText: RichText(text: "Synthetic café 你好", spans: [
            .init(range: .init(location: 0, length: 9), attributes: .init(styles: [.bold, .underline]))
        ]))
        let completed = TaskID(UUID())
        _ = try await repository.addTask(id: completed, to: note, createdAt: date,
            text: "Completed child", orderToken: OrderToken(rawValue: "t"), indentLevel: 1)
        _ = try await repository.setTaskCompletion(id: completed, completion: .completed(at: date))
        _ = try await repository.createNote(id: memo, createdAt: date, title: "Synthetic memo")
        _ = try await repository.addTask(id: TaskID(UUID()), to: memo, createdAt: date,
            text: "Memo body", orderToken: OrderToken(rawValue: "m"))
        _ = try await repository.setNoteKind(id: memo, kind: .singleTask)
        _ = try await repository.setSingleMemoFont(id: memo, font: .permanentMarker)
        _ = try await repository.createNote(id: deleted, createdAt: date, title: "Synthetic tombstone")
        _ = try await repository.addTask(id: TaskID(UUID()), to: deleted, createdAt: date,
            text: "Deleted child", orderToken: OrderToken(rawValue: "m"))
        try await repository.deleteNote(id: deleted)
        let pending = try await repository.pendingMutations()
        let attempted = try XCTUnwrap(pending.first)
        try await repository.recordMutationAttempt(id: attempted.id, at: date)
        var state = SyncPersistentState()
        state.zoneCreated = true
        state.engineSerialization = Data("synthetic-development-cursor".utf8)
        let domainNote = try await repository.note(id: note)
        try state.storeSystemFields(for: CloudKitRecordMapper().record(from: .note(domainNote)))
        try await repository.storeFutureSyncEngineState(state.encoded())
        return try await snapshot(repository)
    }

    private func read(_ descriptor: PersistenceStoreDescriptor) async throws -> Snapshot {
        let repository = try TildoneRepository(descriptor: descriptor)
        return try await snapshot(repository)
    }

    private func snapshot(_ repository: TildoneRepository) async throws -> Snapshot {
        try await Snapshot(notes: repository.allSyncNotes(), tasks: repository.allSyncTasks(),
            pending: repository.pendingMutations(includeSuperseded: true), workspace: repository.workspaceSnapshot())
    }

    private func writePartialTransfer(_ note: TildoneDomain.Note, to descriptor: PersistenceStoreDescriptor) async throws {
        let repository = try TildoneRepository(descriptor: descriptor)
        _ = try await repository.mergeRemoteNote(note, at: date)
        try await repository.enqueueAllSyncContent(at: date)
    }

    private func transfer(_ source: Snapshot, to descriptor: PersistenceStoreDescriptor) async throws {
        let repository = try TildoneRepository(descriptor: descriptor)
        try await repository.adoptSyncContent(notes: source.notes, tasks: source.tasks, at: date)
    }
}
