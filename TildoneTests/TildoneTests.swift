//
//  TildoneTests.swift
//  TildoneTests
//

import CloudKit
import SwiftUI
import XCTest
import TildoneDomain
import TildonePersistence
import TildoneSync
@testable import Tildone

final class TildoneTests: XCTestCase {
    func testCheckboxDoesNotRetainParentOwnedCompletionAsLocalState() {
        let storedPropertyNames = Set(
            Mirror(reflecting: Checkbox(checked: false)).children.compactMap(\.label)
        )

        XCTAssertTrue(
            storedPropertyNames.contains("checked"),
            "Completion must remain an ordinary parent-owned view input."
        )
        XCTAssertFalse(
            storedPropertyNames.contains("_checked"),
            "Duplicating completion in @State prevents remote parent updates from redrawing the checkbox."
        )
    }

    @MainActor
    func testPrimarySceneUsesSingleUniqueCoordinatorWindow() {
        let scene = TildonePrimaryScene { EmptyView() }
        let bodyType = String(reflecting: type(of: scene.body))

        XCTAssertTrue(
            bodyType.contains("SwiftUI.Window<"),
            "The process-wide note-window coordinator must use SwiftUI.Window."
        )
        XCTAssertFalse(
            bodyType.contains("SwiftUI.WindowGroup<"),
            "WindowGroup permits multiple coordinator instances on macOS."
        )
    }

    func testMacSharedStoreRoutesCRUDThroughDomainRepository() async throws {
        let repository = try TildoneRepository(
            descriptor: .inMemory(),
            replicaID: ReplicaID(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!),
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let store = await MainActor.run { MacSharedStore(repository: repository) }

        let note = try await store.createNote(createdAt: Date(timeIntervalSince1970: 100))
        try await store.renameNote(note.id, to: "Title")
        let last = try await store.addTask(to: note.id, text: "Last")
        let first = try await store.addTask(to: note.id, text: "First", insertingAt: 0)
        try await store.setTaskCompletion(first.id, completed: true)
        try await store.editTask(last.id, text: "Changed")

        let loadedSnapshot = await MainActor.run { store.note(note.id) }
        let snapshot = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(snapshot.title, "Title")
        XCTAssertEqual(snapshot.tasks.map(\.text), ["First", "Changed"])
        XCTAssertEqual(snapshot.pendingTasks.map(\.id), [last.id])

        try await store.deleteTask(first.id)
        try await store.deleteTask(last.id)
        try await store.renameNote(note.id, to: nil)
        let loadedEmpty = await MainActor.run { store.note(note.id) }
        let empty = try XCTUnwrap(loadedEmpty)
        XCTAssertTrue(empty.isDeletable)
        try await store.deleteNote(note.id)
        let remaining = try await repository.visibleNotes()
        XCTAssertTrue(remaining.isEmpty)
    }

    /// Opt-in smoke test hosted by the signed development Mac app so the test
    /// inherits the real CloudKit entitlement. The normal suite is fully local.
    func testDevelopmentCloudKitRoundTripWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["TILDONE_RUN_DEVELOPMENT_CLOUDKIT_TESTS"] == "1" else {
            throw XCTSkip("Development CloudKit integration is explicitly opt-in")
        }
        let container = CKContainer(identifier: TildoneCloudSchema.containerIdentifier)
        guard try await container.accountStatus() == .available else {
            throw XCTSkip("A development iCloud account is required")
        }

        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneID: TildoneCloudSchema.zoneID)
        let zoneResults = try await database.modifyRecordZones(saving: [zone], deleting: [])
        _ = try zoneResults.saveResults[TildoneCloudSchema.zoneID]?.get()

        let timestamp = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let stamp = VersionStamp(logicalCounter: 1, replicaID: ReplicaID())
        let note = Note(
            id: NoteID(),
            createdAt: timestamp,
            title: "Stage 8 synthetic integration record",
            titleVersion: stamp,
            lifecycleVersion: stamp,
            lastMeaningfulEditAt: timestamp,
            lastMeaningfulEditVersion: stamp
        )
        let mapper = CloudKitRecordMapper()
        let record = mapper.record(from: .note(note))
        do {
            let saved = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )
            _ = try saved.saveResults[record.recordID]?.get()
            let fetched = try await database.records(for: [record.recordID])
            let fetchedRecord = try XCTUnwrap(fetched[record.recordID]).get()
            XCTAssertEqual(try mapper.syncRecord(from: fetchedRecord), .note(note))
            _ = try await database.modifyRecords(saving: [], deleting: [record.recordID])
        } catch {
            _ = try? await database.modifyRecords(saving: [], deleting: [record.recordID])
            throw error
        }
    }
}
