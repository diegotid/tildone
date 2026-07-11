import Foundation
import SwiftData
import XCTest
import TildoneDomain
@testable import TildonePersistence

final class TildonePersistenceTests: XCTestCase {
    private let replica = ReplicaID(UUID(uuidString: "20000000-0000-0000-0000-000000000001")!)
    private let noteID = NoteID(UUID(uuidString: "10000000-0000-0000-0000-000000000001")!)
    private let taskID = TaskID(UUID(uuidString: "30000000-0000-0000-0000-000000000001")!)
    private let createdAt = Date(timeIntervalSince1970: 1_000)

    func testFullDomainRoundTripPreservesEveryStoredProperty() throws {
        let titleStamp = stamp(2)
        let lifecycleStamp = stamp(3)
        let note = Note(
            id: noteID,
            createdAt: createdAt,
            title: "📝 Café\n漢字",
            titleVersion: titleStamp,
            lifecycle: .deleted,
            lifecycleVersion: lifecycleStamp,
            lastMeaningfulEditAt: createdAt.addingTimeInterval(10)
        )
        XCTAssertEqual(try StoredDomainMapping.note(from: StoredDomainMapping.storedNote(from: note)), note)

        let task = Task(
            id: taskID,
            noteID: noteID,
            createdAt: createdAt,
            text: "✅ naïve\nمهمة",
            textVersion: stamp(4),
            completion: .completed(at: createdAt.addingTimeInterval(20)),
            completionVersion: stamp(5),
            orderToken: try OrderToken(rawValue: "az9"),
            orderVersion: stamp(6),
            lifecycle: .deleted,
            lifecycleVersion: stamp(7)
        )
        XCTAssertEqual(try StoredDomainMapping.task(from: StoredDomainMapping.storedTask(from: task)), task)

        let nilTitle = Note(
            id: NoteID(), createdAt: createdAt, title: nil,
            titleVersion: stamp(8), lifecycleVersion: stamp(8), lastMeaningfulEditAt: createdAt
        )
        XCTAssertNil(try StoredDomainMapping.note(from: StoredDomainMapping.storedNote(from: nilTitle)).title)
    }

    func testMalformedStoredRepresentationsProduceTypedErrors() throws {
        let validTask = try StoredDomainMapping.storedTask(from: makeTask())
        validTask.orderTokenRawValue = "BAD"
        assertMalformed(try StoredDomainMapping.task(from: validTask), field: "orderToken")

        let completion = try StoredDomainMapping.storedTask(from: makeTask())
        completion.isCompleted = true
        completion.completedAt = nil
        assertMalformed(try StoredDomainMapping.task(from: completion), field: "completion")

        let owner = try StoredDomainMapping.storedTask(from: makeTask())
        owner.noteStableID = "not-a-uuid"
        assertMalformed(try StoredDomainMapping.task(from: owner), field: "ownership")

        let version = try StoredDomainMapping.storedTask(from: makeTask())
        version.textVersionCounter = -1
        assertMalformed(try StoredDomainMapping.task(from: version), field: "textVersion")

        let lifecycle = try StoredDomainMapping.storedNote(from: makeNote())
        lifecycle.lifecycleRawValue = "unknown"
        assertMalformed(try StoredDomainMapping.note(from: lifecycle), field: "lifecycle")

        let future = try StoredDomainMapping.storedNote(from: makeNote())
        future.recordSchemaVersion = Note.currentSchemaVersion + 1
        XCTAssertThrowsError(try StoredDomainMapping.note(from: future)) {
            XCTAssertEqual($0 as? PersistenceError, .unsupportedRecordSchema(.note, 2))
        }
    }

