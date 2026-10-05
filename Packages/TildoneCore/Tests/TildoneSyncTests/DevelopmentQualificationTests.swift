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
