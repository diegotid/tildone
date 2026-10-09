import CloudKit
import XCTest
import TildoneDomain
import TildonePersistence
@testable import TildoneSync

/// Isolated synthetic fixtures. These tests qualify the local pipeline, never
/// physical-device delivery or a live CloudKit account.
final class DevelopmentQualificationTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testPausedInsertionDrainsAndArrivesWithEveryFieldInBothDirections() async throws {
        for reverse in [false, true] {
            let first = try makeRepository()
            let second = try makeRepository()
            let source = reverse ? second : first
            let destination = reverse ? first : second
            let outbound = SyncPipeline(repository: source)
            let inbound = SyncPipeline(repository: destination)
            let noteID = NoteID()
            let taskID = TaskID()
            let keeperID = TaskID()
            _ = try await source.createNote(id: noteID, createdAt: date, title: "Qualification checklist")
            _ = try await source.addTask(id: keeperID, to: noteID, createdAt: date,
                                         text: "Keep pending", orderToken: OrderToken(rawValue: "m"))
            try await transfer(outbound, to: inbound)

            // No transport runs during this interval. A task insertion produces
            // both task and parent evidence, even with an already-drained note.
            _ = try await source.addTask(id: taskID, to: noteID, createdAt: date,
                                         text: "Paused synthetic insertion", orderToken: OrderToken(rawValue: "t"))
            let paused = try await source.pendingMutations()
            XCTAssertEqual(Set(paused.map(\.targetKind)), [.note, .task])
            let absent = try await destination.orderedTasks(in: noteID)
            XCTAssertEqual(absent.map(\.id), [keeperID])
            _ = try await source.renameNote(id: noteID, to: "Qualification renamed", editedAt: date)
            _ = try await source.setNoteColor(id: noteID, color: .green)
            _ = try await source.setSingleMemoFont(id: noteID, font: .permanentMarker)
            let rich = RichText(text: "Synthetic bold", spans: [
                .init(range: .init(location: 10, length: 4), attributes: .init(styles: [.bold, .underline]))
            ])
            _ = try await source.editTask(id: taskID, richText: rich)
            _ = try await source.setTaskIndentLevel(id: taskID, indentLevel: 1)
            _ = try await source.setTaskCompletion(id: taskID, completion: .completed(at: date))
            try await transfer(outbound, to: inbound)
            let expectedNote = try await source.note(id: noteID)
            let receivedNote = try await destination.note(id: noteID)
            let expectedTasks = try await source.orderedTasks(in: noteID)
            let receivedTasks = try await destination.orderedTasks(in: noteID)
            XCTAssertEqual(receivedNote, expectedNote)
            XCTAssertEqual(receivedTasks, expectedTasks)
            XCTAssertEqual(receivedTasks.map(\.id), [keeperID, taskID])
            XCTAssertEqual(receivedTasks.last?.richText, rich)
            let pending = try await outbound.pendingCount()
            XCTAssertEqual(pending, 0)

            _ = try await source.setTaskIndentLevel(id: taskID, indentLevel: 0)
            _ = try await source.moveTask(id: taskID, to: OrderToken(rawValue: "a"))
            try await transfer(outbound, to: inbound)
            let reordered = try await destination.orderedTasks(in: noteID)
            XCTAssertEqual(reordered.map(\.id), [taskID, keeperID])

            let staleTask = try await source.task(id: taskID)
            try await source.deleteTask(id: taskID)
            try await transfer(outbound, to: inbound)
            _ = try await inbound.apply([.task(staleTask)], at: date)
            let afterStaleDelivery = try await destination.orderedTasks(in: noteID)
            XCTAssertEqual(afterStaleDelivery.map(\.id), [keeperID])

            // Kind/font on an eligible one-task note, rather than bypassing the
            // repository's memo conversion constraint.
            _ = try await source.setNoteKind(id: noteID, kind: .singleTask)
            try await transfer(outbound, to: inbound)
            let memo = try await destination.note(id: noteID)
            XCTAssertEqual(memo.kind, .singleTask)
            XCTAssertEqual(memo.singleMemoFont, .permanentMarker)
            let staleNote = memo
            try await source.deleteNote(id: noteID)
            try await transfer(outbound, to: inbound)
            _ = try await inbound.apply([.note(staleNote), .task(staleTask)], at: date)
            let visible = try await destination.visibleNotes()
            XCTAssertTrue(visible.isEmpty)
            let finalPending = try await outbound.pendingCount()
            XCTAssertEqual(finalPending, 0)
        }
    }

    func testOlderSaveAcknowledgmentCannotDrainNewerTaskEdit() async throws {
        let source = try makeRepository()
        let destination = try makeRepository()
        let pipeline = SyncPipeline(repository: source)
        let receiver = SyncPipeline(repository: destination)
        let noteID = NoteID()
        let taskID = TaskID()
        _ = try await source.createNote(id: noteID, createdAt: date, title: "Qualification acknowledgment")
        _ = try await source.addTask(id: taskID, to: noteID, createdAt: date,
                                     text: "Before save", orderToken: OrderToken(rawValue: "m"))
        let prepared = try await pipeline.prepareOutboundMutation(recordName: taskID.recordName, at: date)
        let old = try XCTUnwrap(prepared)
        _ = try await source.editTask(id: taskID, text: "After save began")
        _ = try await receiver.apply([old.record], at: date)
        try await pipeline.acknowledge([old.mutationID])
        let remaining = try await source.pendingMutations()
        XCTAssertTrue(remaining.contains { $0.targetStableID == taskID.stringValue && $0.id != old.mutationID })
        try await transfer(pipeline, to: receiver)
        let arrived = try await destination.task(id: taskID)
        XCTAssertEqual(arrived.text, "After save began")
        let pending = try await pipeline.pendingCount()
        XCTAssertEqual(pending, 0)
    }

    func testCanonicalClientConflictRetainsNewestServerEvidenceAndRetriesOwnPlatform() async throws {
        let repository = try makeRepository()
        let replicaID = try await repository.workspaceSnapshot().replicaID
        let state = SyncCoordinatorState(persistent: SyncPersistentState(), repository: repository)
        let mapper = CloudKitRecordMapper()
        let server = mapper.clientRecord(replicaID: replicaID, platform: .iPhone)
        let latest = SyncClientRegistration(replicaID: replicaID, platform: .iPhone, lastSeenAt: date)
        _ = try await state.storeClientRegistration(latest, record: server)
        let stale = SyncClientRegistration(replicaID: replicaID, platform: .mac, lastSeenAt: date.addingTimeInterval(-1))
        let changed = try await state.storeClientRegistration(stale, record: server)
        XCTAssertFalse(changed)
        let retained = await state.snapshot()
        XCTAssertEqual(retained.clientRegistrationsByReplicaID.count, 1)
        XCTAssertEqual(retained.clientRegistration(replicaID: replicaID), latest)
        let retry = mapper.clientRecord(replicaID: replicaID, platform: .mac,
                                        reusing: await state.systemRecord(named: latest.recordName))
        XCTAssertEqual(retry.recordID, server.recordID)
        XCTAssertEqual(Set(retry.allKeys()), ["schemaVersion", "replicaID", "platform"])
        let registered = try mapper.clientRegistration(from: retry, observedAt: date.addingTimeInterval(1))
        _ = try await state.storeClientRegistration(registered, record: retry)
        let final = await state.snapshot()
        XCTAssertEqual(final.clientRegistrationsByReplicaID.count, 1)
        XCTAssertEqual(final.clientRegistration(replicaID: replicaID)?.platform, .mac)
    }

    func testAutomaticSchedulingHandoffUsesCommittedFetchStateWithoutDroppingQueuedDeletion() async throws {
        let repository = try makeRepository()
        let noteID = NoteID()
        let taskID = TaskID()
        _ = try await repository.createNote(id: noteID, createdAt: date, title: "Scheduling handoff")
        _ = try await repository.addTask(id: taskID, to: noteID, createdAt: date,
                                        text: "Queued deletion", orderToken: OrderToken(rawValue: "m"))
        try await repository.deleteTask(id: taskID)
        let queuedBefore = try await repository.pendingMutations(includeSuperseded: true)
        let tombstonesBefore = try await repository.allSyncTasks()
        let workspaceBefore = try await repository.workspaceSnapshot()
        let systemRecord = CloudKitRecordMapper().clientRecord(
            replicaID: workspaceBefore.replicaID, platform: .mac
        )
        var initial = SyncPersistentState()
        initial.zoneCreated = true
        initial.completedReconciliationVersion = SyncPersistentState.currentReconciliationVersion
        initial.engineSerialization = Data([1, 2, 3])
        try initial.storeSystemFields(for: systemRecord)
        let state = SyncCoordinatorState(persistent: initial, repository: repository)

        await state.beginFetch()
        try await state.updateEncodedEngineSerialization(Data([4, 5, 6]))
        let beforeCommit = await state.stateForAutomaticScheduling()
        XCTAssertEqual(beforeCommit?.engineSerialization, Data([1, 2, 3]))
        try await state.completeFetch()
        let handoff = await state.stateForAutomaticScheduling()
        let captured = try XCTUnwrap(handoff)
        let persisted = SyncPersistentState(data: try await repository.workspaceSnapshot().futureSyncEngineState)
        XCTAssertEqual(captured.engineSerialization, Data([4, 5, 6]))
        XCTAssertEqual(captured, persisted)
        XCTAssertEqual(captured.systemFieldsByRecordName, initial.systemFieldsByRecordName)
        XCTAssertTrue(captured.zoneCreated)
        XCTAssertFalse(captured.fullReconciliationRequired)
        let queuedAfter = try await repository.pendingMutations(includeSuperseded: true)
        let tombstonesAfter = try await repository.allSyncTasks()
        let workspaceAfter = try await repository.workspaceSnapshot()
        XCTAssertEqual(queuedAfter, queuedBefore)
        XCTAssertEqual(tombstonesAfter, tombstonesBefore)
        XCTAssertEqual(workspaceAfter.opaqueWorkspaceID, workspaceBefore.opaqueWorkspaceID)
        XCTAssertEqual(workspaceAfter.replicaID, workspaceBefore.replicaID)
        XCTAssertEqual(workspaceAfter.logicalCounter, workspaceBefore.logicalCounter)
    }

    func testPausedOrFailedRefreshCannotHandOffToAutomaticScheduling() async throws {
        let repository = try makeRepository()
        var persistent = SyncPersistentState()
        persistent.zoneCreated = true
        persistent.engineSerialization = Data([7, 8, 9])
        try await repository.storeFutureSyncEngineState(persistent.encoded())
        let savedBefore = try await repository.workspaceSnapshot().futureSyncEngineState
        let state = SyncCoordinatorState(persistent: persistent, repository: repository)
        await state.beginFetch()
        try await state.updateEncodedEngineSerialization(Data([10, 11, 12]))
        // Pause or a local presentation failure freezes before fetch completion.
        await state.freeze()
        let handoff = await state.stateForAutomaticScheduling()
        XCTAssertNil(handoff)
        let savedAfter = try await repository.workspaceSnapshot().futureSyncEngineState
        XCTAssertEqual(savedAfter, savedBefore)
        let retained = await state.snapshot()
        XCTAssertEqual(retained.engineSerialization, Data([7, 8, 9]))
    }

