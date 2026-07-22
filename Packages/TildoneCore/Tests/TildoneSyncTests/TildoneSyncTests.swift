//
//  TildoneSyncTests.swift
//  Tildone
//
import CloudKit
import XCTest
import TildoneDomain
import TildonePersistence
@testable import TildoneSync

final class TildoneSyncTests: XCTestCase {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testDomainToCloudRecordRoundTrips() throws {
        let fixture = Fixture()
        let mapper = CloudKitRecordMapper()
        for value in [SyncRecord.note(fixture.note), SyncRecord.task(fixture.task)] {
            let record = mapper.record(from: value)
            XCTAssertEqual(record.recordID.zoneID, TildoneCloudSchema.zoneID)
            XCTAssertEqual(record.recordID.recordName, value.recordName)
            XCTAssertEqual(try mapper.syncRecord(from: record), value)
        }
        XCTAssertEqual(TildoneCloudSchema.containerIdentifier, "iCloud.studio.cuatro.tildone")
        XCTAssertEqual(TildoneCloudSchema.noteRecordType, "TDNote")
        XCTAssertEqual(TildoneCloudSchema.taskRecordType, "TDTask")
    }

    func testDiagnosticFailureCategoriesDiscardContentBearingErrorDetails() {
        let sensitiveRecordName = "note-private-record-name"
        let sensitiveFieldName = "private-title-field"
        let persistenceError = PersistenceError.malformedRepresentation(
            .note,
            sensitiveRecordName,
            field: sensitiveFieldName
        )

        let persistenceCategory = SyncFailureDiagnosticCategory.classify(persistenceError)
        XCTAssertEqual(persistenceCategory, .persistenceMalformed)
        XCTAssertEqual(persistenceCategory.label, "persistence-malformed")
        XCTAssertFalse(persistenceCategory.label.contains(sensitiveRecordName))
        XCTAssertFalse(persistenceCategory.label.contains(sensitiveFieldName))

        let unrelatedError = NSError(
            domain: "private-note-title",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "private task text"]
        )
        XCTAssertEqual(
            SyncFailureDiagnosticCategory.classify(unrelatedError).label,
            "non-cloud-non-persistence"
        )
    }

    func testInitialUploadAndInitialFetch() async throws {
        let source = try Replica(id: 1)
        let destination = try Replica(id: 2)
        let noteID = NoteID(UUID(int: 10))
        let taskID = TaskID(UUID(int: 11))
        _ = try await source.repository.createNote(id: noteID, createdAt: date, title: "Private")
        _ = try await source.repository.addTask(
            id: taskID, to: noteID, createdAt: date, text: "One",
            orderToken: try OrderToken(rawValue: "m")
        )

        var server: [String: SyncRecord] = [:]
        try await upload(source, server: &server)
        XCTAssertEqual(server.count, 2)
        try await deliver(server, to: destination)
        let fetchedNote = try await destination.repository.note(id: noteID)
        let fetchedTasks = try await destination.repository.orderedTasks(in: noteID)
        let destinationPending = try await destination.repository.pendingMutations()
        XCTAssertEqual(fetchedNote.title, "Private")
        XCTAssertEqual(fetchedTasks.map(\.text), ["One"])
        XCTAssertTrue(destinationPending.isEmpty)
    }

    func testPendingMutationSurvivesRelaunchAndInterruptedSend() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TildoneSyncTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = WorkspaceIdentity.account(UUID(int: 90))
        let descriptor = PersistenceStoreDescriptor.persistent(baseDirectory: root, workspace: workspace)
        let noteID = NoteID(UUID(int: 91))
        try await prepareInterruptedMutation(
            descriptor: descriptor,
            noteID: noteID
        )
        try await Swift.Task.sleep(nanoseconds: 20_000_000)

        let reopened = try TildoneRepository(
            descriptor: descriptor,
            replicaID: ReplicaID(UUID(int: 999))
        )
        let pending = try await reopened.pendingMutations()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].attemptCount, 1)
        XCTAssertEqual(pending[0].targetStableID, noteID.stringValue)
    }

    func testDuplicateSendAndDuplicateDeliveryAreIdempotent() async throws {
        let source = try Replica(id: 1)
        let destination = try Replica(id: 2)
        let noteID = NoteID(UUID(int: 20))
        _ = try await source.repository.createNote(id: noteID, createdAt: date, title: "A")
        let first = try await source.pipeline.prepareOutboundMutation(recordName: noteID.recordName, at: date)!
        let second = try await source.pipeline.prepareOutboundMutation(recordName: noteID.recordName, at: date)!
        XCTAssertEqual(first.record, second.record)
        XCTAssertEqual(first.mutationID, second.mutationID)

        _ = try await destination.pipeline.apply([first.record, first.record], at: date)
        _ = try await destination.pipeline.apply([first.record], at: date)
        let notes = try await destination.repository.allSyncNotes()
        let pending = try await destination.repository.pendingMutations()
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(pending.isEmpty)
    }

    func testConcurrentDifferentPropertyAndSamePropertyEditsConverge() async throws {
        let a = try Replica(id: 1)
        let b = try Replica(id: 2)
        let noteID = NoteID(UUID(int: 30))
        let taskID = TaskID(UUID(int: 31))
        _ = try await a.repository.createNote(id: noteID, createdAt: date, title: "Start")
        _ = try await a.repository.addTask(
            id: taskID, to: noteID, createdAt: date, text: "Initial",
            orderToken: try OrderToken(rawValue: "m")
        )
        var server: [String: SyncRecord] = [:]
        try await upload(a, server: &server)
        try await deliver(server, to: b)

        _ = try await a.repository.editTask(id: taskID, text: "Edited text")
        _ = try await b.repository.setTaskCompletion(id: taskID, completion: .completed(at: date.addingTimeInterval(1)))
        _ = try await a.repository.renameNote(id: noteID, to: "Title A", editedAt: date.addingTimeInterval(2))
        _ = try await b.repository.renameNote(id: noteID, to: "Title B", editedAt: date.addingTimeInterval(3))
        try await upload(a, server: &server)
        try await upload(b, server: &server)
        try await deliver(server, to: a)
        try await deliver(server, to: b)

        let taskA = try await a.repository.task(id: taskID)
        let taskB = try await b.repository.task(id: taskID)
        XCTAssertEqual(taskA, taskB)
        XCTAssertEqual(taskA.text, "Edited text")
        XCTAssertTrue(taskA.isCompleted)
        let noteA = try await a.repository.note(id: noteID)
        let noteB = try await b.repository.note(id: noteID)
        XCTAssertEqual(noteA, noteB)
        XCTAssertTrue(["Title A", "Title B"].contains(noteA.title))
    }

    func testConcurrentReordersConvergeWithoutDroppingTasks() async throws {
        let a = try Replica(id: 1)
        let b = try Replica(id: 2)
        let noteID = NoteID(UUID(int: 40))
        let firstID = TaskID(UUID(int: 41))
        let secondID = TaskID(UUID(int: 42))
        _ = try await a.repository.createNote(id: noteID, createdAt: date, title: nil)
        _ = try await a.repository.addTask(id: firstID, to: noteID, createdAt: date, text: "1", orderToken: try OrderToken(rawValue: "g"))
        _ = try await a.repository.addTask(id: secondID, to: noteID, createdAt: date, text: "2", orderToken: try OrderToken(rawValue: "t"))
        var server: [String: SyncRecord] = [:]
        try await upload(a, server: &server)
        try await deliver(server, to: b)

        _ = try await a.repository.moveTask(id: firstID, to: try OrderToken(rawValue: "z"))
        _ = try await b.repository.moveTask(id: secondID, to: try OrderToken(rawValue: "a"))
        try await upload(b, server: &server)
        try await upload(a, server: &server)
        try await deliver(server, to: a)
        try await deliver(server, to: b)
        let orderA = try await a.repository.orderedTasks(in: noteID).map(\.id)
        let orderB = try await b.repository.orderedTasks(in: noteID).map(\.id)
        XCTAssertEqual(orderA, orderB)
        XCTAssertEqual(Set(orderA), Set([firstID, secondID]))
    }

    func testDeleteVersusEditAndParentDeleteWithChildChanges() async throws {
        let a = try Replica(id: 1)
        let b = try Replica(id: 2)
        let noteID = NoteID(UUID(int: 50))
        let taskID = TaskID(UUID(int: 51))
        let newTaskID = TaskID(UUID(int: 52))
        _ = try await a.repository.createNote(id: noteID, createdAt: date, title: nil)
        _ = try await a.repository.addTask(id: taskID, to: noteID, createdAt: date, text: "Old", orderToken: try OrderToken(rawValue: "m"))
        var server: [String: SyncRecord] = [:]
        try await upload(a, server: &server)
        try await deliver(server, to: b)

        try await a.repository.deleteNote(id: noteID)
        _ = try await b.repository.editTask(id: taskID, text: "Offline edit")
        _ = try await b.repository.addTask(id: newTaskID, to: noteID, createdAt: date, text: "Offline child", orderToken: try OrderToken(rawValue: "z"))
        try await upload(b, server: &server)
        try await upload(a, server: &server)
        try await converge([a, b], server: &server)

        for replica in [a, b] {
            let note = try await replica.repository.note(id: noteID, includingDeleted: true)
            let oldTask = try await replica.repository.task(id: taskID, includingDeleted: true)
            let newTask = try await replica.repository.task(id: newTaskID, includingDeleted: true)
            let visible = try await replica.repository.visibleNotes()
            XCTAssertEqual(note.lifecycle, .deleted)
            XCTAssertEqual(oldTask.lifecycle, .deleted)
            XCTAssertEqual(newTask.lifecycle, .deleted)
            XCTAssertTrue(visible.isEmpty)
        }

        let physical = try Replica(id: 53)
        let physicalNoteID = NoteID(UUID(int: 54))
        let physicalTaskID = TaskID(UUID(int: 55))
        _ = try await physical.repository.createNote(
            id: physicalNoteID,
            createdAt: date,
            title: nil
        )
        _ = try await physical.repository.addTask(
            id: physicalTaskID,
            to: physicalNoteID,
            createdAt: date,
            text: "Physical-delete compatibility",
            orderToken: try OrderToken(rawValue: "m")
        )
        var physicalServer: [String: SyncRecord] = [:]
        try await upload(physical, server: &physicalServer)
        try await physical.pipeline.applyPhysicalDeletion(
            recordName: physicalNoteID.recordName,
            at: date
        )
        let deletedNote = try await physical.repository.note(
            id: physicalNoteID,
            includingDeleted: true
        )
        let deletedTask = try await physical.repository.task(
            id: physicalTaskID,
            includingDeleted: true
        )
        let physicalPendingCount = try await physical.pipeline.pendingCount()
        XCTAssertEqual(deletedNote.lifecycle, .deleted)
        XCTAssertEqual(deletedTask.lifecycle, .deleted)
        XCTAssertEqual(physicalPendingCount, 2)
    }

    func testOfflineEditsReconnectAndPartialSuccessKeepsOnlyFailuresPending() async throws {
        let a = try Replica(id: 1)
        let b = try Replica(id: 2)
        let noteID = NoteID(UUID(int: 60))
        let taskID = TaskID(UUID(int: 61))
        _ = try await a.repository.createNote(id: noteID, createdAt: date, title: "Offline")
        _ = try await a.repository.addTask(id: taskID, to: noteID, createdAt: date, text: "Queued", orderToken: try OrderToken(rawValue: "m"))
        var server: [String: SyncRecord] = [:]
        try await upload(a, server: &server, accepting: { $0 == noteID.recordName })
        let partialPending = try await a.repository.pendingMutations()
        XCTAssertEqual(partialPending.count, 1)
        XCTAssertEqual(partialPending[0].targetStableID, taskID.stringValue)
        try await upload(a, server: &server)
        try await deliver(server, to: b)
        let fetched = try await b.repository.orderedTasks(in: noteID)
        XCTAssertEqual(fetched.map(\.text), ["Queued"])
    }

    func testServerRecordChangedMergeRetainsPendingWinnerForRetry() async throws {
        let a = try Replica(id: 1)
        let b = try Replica(id: 2)
        let noteID = NoteID(UUID(int: 70))
        _ = try await a.repository.createNote(id: noteID, createdAt: date, title: "Original")
        var server: [String: SyncRecord] = [:]
        try await upload(a, server: &server)
        try await deliver(server, to: b)
        _ = try await a.repository.renameNote(id: noteID, to: "Client", editedAt: date)
        _ = try await b.repository.renameNote(id: noteID, to: "Server", editedAt: date)
        try await upload(b, server: &server)

        // Simulate CKError.serverRecordChanged: merge the returned server record
        // locally but do not acknowledge the client's durable mutation.
        _ = try await a.pipeline.apply([server[noteID.recordName]!], at: date)
        let pending = try await a.repository.pendingMutations()
        XCTAssertEqual(pending.count, 1)
        try await upload(a, server: &server)
        try await deliver(server, to: b)
        let noteA = try await a.repository.note(id: noteID)
        let noteB = try await b.repository.note(id: noteID)
        XCTAssertEqual(noteA, noteB)
    }

    func testEngineEnvelopeRestoresAfterWorkspaceRelaunchAndZoneResetFreezes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TildoneEngineState-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptor = PersistenceStoreDescriptor.persistent(
            baseDirectory: root,
            workspace: .account(UUID(int: 80))
        )
        var repository: TildoneRepository? = try TildoneRepository(descriptor: descriptor)
        var state = SyncPersistentState()
        state.zoneCreated = true
        state.zoneResetRequired = true
        try await repository!.storeFutureSyncEngineState(state.encoded())
        repository = nil
        try await Swift.Task.sleep(nanoseconds: 20_000_000)
        let reopened = try TildoneRepository(descriptor: descriptor)
        let data = try await reopened.workspaceSnapshot().futureSyncEngineState
        let restored = SyncPersistentState(data: data)
        XCTAssertTrue(restored.zoneCreated)
        XCTAssertTrue(restored.zoneResetRequired)
    }

    func testAccountSignOutAndSwitchInvalidateAndWorkspacesStayIsolated() async throws {
        XCTAssertFalse(SyncAccountChange.signedIn.requiresWorkspaceInvalidation)
        XCTAssertTrue(SyncAccountChange.signedOut.requiresWorkspaceInvalidation)
        XCTAssertTrue(SyncAccountChange.switched.requiresWorkspaceInvalidation)

        let one = CloudAccountResolver.opaqueWorkspaceID(
            containerIdentifier: TildoneCloudSchema.containerIdentifier,
            userRecordName: "account-one"
        )
        let oneAgain = CloudAccountResolver.opaqueWorkspaceID(
            containerIdentifier: TildoneCloudSchema.containerIdentifier,
            userRecordName: "account-one"
        )
        let two = CloudAccountResolver.opaqueWorkspaceID(
            containerIdentifier: TildoneCloudSchema.containerIdentifier,
            userRecordName: "account-two"
        )
        XCTAssertEqual(one, oneAgain)
        XCTAssertNotEqual(one, two)

        let first = try TildoneRepository(descriptor: .inMemory(workspace: .account(one)))
        let second = try TildoneRepository(descriptor: .inMemory(workspace: .account(two)))
        _ = try await first.createNote(id: NoteID(UUID(int: 81)), createdAt: date, title: "Only first")
        let firstNotes = try await first.visibleNotes()
        let secondNotes = try await second.visibleNotes()
        let firstWorkspace = try await first.workspaceSnapshot()
        let secondWorkspace = try await second.workspaceSnapshot()
        XCTAssertEqual(firstNotes.count, 1)
        XCTAssertTrue(secondNotes.isEmpty)
        XCTAssertNotEqual(firstWorkspace.opaqueWorkspaceID, secondWorkspace.opaqueWorkspaceID)
    }

    func testMalformedUnknownAndFutureRecordsAreRejectedWithoutContentInErrors() throws {
        let mapper = CloudKitRecordMapper()
        let fixture = Fixture()
        let future = mapper.record(from: .note(fixture.note))
        future["schemaVersion"] = NSNumber(value: 99)
        XCTAssertThrowsError(try mapper.syncRecord(from: future)) { error in
            XCTAssertEqual(
                error as? CloudRecordMappingError,
                .unsupportedSchema(fixture.note.id.recordName, 99)
            )
            XCTAssertFalse(String(describing: error).contains("Secret title"))
        }

        let unknown = CKRecord(
            recordType: "SpeculativeType",
            recordID: CKRecord.ID(
                recordName: "opaque-name",
                zoneID: TildoneCloudSchema.zoneID
            )
        )
        XCTAssertThrowsError(try mapper.syncRecord(from: unknown))

        let malformedOptional = mapper.record(from: .note(fixture.note))
        malformedOptional["title"] = NSNumber(value: 7)
        XCTAssertThrowsError(try mapper.syncRecord(from: malformedOptional)) { error in
            XCTAssertEqual(
                error as? CloudRecordMappingError,
                .invalidField(fixture.note.id.recordName, "title")
            )
        }
    }

    func testCloudMapperAcceptsServerBooleanRepresentationButRejectsOtherCoercions() throws {
        let mapper = CloudKitRecordMapper()
        let fixture = Fixture()

        let booleanSchema = mapper.record(from: .note(fixture.note))
        booleanSchema["schemaVersion"] = NSNumber(value: true)
        XCTAssertThrowsError(try mapper.syncRecord(from: booleanSchema)) { error in
            XCTAssertEqual(
                error as? CloudRecordMappingError,
                .invalidField(fixture.note.id.recordName, "schemaVersion")
            )
        }

        let fractionalCounter = mapper.record(from: .task(fixture.task))
        fractionalCounter["textVersionCounter"] = NSNumber(value: 7.5)
        XCTAssertThrowsError(try mapper.syncRecord(from: fractionalCounter)) { error in
            XCTAssertEqual(
                error as? CloudRecordMappingError,
                .invalidField(fixture.task.id.recordName, "textVersionCounter")
            )
        }

        let serverTrue = mapper.record(from: .task(fixture.task))
        serverTrue["isCompleted"] = NSNumber(value: Int64(1))
        guard case let .task(decodedTrue) = try mapper.syncRecord(from: serverTrue) else {
            return XCTFail("Expected a task")
        }
        XCTAssertTrue(decodedTrue.isCompleted)

        let serverFalse = mapper.record(from: .task(fixture.task))
        serverFalse["isCompleted"] = NSNumber(value: Int64(0))
        serverFalse["completedAt"] = nil
        guard case let .task(decodedFalse) = try mapper.syncRecord(from: serverFalse) else {
            return XCTFail("Expected a task")
        }
        XCTAssertFalse(decodedFalse.isCompleted)

        for invalid in [NSNumber(value: Int64(2)), NSNumber(value: 0.5)] {
            let invalidBoolean = mapper.record(from: .task(fixture.task))
            invalidBoolean["isCompleted"] = invalid
            XCTAssertThrowsError(try mapper.syncRecord(from: invalidBoolean)) { error in
                XCTAssertEqual(
                    error as? CloudRecordMappingError,
                    .invalidField(fixture.task.id.recordName, "isCompleted")
                )
            }
        }

        let inconsistentBoolean = mapper.record(from: .task(fixture.task))
        inconsistentBoolean["isCompleted"] = NSNumber(value: Int64(0))
        XCTAssertThrowsError(try mapper.syncRecord(from: inconsistentBoolean)) { error in
            XCTAssertEqual(
                error as? CloudRecordMappingError,
                .invalidField(fixture.task.id.recordName, "completedAt")
            )
        }
    }

    func testCloudKitBatchPolicyCapsEachRequestAtServerLimit() {
        let pending = Array(0..<301)
        let firstBatch = TildoneSyncBatchPolicy.bounded(pending)

        XCTAssertEqual(firstBatch.count, 250)
        XCTAssertEqual(Array(firstBatch), Array(0..<250))
        XCTAssertEqual(TildoneSyncBatchPolicy.bounded([] as [Int]).count, 0)
    }

    func testThreeReplicasConvergeAcrossReorderedDuplicateDeliveries() async throws {
        let replicas = try [Replica(id: 1), Replica(id: 2), Replica(id: 3)]
        let noteID = NoteID(UUID(int: 100))
        let taskID = TaskID(UUID(int: 101))
        _ = try await replicas[0].repository.createNote(id: noteID, createdAt: date, title: "Seed")
        _ = try await replicas[0].repository.addTask(id: taskID, to: noteID, createdAt: date, text: "Seed", orderToken: try OrderToken(rawValue: "m"))
        var server: [String: SyncRecord] = [:]
        try await upload(replicas[0], server: &server)
        for replica in replicas.dropFirst() { try await deliver(server, to: replica) }

        _ = try await replicas[0].repository.editTask(id: taskID, text: "Replica one")
        _ = try await replicas[1].repository.setTaskCompletion(id: taskID, completion: .completed(at: date))
        _ = try await replicas[2].repository.renameNote(id: noteID, to: "Replica three", editedAt: date)
        try await upload(replicas[2], server: &server)
        try await upload(replicas[0], server: &server)
        try await upload(replicas[1], server: &server)
        for replica in replicas.reversed() {
            try await deliver(server, to: replica)
            try await deliver(server, to: replica)
        }
        try await converge(replicas, server: &server)

        let notes = try await replicas.asyncMap { try await $0.repository.allSyncNotes() }
        let tasks = try await replicas.asyncMap { try await $0.repository.allSyncTasks() }
        XCTAssertTrue(notes.dropFirst().allSatisfy { $0 == notes[0] })
        XCTAssertTrue(tasks.dropFirst().allSatisfy { $0 == tasks[0] })
        XCTAssertEqual(tasks[0][0].text, "Replica one")
        XCTAssertTrue(tasks[0][0].isCompleted)
    }

}