    func testNoteAndTaskMutationsPreserveIndependentVersionsAndOrdering() async throws {
        let repository = try makeRepository(now: createdAt.addingTimeInterval(50))
        let note = try await repository.createNote(id: noteID, createdAt: createdAt, title: nil)
        let firstToken = try OrderToken(rawValue: "h")
        let secondToken = try OrderToken(rawValue: "q")
        let first = try await repository.addTask(
            id: taskID, to: noteID, createdAt: createdAt, text: "one", orderToken: firstToken
        )
        let secondID = TaskID()
        _ = try await repository.addTask(
            id: secondID, to: noteID, createdAt: createdAt, text: "two", orderToken: firstToken
        )

        let edited = try await repository.editTask(id: taskID, text: "éдит")
        XCTAssertGreaterThan(edited.textVersion, first.textVersion)
        XCTAssertEqual(edited.completionVersion, first.completionVersion)
        XCTAssertEqual(edited.orderVersion, first.orderVersion)

        let completed = try await repository.setTaskCompletion(
            id: taskID, completion: .completed(at: createdAt.addingTimeInterval(5))
        )
        XCTAssertEqual(completed.textVersion, edited.textVersion)
        XCTAssertGreaterThan(completed.completionVersion, edited.completionVersion)

        let moved = try await repository.moveTask(id: taskID, to: secondToken)
        XCTAssertEqual(moved.textVersion, edited.textVersion)
        XCTAssertEqual(moved.completionVersion, completed.completionVersion)
        XCTAssertGreaterThan(moved.orderVersion, completed.orderVersion)
        let orderedIDs = try await repository.orderedTasks(in: noteID).map(\.id)
        XCTAssertEqual(orderedIDs, [secondID, taskID])

        let renamed = try await repository.renameNote(
            id: noteID, to: "Unicode 🧡", editedAt: createdAt.addingTimeInterval(100)
        )
        XCTAssertGreaterThan(renamed.titleVersion, note.titleVersion)
        XCTAssertEqual(renamed.lifecycleVersion, note.lifecycleVersion)
        let summary = try await repository.taskSummary(in: noteID)
        let meaningfullyEdited = try await repository.notesMeaningfullyEdited(
            since: createdAt.addingTimeInterval(90)
        )
        XCTAssertEqual(summary.completedCount, 1)
        XCTAssertEqual(meaningfullyEdited.map(\.id), [noteID])
    }

    func testDeletedParentHidesAndTombstonesChildrenAndExplicitRestoreDoesNotRestoreChildren() async throws {
        let repository = try makeRepository()
        _ = try await repository.createNote(id: noteID, createdAt: createdAt, title: "parent")
        _ = try await repository.addTask(
            id: taskID, to: noteID, createdAt: createdAt, text: "child",
            orderToken: try OrderToken(rawValue: "h")
        )

        try await repository.deleteNote(id: noteID)

        let visible = try await repository.visibleNotes()
        let hiddenChildren = try await repository.orderedTasks(in: noteID)
        let deletedNote = try await repository.note(id: noteID, includingDeleted: true)
        let deletedTask = try await repository.task(id: taskID, includingDeleted: true)
        XCTAssertTrue(visible.isEmpty)
        XCTAssertTrue(hiddenChildren.isEmpty)
        XCTAssertEqual(deletedNote.lifecycle, .deleted)
        XCTAssertEqual(deletedTask.lifecycle, .deleted)
        let targets = Set(try await repository.pendingMutations().map { $0.targetStableID })
        XCTAssertEqual(targets, [noteID.stringValue, taskID.stringValue])

        _ = try await repository.restoreNote(id: noteID)
        let stillDeleted = try await repository.orderedTasks(in: noteID)
        XCTAssertTrue(stillDeleted.isEmpty)
        _ = try await repository.restoreTask(id: taskID)
        let restoredIDs = try await repository.orderedTasks(in: noteID).map(\.id)
        XCTAssertEqual(restoredIDs, [taskID])
    }

    func testInvalidParentAndDeletedParentRejectTaskCreationOrRestore() async throws {
        let repository = try makeRepository()
        await XCTAssertThrowsPersistenceError(.missing(.note, noteID.stringValue)) {
            _ = try await repository.addTask(
                id: self.taskID, to: self.noteID, createdAt: self.createdAt,
                text: "orphan", orderToken: try OrderToken(rawValue: "h")
            )
        }
        _ = try await repository.createNote(id: noteID, createdAt: createdAt, title: nil)
        _ = try await repository.addTask(
            id: taskID, to: noteID, createdAt: createdAt, text: "child",
            orderToken: try OrderToken(rawValue: "h")
        )
        try await repository.deleteNote(id: noteID)
        await XCTAssertThrowsPersistenceError(.domainInvariant) {
            _ = try await repository.restoreTask(id: self.taskID)
        }
    }

