//
//  TildoneiOSTests.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import XCTest
import CloudKit
import TildoneDomain
import TildonePersistence
import TildoneSync
@testable import Tildone

@MainActor
final class TildoneiOSTests: XCTestCase {
    func testIPhoneTransportIsDisabledUnderTests() {
        XCTAssertFalse(TildoneiOSSyncBootstrapper.featureEnabled)
    }

    func testNotesArePresentedInMeaningfulEditOrderWithUntitledFallback() async throws {
        let workspace = UUID()
        let repository = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspace)))
        let model = try await makeModel(repository: repository)
        let older = try await repository.createNote(
            id: NoteID(), createdAt: Date(timeIntervalSince1970: 100), title: nil
        )
        let newer = try await repository.createNote(
            id: NoteID(), createdAt: Date(timeIntervalSince1970: 200), title: "Later"
        )
        try await model.reloadNotes()

        XCTAssertEqual(model.notes.map(\.id), [newer.id, older.id])
        XCTAssertEqual(SyncStatusPresentation.title(for: .disabled), "Sync is disabled")
        XCTAssertEqual(older.title, nil)
    }

    func testCreateRenameAndDeleteNoteUsesRepositoryLifecycle() async throws {
        let model = try await makeModel()
        let note = try await model.createNote()
        try await model.rename(noteID: note.id, title: "  Groceries  ")
        XCTAssertEqual(model.notes.first?.title, "Groceries")

        try await model.setColor(noteID: note.id, color: .blue)
        XCTAssertEqual(model.notes.first?.color, .blue)

        try await model.delete(noteID: note.id)
        XCTAssertTrue(model.notes.isEmpty)
    }

    func testTaskEditingCompletionDeletionAndOrderingUseDomainCommands() async throws {
        let model = try await makeModel()
        let note = try await model.createNote(title: "Checklist")
        let createdFirst = try await model.addTask(noteID: note.id, text: "First", after: [])
        let first = try XCTUnwrap(createdFirst)
        let createdSecond = try await model.addTask(noteID: note.id, text: "Second", after: [first])
        let second = try XCTUnwrap(createdSecond)

        try await model.edit(taskID: second.id, text: "Changed")
        try await model.setCompletion(taskID: first.id, completed: true)
        XCTAssertEqual(model.taskSummaries[note.id]?.completedCount, 1)
        XCTAssertEqual(model.taskSummaries[note.id]?.totalCount, 2)
        XCTAssertEqual(model.taskListTexts[note.id], "First, Changed")
        try await model.move(taskID: second.id, in: [first, second], from: IndexSet(integer: 1), to: 0)
        let reordered = try await model.tasks(in: note.id)
        XCTAssertEqual(reordered.map(\.id), [second.id, first.id])
        XCTAssertEqual(reordered.first?.text, "Changed")
        XCTAssertTrue(reordered.last?.isCompleted == true)

        try await model.delete(taskID: first.id)
        let remaining = try await model.tasks(in: note.id)
        XCTAssertEqual(remaining.map(\.id), [second.id])
    }

    func testRemoteStyleRefreshDoesNotDuplicateRowsAndHidesTombstones() async throws {
        let workspace = UUID()
        let repository = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspace)))
        let model = try await makeModel(repository: repository)
        try await model.openForTesting(workspaceID: workspace)
        let note = try await repository.createNote(id: NoteID(), createdAt: Date(), title: "From Mac")

        try await model.reloadNotes()
        try await model.reloadNotes() // Redelivery/reload is idempotent for presentation.
        XCTAssertEqual(model.notes.map(\.id), [note.id])

        try await repository.deleteNote(id: note.id)
        try await model.reloadNotes()
        XCTAssertTrue(model.notes.isEmpty)
    }

    func testTaskOnlyRemoteDeliveryAdvancesContentRevision() async throws {
        let workspace = UUID()
        let repository = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspace)))
        let model = try await makeModel(repository: repository)
        let note = try await repository.createNote(id: NoteID(), createdAt: Date(), title: "Remote")
        try await model.reloadNotes()
        let notesBeforeTask = model.notes
        let revisionBeforeTask = model.contentRevision

        let stamp = VersionStamp(logicalCounter: 100, replicaID: ReplicaID())
        let remoteTask = TildoneDomain.Task(
            id: TaskID(),
            noteID: note.id,
            createdAt: Date(),
            text: "Arrived separately",
            textVersion: stamp,
            completionVersion: stamp,
            orderToken: try OrderToken(rawValue: "m"),
            orderVersion: stamp,
            lifecycleVersion: stamp
        )
        _ = try await repository.mergeRemoteTask(remoteTask, at: Date())
        try await model.reloadNotes()

        XCTAssertEqual(model.notes, notesBeforeTask)
        XCTAssertGreaterThan(model.contentRevision, revisionBeforeTask)
        let tasks = try await model.tasks(in: note.id)
        XCTAssertEqual(tasks.map(\.id), [remoteTask.id])
    }

    func testOfflineAndAttentionStatesRemainUnderstandable() async throws {
        let model = try await makeModel()
        let note = try await model.createNote()
        _ = try await model.addTask(noteID: note.id, text: "Works offline", after: [])
        let tasks = try await model.tasks(in: note.id)
        XCTAssertEqual(tasks.count, 1)

        for availability in [SyncAvailability.noAccount, .restricted, .adoptionRequired, .zoneResetRequired, .incompatibleRemoteData] {
            let status = SyncStatus(availability: availability, activity: .attentionNeeded)
            XCTAssertFalse(SyncStatusPresentation.title(for: status).isEmpty)
            XCTAssertNotNil(SyncStatusPresentation.detail(for: status))
        }

        let malformed = SyncStatus(
            availability: .available,
            activity: .attentionNeeded,
            issue: .malformedRemoteRecord
        )
        XCTAssertEqual(SyncStatusPresentation.title(for: malformed), "iCloud needs attention")
        XCTAssertEqual(
            SyncStatusPresentation.detail(for: malformed),
            "Some notes from iCloud could not be read. You can keep editing."
        )

        let paused = SyncStatus(availability: .available, activity: .paused)
        XCTAssertEqual(SyncStatusPresentation.title(for: paused), "Sync is paused")
        XCTAssertEqual(SyncStatusPresentation.symbol(for: paused), "pause.circle")
        let pausedDetail = try XCTUnwrap(SyncStatusPresentation.detail(for: paused))
        XCTAssertFalse(pausedDetail.localizedCaseInsensitiveContains("workspace"))

        let available = SyncStatus(
            availability: .available,
            activity: .idle,
            activeDeviceSummary: SyncDeviceSummary(
                currentPlatform: .iPhone,
                otherMacCount: 2
            )
        )
        XCTAssertEqual(available.activeDeviceCount, 3)
        XCTAssertEqual(
            SyncDeviceSummaryPresentation.title(
                for: try XCTUnwrap(available.activeDeviceSummary),
                locale: Locale(identifier: "en_US")
            ),
            "This iPhone and 2 Macs"
        )
        XCTAssertFalse(SyncDeviceSummaryPresentation.shouldShowMacUpgradeGuidance(
            for: try XCTUnwrap(available.activeDeviceSummary)
        ))

        let noMac = SyncDeviceSummary(currentPlatform: .iPhone)
        XCTAssertTrue(SyncDeviceSummaryPresentation.shouldShowMacUpgradeGuidance(for: noMac))
        XCTAssertEqual(
            SyncDeviceSummaryPresentation.macUpgradeGuidance(
                locale: Locale(identifier: "en_US")
            ),
            "To see existing Mac notes here, update Tildone on your Mac to version 2.0 or later. Both devices must use the same iCloud account."
        )
    }

    func testAccountChangeDropsOldWorkspaceImmediately() async throws {
        let workspaceA = UUID()
        let workspaceB = UUID()
        let repositoryA = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceA)))
        let repositoryB = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceB)))
        let model = TildoneiOSApplicationModel(repositoryFactory: { workspace in
            switch workspace {
            case let .account(id) where id == workspaceA: return repositoryA
            case let .account(id) where id == workspaceB: return repositoryB
            default: throw PersistenceError.workspaceMismatch
            }
        }, synchronizationEnabled: false)
        try await model.openForTesting(workspaceID: workspaceA)
        _ = try await model.createNote(title: "Account A")
        XCTAssertFalse(model.notes.isEmpty)

        model.present(status: SyncStatus(availability: .accountChanged, activity: .attentionNeeded))
        XCTAssertFalse(model.hasWorkspace)
        XCTAssertTrue(model.notes.isEmpty)

        try await model.openForTesting(workspaceID: workspaceB)
        XCTAssertTrue(model.notes.isEmpty)
    }

    func testPausedTransportKeepsWorkspaceCRUDAndIsolatesAccountPreference() async throws {
        let suiteName = "TildoneiOSTransportTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let transportStore = SyncTransportStateStore(defaults: defaults)
        let workspaceA = UUID()
        let workspaceB = UUID()
        let repositoryA = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(workspaceA))
        )
        let repositoryB = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(workspaceB))
        )
        let model = TildoneiOSApplicationModel(
            repositoryFactory: { workspace in
                switch workspace {
                case let .account(id) where id == workspaceA: return repositoryA
                case let .account(id) where id == workspaceB: return repositoryB
                default: throw PersistenceError.workspaceMismatch
                }
            },
            synchronizationEnabled: true,
            transportStateStore: transportStore
        )

        try await model.openForTesting(workspaceID: workspaceA)
        model.pauseTransport()
        XCTAssertEqual(model.transportState, .paused)
        XCTAssertEqual(model.syncStatus.activity, .paused)
        XCTAssertTrue(model.hasWorkspace)
        _ = try await model.createNote(title: "Stays local while paused")
        let pendingA = try await repositoryA.pendingMutations()
        XCTAssertEqual(model.notes.count, 1)
        XCTAssertFalse(pendingA.isEmpty)

        try await model.openForTesting(workspaceID: workspaceB)
        XCTAssertEqual(model.transportState, .active)
        XCTAssertTrue(model.notes.isEmpty)

        try await model.openForTesting(workspaceID: workspaceA)
        XCTAssertEqual(model.transportState, .paused)
        XCTAssertEqual(model.notes.count, 1)
    }

    func testWorkspaceResolutionRevalidatesAccountIdentity() async throws {
        let workspaceA = UUID()
        let workspaceB = UUID()
        let repositoryA = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceA)))
        let repositoryB = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceB)))
        var account = CloudAccountSnapshot(state: .available, workspaceID: workspaceA)
        let model = TildoneiOSApplicationModel(
            repositoryFactory: { workspace in
                switch workspace {
                case let .account(id) where id == workspaceA: return repositoryA
                case let .account(id) where id == workspaceB: return repositoryB
                default: throw PersistenceError.workspaceMismatch
                }
            },
            accountResolver: { account },
            synchronizationEnabled: false
        )

        await model.resolveAndOpenCurrentWorkspace()
        _ = try await model.createNote(title: "Private to A")
        XCTAssertEqual(model.notes.count, 1)

        account = CloudAccountSnapshot(state: .available, workspaceID: workspaceB)
        await model.resolveAndOpenCurrentWorkspace()
        XCTAssertTrue(model.hasWorkspace)
        XCTAssertTrue(model.notes.isEmpty)
    }

    func testNotesListReentersExistingNotesWithoutTypedPathNavigation() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("TildoneiOS/Views/Notes/NotesListView.swift")
        let listSource = try String(contentsOf: sourceURL, encoding: .utf8)
        let noteRowURL = sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent("NoteListRow.swift")
        let noteRowSource = try String(contentsOf: noteRowURL, encoding: .utf8)
        let gaugeURL = sourceURL
            .deletingLastPathComponent()
            .appendingPathComponent("NoteCompletionGauge.swift")
        let gaugeSource = try String(contentsOf: gaugeURL, encoding: .utf8)

        XCTAssertTrue(listSource.contains("NavigationLink {"))
        XCTAssertTrue(listSource.contains(".navigationDestination(item: $presentedNoteID)"))
        XCTAssertFalse(listSource.contains("NavigationStack(path: $path)"))
        XCTAssertFalse(listSource.contains(".navigationDestination(for: NoteID.self)"))
        XCTAssertTrue(noteRowSource.contains("NoteCompletionGauge"))
        XCTAssertFalse(noteRowSource.contains("lastMeaningfulEditAt, style: .relative"))
        XCTAssertTrue(gaugeSource.contains(".gaugeStyle(.accessoryCircular)"))
    }

    /// Opt-in, read-only Development diagnostic hosted by the signed-in iOS
    /// simulator. Exact record lookup avoids requiring a queryable CloudKit
    /// index and never modifies the frozen Development schema or record data.
    func testDevelopmentCloudKitNoteLookupWhenExplicitlyEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TILDONE_RUN_DEVELOPMENT_CLOUDKIT_LOOKUP"] == "1" else {
            throw XCTSkip("Development CloudKit lookup is explicitly opt-in")
        }
        let recordName = try XCTUnwrap(
            environment["TILDONE_DEVELOPMENT_RECORD_NAME"],
            "Set the exact Development TDNote record name, including its note- prefix"
        )
        let container = CKContainer(identifier: TildoneCloudSchema.containerIdentifier)
        guard try await container.accountStatus() == .available else {
            throw XCTSkip("A Development iCloud account is required")
        }

        let recordID = CKRecord.ID(
            recordName: recordName,
            zoneID: TildoneCloudSchema.zoneID
        )
        let results = try await container.privateCloudDatabase.records(for: [recordID])
        let record = try XCTUnwrap(results[recordID]).get()
        let decoded = try CloudKitRecordMapper().syncRecord(from: record)
        guard case let .note(note) = decoded else {
            return XCTFail("Expected a TDNote record")
        }

        let displayedTitle = note.title ?? "<nil>"
        print(
            "Development TDNote: title=\(displayedTitle) " +
            "color=\(note.color.rawValue) " +
            "titleCounter=\(note.titleVersion.logicalCounter) " +
            "colorCounter=\(note.colorVersion.logicalCounter)"
        )
        if let expectedTitle = environment["TILDONE_DEVELOPMENT_EXPECTED_TITLE"] {
            XCTAssertEqual(note.title, expectedTitle)
        }
        if let expectedColor = environment["TILDONE_DEVELOPMENT_EXPECTED_COLOR"] {
            XCTAssertEqual(note.color.rawValue, expectedColor)
        }
    }

    private func makeModel(repository: TildoneRepository? = nil) async throws -> TildoneiOSApplicationModel {
        let workspace = UUID()
        let repository = try repository ?? TildoneRepository(descriptor: .inMemory(workspace: .account(workspace)))
        let model = TildoneiOSApplicationModel(
            repositoryFactory: { _ in repository },
            synchronizationEnabled: false
        )
        try await model.openForTesting(workspaceID: workspace)
        return model
    }
}