private extension TildoneSyncTests {
    struct Replica {
        let repository: TildoneRepository
        let pipeline: SyncPipeline

        init(id: UInt64) throws {
            let repository = try TildoneRepository(
                descriptor: .inMemory(workspace: .account(UUID(int: id))),
                replicaID: ReplicaID(UUID(int: id)),
                now: { Date(timeIntervalSinceReferenceDate: 800_000_000) }
            )
            self.repository = repository
            pipeline = SyncPipeline(repository: repository)
        }
    }

    struct Fixture {
        let note: Note
        let task: TildoneDomain.Task

        init() {
            let replica = ReplicaID(UUID(int: 500))
            let stamp = VersionStamp(logicalCounter: 7, replicaID: replica)
            let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let noteID = NoteID(UUID(int: 501))
            note = Note(
                id: noteID,
                createdAt: date,
                title: "Secret title",
                titleVersion: stamp,
                lifecycleVersion: stamp,
                lastMeaningfulEditAt: date,
                lastMeaningfulEditVersion: stamp
            )
            task = TildoneDomain.Task(
                id: TaskID(UUID(int: 502)),
                noteID: noteID,
                createdAt: date,
                text: "Secret task",
                textVersion: stamp,
                completion: .completed(at: date),
                completionVersion: stamp,
                orderToken: try! OrderToken(rawValue: "m"),
                orderVersion: stamp,
                lifecycleVersion: stamp
            )
        }
    }