    func testOutboxIsAtomicCoalescibleRetrySafeAcknowledgeableAndContentFree() async throws {
        let repository = try makeRepository()
        let secret = "private title should never enter queue"
        _ = try await repository.createNote(id: noteID, createdAt: createdAt, title: secret)
        let first = try await repository.pendingMutations().first!
        _ = try await repository.renameNote(id: noteID, to: "second secret", editedAt: createdAt)

        let active = try await repository.pendingMutations()
        let all = try await repository.pendingMutations(includeSuperseded: true)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first(where: { $0.id == first.id })?.supersededBy, active[0].id)
        XCTAssertGreaterThan(active[0].sequence, first.sequence)

        try await repository.recordMutationAttempt(id: active[0].id, at: createdAt)
        let retried = try await repository.pendingMutations()[0]
        XCTAssertEqual(retried.attemptCount, 1)
        XCTAssertEqual(retried.lastAttemptAt, createdAt)
        let encoded = String(decoding: try JSONEncoder().encode(all), as: UTF8.self)
        XCTAssertFalse(encoded.contains(secret))
        XCTAssertFalse(encoded.contains("second secret"))

        try await repository.acknowledgeMutations(ids: [first.id, active[0].id])
        let acknowledged = try await repository.pendingMutations(includeSuperseded: true)
        XCTAssertTrue(acknowledged.isEmpty)
    }

    func testForcedSaveFailureLeavesNeitherContentNorOutboxHalf() async throws {
        let repository = try makeRepository()
        await repository.failNextSaveForTesting()
        await XCTAssertThrowsPersistenceError(.atomicMutationFailure) {
            _ = try await repository.createNote(
                id: self.noteID, createdAt: self.createdAt, title: "must roll back"
            )
        }
        await XCTAssertThrowsPersistenceError(.missing(.note, noteID.stringValue)) {
            _ = try await repository.note(id: self.noteID, includingDeleted: true)
        }
        let pending = try await repository.pendingMutations(includeSuperseded: true)
        XCTAssertTrue(pending.isEmpty)
    }

    func testPersistentStoreClosesReopensAndRetainsContentOutboxMetadataAndOpaqueState() async throws {
        let base = try temporaryDirectory()
        let descriptor = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .localOnly)
        do {
            let first = try TildoneRepository(descriptor: descriptor, replicaID: replica)
            _ = try await first.createNote(id: noteID, createdAt: createdAt, title: "durable")
            try await first.storeFutureSyncEngineState(Data([0, 1, 255]))
        }
        let reopened = try TildoneRepository(descriptor: descriptor, replicaID: ReplicaID())
        let durableNote = try await reopened.note(id: noteID, includingDeleted: false)
        let durablePending = try await reopened.pendingMutations()
        XCTAssertEqual(durableNote.title, "durable")
        XCTAssertEqual(durablePending.count, 1)
        let metadata = try await reopened.workspaceSnapshot()
        XCTAssertEqual(metadata.replicaID, replica)
        XCTAssertEqual(metadata.sharedSchemaVersion, 1)
        XCTAssertEqual(metadata.futureSyncEngineState, Data([0, 1, 255]))
    }

    func testWorkspaceIsolationRepeatableLocationsAndLegacyPathNoncollision() async throws {
        let base = try temporaryDirectory()
        let accountID = UUID(uuidString: "aaaaaaaa-0000-0000-0000-000000000001")!
        let local = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .localOnly)
        let account = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .account(accountID))
        let localURL = try XCTUnwrap(TildoneRepository.storeURL(for: local))
        let accountURL = try XCTUnwrap(TildoneRepository.storeURL(for: account))
        XCTAssertNotEqual(localURL, accountURL)
        XCTAssertEqual(localURL, try TildoneRepository.storeURL(for: local))
        XCTAssertFalse(localURL.lastPathComponent == "default.store")
        XCTAssertFalse(localURL.path.contains("Todo"))

        let legacy = base.appendingPathComponent("default.store")
        let sentinel = Data("legacy untouched".utf8)
        try sentinel.write(to: legacy)
        let localRepository = try TildoneRepository(descriptor: local, replicaID: replica)
        let accountRepository = try TildoneRepository(descriptor: account, replicaID: replica)
        _ = try await localRepository.createNote(id: noteID, createdAt: createdAt, title: "local")
        let accountNotes = try await accountRepository.visibleNotes()
        XCTAssertTrue(accountNotes.isEmpty)
        XCTAssertEqual(try Data(contentsOf: legacy), sentinel)
    }

    func testInMemoryRepositoriesAreIsolatedAndCannotResolveToDisk() async throws {
        let first = try makeRepository()
        let second = try makeRepository()
        _ = try await first.createNote(id: noteID, createdAt: createdAt, title: "only first")
        let isolatedNotes = try await second.visibleNotes()
        XCTAssertTrue(isolatedNotes.isEmpty)
        XCTAssertNil(try TildoneRepository.storeURL(for: .inMemory()))
    }

    func testBadStoreLocationFailsTypedWithoutSilentEmptyFallback() throws {
        let base = try temporaryDirectory()
        let file = base.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: file)
        let descriptor = PersistenceStoreDescriptor.persistent(baseDirectory: file, workspace: .localOnly)
        XCTAssertThrowsError(try TildoneRepository(descriptor: descriptor, replicaID: replica)) {
            XCTAssertTrue([.invalidStoreLocation, .openFailure].contains($0 as? PersistenceError))
        }
    }

    func testConcurrentDuplicateIdentityHasOneWinnerAndCountersAreMonotonic() async throws {
        let repository = try makeRepository()
        let outcomes = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<20 {
                group.addTask {
                    do {
                        _ = try await repository.createNote(
                            id: self.noteID, createdAt: self.createdAt, title: nil
                        )
                        return true
                    } catch {
                        XCTAssertEqual(error as? PersistenceError, .duplicateID(.note, self.noteID.stringValue))
                        return false
                    }
                }
            }
            var values: [Bool] = []
            for await value in group { values.append(value) }
            return values
        }
        XCTAssertEqual(outcomes.filter { $0 }.count, 1)

        async let first = repository.renameNote(id: noteID, to: "a", editedAt: createdAt)
        async let second = repository.renameNote(id: noteID, to: "b", editedAt: createdAt)
        let firstResult = try await first
        let secondResult = try await second
        let versions = [firstResult.titleVersion, secondResult.titleVersion].sorted()
        XCTAssertEqual(versions[1].logicalCounter, versions[0].logicalCounter + 1)
        let workspace = try await repository.workspaceSnapshot()
        XCTAssertEqual(workspace.logicalCounter, versions[1].logicalCounter)
    }

    func testSchemaAndMigrationPlanAreDeliberatelyWired() {
        XCTAssertEqual(TildoneSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(TildoneSchemaV1.models.count, 5)
        XCTAssertEqual(TildoneSchemaMigrationPlan.schemas.count, 1)
        XCTAssertTrue(TildoneSchemaMigrationPlan.stages.isEmpty)
    }

    // MARK: Helpers

    private func makeRepository(now: Date? = nil) throws -> TildoneRepository {
        try TildoneRepository(
            descriptor: .inMemory(),
            replicaID: replica,
            now: { now ?? Date(timeIntervalSince1970: 2_000) }
        )
    }

    private func makeNote() -> Note {
        Note(
            id: noteID, createdAt: createdAt, title: "title",
            titleVersion: stamp(1), lifecycleVersion: stamp(1), lastMeaningfulEditAt: createdAt
        )
    }

    private func makeTask() throws -> Task {
        Task(
            id: taskID, noteID: noteID, createdAt: createdAt, text: "task",
            textVersion: stamp(1), completionVersion: stamp(1),
            orderToken: try OrderToken(rawValue: "h"), orderVersion: stamp(1),
            lifecycleVersion: stamp(1)
        )
    }

    private func stamp(_ counter: UInt64) -> VersionStamp {
        VersionStamp(logicalCounter: counter, replicaID: replica)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TildonePersistenceTests-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func assertMalformed<T>(_ expression: @autoclosure () throws -> T, field: String) {
        XCTAssertThrowsError(try expression()) {
            guard case let .malformedRepresentation(_, _, actualField) = $0 as? PersistenceError else {
                return XCTFail("Expected typed malformed representation, got \($0)")
            }
            XCTAssertEqual(actualField, field)
        }
    }
}

private extension TildonePersistenceTests {
    func XCTAssertThrowsPersistenceError(
        _ expected: PersistenceError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? PersistenceError, expected)
        }
    }
}