#if DEBUG
    func testQualificationFaultIsSyntheticOnlyOneShotAndDoesNotChangeSavedState() async throws {
        let repository = try makeRepository()
        let fixture = TildoneRepository.QualificationFixture.offline
        let note = try await repository.createNote(id: NoteID(), createdAt: date, title: fixture.title)
        let marker = try await repository.addTask(
            id: TaskID(), to: note.id, createdAt: date,
            text: "Stage12 refresh failure 20261009", orderToken: OrderToken(rawValue: "m")
        )
        let unrelated = try await repository.createNote(
            id: NoteID(), createdAt: date, title: "Unrelated isolated fixture"
        )
        let before = try await repository.qualificationSnapshot(fixture)
        let injector = SyncQualificationFaultInjector(armed: true)
        // A mixed delivery containing unrelated data must never inject.
        try await injector.check(in: repository, changedRecords: [.task(marker.id), .note(unrelated.id)])
        try await SyncQualificationFaultInjector(armed: false).check(
            in: repository, changedRecords: [.task(marker.id)]
        )
        do {
            try await injector.check(in: repository, changedRecords: [.task(marker.id)])
            XCTFail("Expected the explicitly armed synthetic failure")
        } catch {
            XCTAssertEqual(error as? SyncQualificationFaultInjector.Fault, .syntheticRemoteRefresh)
        }
        try await injector.check(in: repository, changedRecords: [.task(marker.id)])
        let after = try await repository.qualificationSnapshot(fixture)
        XCTAssertEqual(after.notes, before.notes)
        XCTAssertEqual(after.tasks, before.tasks)
        XCTAssertEqual(after.pending, before.pending)
        XCTAssertEqual(after.workspace, before.workspace)
    }

    func testQualificationSnapshotIncludesOnlyNamedFixtureAndItsDeletedChildren() async throws {
        let repository = try makeRepository()
        let fixture = TildoneRepository.QualificationFixture.offline
        let note = try await repository.createNote(id: NoteID(), createdAt: date, title: fixture.title)
        let task = try await repository.addTask(id: TaskID(), to: note.id, createdAt: date,
                                                text: "Synthetic tombstone", orderToken: OrderToken(rawValue: "m"))
        try await repository.deleteTask(id: task.id)
        let unrelated = try await repository.createNote(id: NoteID(), createdAt: date, title: "Unrelated fixture")
        _ = try await repository.addTask(id: TaskID(), to: unrelated.id, createdAt: date,
                                        text: "Excluded payload", orderToken: OrderToken(rawValue: "m"))
        let before = try await repository.workspaceSnapshot()
        let captured = try await repository.qualificationSnapshot(fixture)
        XCTAssertEqual(captured.notes.map(\.id), [note.id])
        XCTAssertEqual(captured.tasks.map(\.id), [task.id])
        XCTAssertEqual(captured.tasks.first?.lifecycle, .deleted)
        XCTAssertTrue(captured.pending.allSatisfy {
            [note.id.stringValue, task.id.stringValue].contains($0.targetStableID)
        })
        XCTAssertFalse(captured.pending.isEmpty)
        XCTAssertEqual(captured.workspace, before)
        let after = try await repository.workspaceSnapshot()
        XCTAssertEqual(after, before)
        let absent = try await repository.qualificationSnapshot(.memo)
        XCTAssertTrue(absent.notes.isEmpty)
        XCTAssertTrue(absent.tasks.isEmpty)
        XCTAssertTrue(absent.pending.isEmpty)
    }
#endif

    private func makeRepository() throws -> TildoneRepository {
        try TildoneRepository(descriptor: .inMemory(workspace: .account(UUID())), now: { self.date })
    }

    private func transfer(_ source: SyncPipeline, to destination: SyncPipeline) async throws {
        let mapper = CloudKitRecordMapper()
        var records: [SyncRecord] = []
        var acknowledgments: Set<UUID> = []
        for name in try await source.pendingRecordNames() {
            guard let mutation = try await source.prepareOutboundMutation(recordName: name, at: date) else { continue }
            records.append(try mapper.syncRecord(from: mapper.record(from: mutation.record)))
            acknowledgments.insert(mutation.mutationID)
        }
        _ = try await destination.apply(records.reversed(), at: date)
        _ = try await destination.apply(records, at: date)
        try await source.acknowledge(acknowledgments)
    }
}