    func upload(
        _ replica: Replica,
        server: inout [String: SyncRecord],
        accepting: (String) -> Bool = { _ in true }
    ) async throws {
        for name in try await replica.pipeline.pendingRecordNames() where accepting(name) {
            guard let mutation = try await replica.pipeline.prepareOutboundMutation(
                recordName: name,
                at: date
            ) else { continue }
            server[name] = try merge(server[name], mutation.record)
            try await replica.pipeline.acknowledge(Set([mutation.mutationID]))
        }
    }

    func deliver(_ server: [String: SyncRecord], to replica: Replica) async throws {
        _ = try await replica.pipeline.apply(
            server.values.sorted { $0.recordName < $1.recordName },
            at: date
        )
    }

    func converge(_ replicas: [Replica], server: inout [String: SyncRecord]) async throws {
        for _ in 0..<8 {
            var hadPending = false
            for replica in replicas {
                if try await replica.pipeline.pendingCount() > 0 {
                    hadPending = true
                    try await upload(replica, server: &server)
                }
            }
            for replica in replicas { try await deliver(server, to: replica) }
            if !hadPending { return }
        }
        XCTFail("Replicas did not quiesce")
    }

    func merge(_ lhs: SyncRecord?, _ rhs: SyncRecord) throws -> SyncRecord {
        guard let lhs else { return rhs }
        switch (lhs, rhs) {
        case let (.note(a), .note(b)): return .note(try a.merged(with: b))
        case let (.task(a), .task(b)): return .task(try a.merged(with: b))
        default: throw DomainMergeError.immutableFieldMismatch
        }
    }

    func prepareInterruptedMutation(
        descriptor: PersistenceStoreDescriptor,
        noteID: NoteID
    ) async throws {
        let repository = try TildoneRepository(
            descriptor: descriptor,
            replicaID: ReplicaID(UUID(int: 1)),
            now: { Date(timeIntervalSinceReferenceDate: 800_000_000) }
        )
        _ = try await repository.createNote(id: noteID, createdAt: date, title: nil)
        let pipeline = SyncPipeline(repository: repository)
        let outbound = try await pipeline.prepareOutboundMutation(
            recordName: noteID.recordName,
            at: date
        )
        XCTAssertNotNil(outbound)
    }
}

private extension UUID {
    init(int: UInt64) {
        self.init(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            UInt8((int >> 56) & 0xff), UInt8((int >> 48) & 0xff),
            UInt8((int >> 40) & 0xff), UInt8((int >> 32) & 0xff),
            UInt8((int >> 24) & 0xff), UInt8((int >> 16) & 0xff),
            UInt8((int >> 8) & 0xff), UInt8(int & 0xff)
        ))
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var values: [T] = []
        for element in self { values.append(try await transform(element)) }
        return values
    }
}
