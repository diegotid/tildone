import CloudKit
import XCTest
import TildoneDomain
import TildonePersistence
@testable import TildoneSync

/// In-memory synthetic repository and SDK value types only. No container or engine.
final class RecoverySchedulingTests: XCTestCase {
    func testUnfetchedRequiredZoneCannotCommitRecoveryCursor() async throws {
        let repository = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(UUID()))
        )
        var initial = SyncPersistentState()
        initial.zoneCreated = true
        initial.fullReconciliationRequired = true
        try await repository.storeFutureSyncEngineState(initial.encoded())
        let state = SyncCoordinatorState(persistent: initial, repository: repository)
        await state.beginFetch()
        try await state.updateEncodedEngineSerialization(Data([4, 5, 6]))
        // A database-only fetch completion is not a full custom-zone download.
        _ = try await state.completeFetch()
        let retained = await state.snapshot()
        let saved = SyncPersistentState(data: try await repository.workspaceSnapshot().futureSyncEngineState)
        XCTAssertTrue(retained.fullReconciliationRequired)
        XCTAssertNil(retained.engineSerialization)
        XCTAssertEqual(saved, initial)
    }

    func testLateCompletionAfterPauseCannotCommitStagedCursor() async throws {
        let repository = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(UUID()))
        )
        var initial = SyncPersistentState()
        initial.zoneCreated = true
        initial.completedReconciliationVersion = SyncPersistentState.currentReconciliationVersion
        initial.engineSerialization = Data([1, 2, 3])
        try await repository.storeFutureSyncEngineState(initial.encoded())
        let state = SyncCoordinatorState(persistent: initial, repository: repository)
        await state.beginFetch()
        try await state.updateEncodedEngineSerialization(Data([4, 5, 6]))
        await state.freeze()
        _ = try await state.completeFetch()
        let saved = SyncPersistentState(data: try await repository.workspaceSnapshot().futureSyncEngineState)
        XCTAssertEqual(saved, initial)
    }

    func testFailedRecoveryRetainsEditsTombstonesReceiptsThenReleasesAfterSuccessfulCommit() async throws {
        let repository = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(UUID()))
        )
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let note = try await repository.createNote(id: NoteID(), createdAt: date, title: "Recovery fixture")
        let task = try await repository.addTask(id: TaskID(), to: note.id, createdAt: date,
                                               text: "Retain this deletion", orderToken: OrderToken(rawValue: "m"))
        try await repository.deleteTask(id: task.id)
        _ = try await repository.renameNote(id: note.id, to: "Retain this edit", editedAt: date)
        let pendingBefore = try await repository.pendingMutations(includeSuperseded: true)
        let tasksBefore = try await repository.allSyncTasks()
        let notesBefore = try await repository.allSyncNotes()
        let workspaceBefore = try await repository.workspaceSnapshot()
        let receipt = CloudKitRecordMapper().clientRecord(replicaID: workspaceBefore.replicaID, platform: .mac)
        var initial = SyncPersistentState()
        initial.zoneCreated = true
        initial.fullReconciliationRequired = true
        try initial.storeSystemFields(for: receipt)
        try await repository.storeFutureSyncEngineState(initial.encoded())
        let state = SyncCoordinatorState(persistent: initial, repository: repository)
        let beforeAllowed = await state.canScheduleRecordChanges()
        XCTAssertFalse(beforeAllowed)

        await state.beginFetch()
        try await state.updateEncodedEngineSerialization(Data([4, 5, 6]))
        await state.recordRequiredZoneFetchCompletion(succeeded: false)
        // Even a later success in the same failed pass cannot hide the failure.
        await state.recordRequiredZoneFetchCompletion(succeeded: true)
        let failedCommitted = try await state.completeFetch()
        XCTAssertFalse(failedCommitted)
        let failedAllowed = await state.canScheduleRecordChanges()
        XCTAssertFalse(failedAllowed)
        let persistedFailure = SyncPersistentState(data: try await repository.workspaceSnapshot().futureSyncEngineState)
        XCTAssertEqual(persistedFailure, initial)
        let reopened = SyncCoordinatorState(persistent: persistedFailure, repository: repository)
        let reopenedAllowed = await reopened.canScheduleRecordChanges()
        XCTAssertFalse(reopenedAllowed)

        await state.beginFetch()
        try await state.updateEncodedEngineSerialization(Data([7, 8, 9]))
        await state.recordRequiredZoneFetchCompletion(succeeded: true)
        let beforeCommitAllowed = await state.canScheduleRecordChanges()
        XCTAssertFalse(beforeCommitAllowed)
        let committed = try await state.completeFetch()
        XCTAssertTrue(committed)
        let afterAllowed = await state.canScheduleRecordChanges()
        XCTAssertTrue(afterAllowed)
        let saved = SyncPersistentState(data: try await repository.workspaceSnapshot().futureSyncEngineState)
        XCTAssertFalse(saved.fullReconciliationRequired)
        XCTAssertEqual(saved.engineSerialization, Data([7, 8, 9]))
        XCTAssertEqual(saved.systemFieldsByRecordName, initial.systemFieldsByRecordName)
        let pendingAfter = try await repository.pendingMutations(includeSuperseded: true)
        let tasksAfter = try await repository.allSyncTasks()
        let notesAfter = try await repository.allSyncNotes()
        let workspaceAfter = try await repository.workspaceSnapshot()
        XCTAssertEqual(pendingAfter, pendingBefore)
        XCTAssertEqual(tasksAfter, tasksBefore)
        XCTAssertEqual(notesAfter, notesBefore)
        XCTAssertEqual(workspaceAfter.replicaID, workspaceBefore.replicaID)
        XCTAssertEqual(workspaceAfter.opaqueWorkspaceID, workspaceBefore.opaqueWorkspaceID)
        XCTAssertEqual(workspaceAfter.logicalCounter, workspaceBefore.logicalCounter)
    }

    func testZoneCreationAndResetRemainIndependentOutgoingBoundaries() async throws {
        let repository = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(UUID()))
        )
        var initial = SyncPersistentState()
        initial.fullReconciliationRequired = true
        let state = SyncCoordinatorState(persistent: initial, repository: repository)
        await state.beginFetch()
        await state.recordRequiredZoneFetchCompletion(succeeded: true)
        let committed = try await state.completeFetch()
        XCTAssertTrue(committed)
        let beforeCreation = await state.canScheduleRecordChanges()
        XCTAssertFalse(beforeCreation)
        let created = try await state.markZoneCreated()
        XCTAssertTrue(created)
        let afterCreation = await state.canScheduleRecordChanges()
        XCTAssertTrue(afterCreation)
        try await state.freezeForZoneReset()
        let afterReset = await state.canScheduleRecordChanges()
        XCTAssertFalse(afterReset)
        let retained = await state.snapshot()
        XCTAssertTrue(retained.zoneResetRequired)
    }
}
