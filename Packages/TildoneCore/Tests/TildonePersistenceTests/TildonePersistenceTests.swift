//
//  TildonePersistenceTests.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
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
            lastMeaningfulEditAt: createdAt.addingTimeInterval(10),
            lastMeaningfulEditVersion: stamp(4)
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
            titleVersion: stamp(8), lifecycleVersion: stamp(8), lastMeaningfulEditAt: createdAt,
            lastMeaningfulEditVersion: stamp(8)
        )
        XCTAssertNil(try StoredDomainMapping.note(from: StoredDomainMapping.storedNote(from: nilTitle)).title)
    }

    func testMalformedStoredRepresentationsProduceTypedErrors() throws {
        let uppercaseNote = try StoredDomainMapping.storedNote(from: makeNote())
        uppercaseNote.stableID = "ABCDEF00-0000-0000-0000-000000000001"
        assertMalformed(try StoredDomainMapping.note(from: uppercaseNote), field: "stableID")

        let uppercaseReplica = try StoredDomainMapping.storedNote(from: makeNote())
        uppercaseReplica.titleVersionReplicaID = "ABCDEF00-0000-0000-0000-000000000002"
        assertMalformed(try StoredDomainMapping.note(from: uppercaseReplica), field: "titleVersion")

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

        let uppercaseTask = try StoredDomainMapping.storedTask(from: makeTask())
        uppercaseTask.stableID = "ABCDEF00-0000-0000-0000-000000000003"
        assertMalformed(try StoredDomainMapping.task(from: uppercaseTask), field: "stableID")

        let otherOwner = try StoredDomainMapping.storedTask(from: makeTask())
        XCTAssertThrowsError(try StoredDomainMapping.task(from: otherOwner, expectedNoteID: NoteID())) {
            guard case .ownershipMismatch = $0 as? PersistenceError else {
                return XCTFail("Expected typed ownership mismatch, got \($0)")
            }
        }

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

        var active = try await repository.pendingMutations()
        var all = try await repository.pendingMutations(includeSuperseded: true)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(all.count, 1, "Never-dispatched work should be coalesced away")
        XCTAssertNotEqual(active[0].id, first.id)
        XCTAssertGreaterThan(active[0].sequence, first.sequence)

        try await repository.recordMutationAttempt(id: active[0].id, at: createdAt)
        let inFlightID = active[0].id
        _ = try await repository.renameNote(id: noteID, to: "third secret", editedAt: createdAt)
        active = try await repository.pendingMutations()
        all = try await repository.pendingMutations(includeSuperseded: true)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(all.count, 2, "Potentially in-flight work must be retained")
        XCTAssertEqual(all.first(where: { $0.id == inFlightID })?.supersededBy, active[0].id)
        XCTAssertEqual(all.first(where: { $0.id == inFlightID })?.attemptCount, 1)
        XCTAssertEqual(all.first(where: { $0.id == inFlightID })?.lastAttemptAt, createdAt)
        let encoded = String(decoding: try JSONEncoder().encode(all), as: UTF8.self)
        XCTAssertFalse(encoded.contains(secret))
        XCTAssertFalse(encoded.contains("second secret"))
        XCTAssertFalse(encoded.contains("third secret"))

        try await repository.acknowledgeMutations(ids: [inFlightID])
        var remainingIDs = try await repository.pendingMutations().map(\.id)
        XCTAssertEqual(remainingIDs, [active[0].id])
        try await repository.acknowledgeMutations(ids: [inFlightID])
        remainingIDs = try await repository.pendingMutations().map(\.id)
        XCTAssertEqual(remainingIDs, [active[0].id])
        try await repository.acknowledgeMutations(ids: [active[0].id])
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
        XCTAssertEqual(metadata.sharedSchemaVersion, 2)
        XCTAssertEqual(metadata.futureSyncEngineState, Data([0, 1, 255]))
    }

    func testSameDiskWorkspaceHasOneLifetimeOwnerAndReopensAfterRelease() async throws {
        let base = try temporaryDirectory()
        let descriptor = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .localOnly)
        var owner: TildoneRepository? = try TildoneRepository(descriptor: descriptor, replicaID: replica)

        let failures = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0..<12 {
                group.addTask {
                    do {
                        _ = try TildoneRepository(descriptor: descriptor, replicaID: ReplicaID())
                        return false
                    } catch {
                        return error as? PersistenceError == .workspaceInUse
                    }
                }
            }
            var results: [Bool] = []
            for await result in group { results.append(result) }
            return results
        }
        XCTAssertTrue(failures.allSatisfy { $0 })

        _ = try await owner?.createNote(id: noteID, createdAt: createdAt, title: "owned")
        owner = nil
        let reopened = try TildoneRepository(descriptor: descriptor, replicaID: ReplicaID())
        let reopenedNote = try await reopened.note(id: noteID)
        XCTAssertEqual(reopenedNote.title, "owned")
    }

    func testCounterIsMonotonicAcrossReopen() async throws {
        let base = try temporaryDirectory()
        let descriptor = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .localOnly)
        let before: UInt64
        do {
            let repository = try TildoneRepository(descriptor: descriptor, replicaID: replica)
            _ = try await repository.createNote(id: noteID, createdAt: createdAt, title: nil)
            _ = try await repository.addTask(
                id: taskID, to: noteID, createdAt: createdAt, text: "task",
                orderToken: try OrderToken(rawValue: "h")
            )
            before = try await repository.workspaceSnapshot().logicalCounter
        }
        let reopened = try TildoneRepository(descriptor: descriptor, replicaID: ReplicaID())
        let edited = try await reopened.editTask(id: taskID, text: "edited")
        let note = try await reopened.note(id: noteID)
        let after = try await reopened.workspaceSnapshot().logicalCounter
        XCTAssertGreaterThan(edited.textVersion.logicalCounter, before)
        XCTAssertGreaterThan(note.lastMeaningfulEditVersion.logicalCounter, edited.textVersion.logicalCounter)
        XCTAssertEqual(after, note.lastMeaningfulEditVersion.logicalCounter)
        let reopenedWorkspace = try await reopened.workspaceSnapshot()
        XCTAssertEqual(reopenedWorkspace.replicaID, replica)
    }

    func testTaskMutationAtomicallySchedulesTaskAndMeaningfullyEditedNote() async throws {
        let repository = try makeRepository(now: createdAt.addingTimeInterval(40))
        let original = try await repository.createNote(id: noteID, createdAt: createdAt, title: nil)
        try await repository.acknowledgeMutations(ids: Set(try await repository.pendingMutations().map(\.id)))

        _ = try await repository.addTask(
            id: taskID, to: noteID, createdAt: createdAt.addingTimeInterval(10), text: "task",
            orderToken: try OrderToken(rawValue: "h")
        )
        let note = try await repository.note(id: noteID)
        let pending = try await repository.pendingMutations()
        XCTAssertGreaterThan(note.lastMeaningfulEditVersion, original.lastMeaningfulEditVersion)
        XCTAssertEqual(note.titleVersion, original.titleVersion)
        XCTAssertEqual(note.lifecycleVersion, original.lifecycleVersion)
        XCTAssertEqual(Set(pending.map { $0.targetKind.rawValue + ":" + $0.targetStableID }), [
            "note:\(noteID.stringValue)", "task:\(taskID.stringValue)"
        ])
    }

    func testFailedUpdateAndDeleteTransactionsRollBackContentCounterAndOutbox() async throws {
        let repository = try makeRepository()
        _ = try await repository.createNote(id: noteID, createdAt: createdAt, title: "before")
        _ = try await repository.addTask(
            id: taskID, to: noteID, createdAt: createdAt, text: "before",
            orderToken: try OrderToken(rawValue: "h")
        )
        try await repository.acknowledgeMutations(ids: Set(try await repository.pendingMutations().map(\.id)))
        let counter = try await repository.workspaceSnapshot().logicalCounter

        await repository.failNextSaveForTesting()
        await XCTAssertThrowsPersistenceError(.atomicMutationFailure) {
            _ = try await repository.editTask(id: self.taskID, text: "must not persist")
        }
        var persistedTask = try await repository.task(id: taskID)
        var persistedWorkspace = try await repository.workspaceSnapshot()
        var persistedPending = try await repository.pendingMutations(includeSuperseded: true)
        XCTAssertEqual(persistedTask.text, "before")
        XCTAssertEqual(persistedWorkspace.logicalCounter, counter)
        XCTAssertTrue(persistedPending.isEmpty)

        await repository.failNextSaveForTesting()
        await XCTAssertThrowsPersistenceError(.atomicMutationFailure) {
            try await repository.deleteNote(id: self.noteID)
        }
        let persistedNote = try await repository.note(id: noteID)
        persistedTask = try await repository.task(id: taskID)
        persistedWorkspace = try await repository.workspaceSnapshot()
        persistedPending = try await repository.pendingMutations(includeSuperseded: true)
        XCTAssertEqual(persistedNote.lifecycle, .active)
        XCTAssertEqual(persistedTask.lifecycle, .active)
        XCTAssertEqual(persistedWorkspace.logicalCounter, counter)
        XCTAssertTrue(persistedPending.isEmpty)
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

    func testPreviewAndTemporaryMigrationStoresAreIsolatedAndQuarantineIsTyped() async throws {
        let base = try temporaryDirectory()
        let preview = PersistenceStoreDescriptor.preview(
            baseDirectory: base,
            identifier: UUID(uuidString: "bbbbbbbb-0000-0000-0000-000000000001")!
        )
        let migration = PersistenceStoreDescriptor.temporaryMigration(
            baseDirectory: base,
            workspace: .account(UUID(uuidString: "cccccccc-0000-0000-0000-000000000001")!),
            identifier: UUID(uuidString: "dddddddd-0000-0000-0000-000000000001")!
        )
        XCTAssertNotEqual(try TildoneRepository.storeURL(for: preview), try TildoneRepository.storeURL(for: migration))

        let previewRepository = try TildoneRepository(descriptor: preview, replicaID: replica)
        let migrationRepository = try TildoneRepository(descriptor: migration, replicaID: replica)
        try await previewRepository.quarantine(
            recordKind: .task,
            opaqueRecordID: taskID.recordName,
            category: .invalidOrderToken,
            recordSchemaVersion: 1,
            at: createdAt
        )
        let quarantined = try await previewRepository.quarantinedRecords()
        XCTAssertEqual(quarantined.count, 1)
        XCTAssertEqual(quarantined[0].recordKind, .task)
        XCTAssertEqual(quarantined[0].opaqueRecordID, taskID.recordName)
        XCTAssertEqual(quarantined[0].category, .invalidOrderToken)
        let migrationQuarantine = try await migrationRepository.quarantinedRecords()
        XCTAssertTrue(migrationQuarantine.isEmpty)

        await XCTAssertThrowsPersistenceError(.invalidQuarantineMetadata) {
            try await previewRepository.quarantine(
                recordKind: .task,
                opaqueRecordID: "private task text",
                category: .malformedIdentifier,
                recordSchemaVersion: 1,
                at: self.createdAt
            )
        }
    }

    func testDuplicateWorkspaceMetadataAndDuplicateStoredIdentitiesAreRejected() async throws {
        let duplicateMetadataBase = try temporaryDirectory()
        let duplicateMetadataDescriptor = PersistenceStoreDescriptor.persistent(
            baseDirectory: duplicateMetadataBase,
            workspace: .localOnly
        )
        try withRawStore(duplicateMetadataDescriptor) { context in
            context.insert(WorkspaceMetadata(
                workspaceKindRawValue: "local-only", opaqueWorkspaceID: nil,
                replicaID: replica.stringValue
            ))
            context.insert(WorkspaceMetadata(
                workspaceKindRawValue: "local-only", opaqueWorkspaceID: nil,
                replicaID: ReplicaID().stringValue
            ))
        }
        XCTAssertThrowsError(try TildoneRepository(
            descriptor: duplicateMetadataDescriptor,
            replicaID: replica
        )) {
            XCTAssertEqual($0 as? PersistenceError, .workspaceMismatch)
        }

        let duplicateIdentityBase = try temporaryDirectory()
        let duplicateIdentityDescriptor = PersistenceStoreDescriptor.persistent(
            baseDirectory: duplicateIdentityBase,
            workspace: .localOnly
        )
        try withRawStore(duplicateIdentityDescriptor) { context in
            context.insert(WorkspaceMetadata(
                workspaceKindRawValue: "local-only", opaqueWorkspaceID: nil,
                replicaID: replica.stringValue, logicalCounter: 1
            ))
            context.insert(try StoredDomainMapping.storedNote(from: makeNote()))
            context.insert(try StoredDomainMapping.storedNote(from: makeNote()))
        }
        let repository = try TildoneRepository(descriptor: duplicateIdentityDescriptor, replicaID: replica)
        await XCTAssertThrowsPersistenceError(.duplicateID(.note, noteID.stringValue)) {
            _ = try await repository.visibleNotes()
        }
    }

    func testMalformedWorkspaceAndOutboxRowsAreRejectedWithoutEchoingPayloads() async throws {
        let workspaceBase = try temporaryDirectory()
        let workspaceDescriptor = PersistenceStoreDescriptor.persistent(
            baseDirectory: workspaceBase,
            workspace: .localOnly
        )
        try withRawStore(workspaceDescriptor) { context in
            context.insert(WorkspaceMetadata(
                workspaceKindRawValue: "local-only", opaqueWorkspaceID: nil,
                replicaID: "ABCDEF00-0000-0000-0000-000000000004"
            ))
        }
        XCTAssertThrowsError(try TildoneRepository(descriptor: workspaceDescriptor, replicaID: replica)) {
            XCTAssertEqual($0 as? PersistenceError, .workspaceMismatch)
        }

        let outboxBase = try temporaryDirectory()
        let outboxDescriptor = PersistenceStoreDescriptor.persistent(
            baseDirectory: outboxBase,
            workspace: .localOnly
        )
        try withRawStore(outboxDescriptor) { context in
            context.insert(WorkspaceMetadata(
                workspaceKindRawValue: "local-only", opaqueWorkspaceID: nil,
                replicaID: replica.stringValue, logicalCounter: 3
            ))
            context.insert(try StoredDomainMapping.storedNote(from: makeNote()))
            context.insert(PendingMutation(
                mutationID: UUID().uuidString.lowercased(),
                targetKindRawValue: PersistedEntityKind.task.rawValue,
                targetStableID: noteID.stringValue,
                sequence: 3,
                createdAt: createdAt
            ))
        }
        do {
            _ = try TildoneRepository(descriptor: outboxDescriptor, replicaID: replica)
            XCTFail("Expected malformed outbox metadata")
        } catch {
            guard case let .malformedRepresentation(_, safeID, field) = error as? PersistenceError else {
                return XCTFail("Expected typed malformed representation, got \(error)")
            }
            XCTAssertEqual(safeID, "invalid")
            XCTAssertEqual(field, "pendingMutationTarget")
            XCTAssertFalse(String(describing: error).contains("private"))
        }
    }

    func testMalformedSupersessionLinkIsRejected() async throws {
        let base = try temporaryDirectory()
        let descriptor = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .localOnly)
        let firstID = UUID().uuidString.lowercased()
        try withRawStore(descriptor) { context in
            context.insert(WorkspaceMetadata(
                workspaceKindRawValue: "local-only", opaqueWorkspaceID: nil,
                replicaID: replica.stringValue, logicalCounter: 2
            ))
            context.insert(try StoredDomainMapping.storedNote(from: makeNote()))
            context.insert(PendingMutation(
                mutationID: firstID,
                targetKindRawValue: PersistedEntityKind.note.rawValue,
                targetStableID: noteID.stringValue,
                sequence: 1,
                createdAt: createdAt,
                attemptCount: 1,
                lastAttemptAt: createdAt,
                supersededByMutationID: UUID().uuidString.lowercased()
            ))
        }
        do {
            _ = try TildoneRepository(descriptor: descriptor, replicaID: replica)
            XCTFail("Expected malformed supersession")
        } catch {
            guard case let .malformedRepresentation(_, safeID, field) = error as? PersistenceError else {
                return XCTFail("Expected typed malformed representation, got \(error)")
            }
            XCTAssertEqual(safeID, "invalid")
            XCTAssertEqual(field, "supersession")
        }
    }

    func testOutboxRestartRetryAndStaleAcknowledgementPreserveNewerWork() async throws {
        let base = try temporaryDirectory()
        let descriptor = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .localOnly)
        let oldID: UUID
        let newID: UUID
        do {
            let repository = try TildoneRepository(descriptor: descriptor, replicaID: replica)
            _ = try await repository.createNote(id: noteID, createdAt: createdAt, title: "first")
            oldID = try await repository.pendingMutations()[0].id
            try await repository.recordMutationAttempt(id: oldID, at: createdAt)
            _ = try await repository.renameNote(id: noteID, to: "newer", editedAt: createdAt)
            newID = try await repository.pendingMutations()[0].id
        }

        do {
            let repository = try TildoneRepository(descriptor: descriptor, replicaID: ReplicaID())
            let all = try await repository.pendingMutations(includeSuperseded: true)
            XCTAssertEqual(all.count, 2)
            XCTAssertEqual(all.first(where: { $0.id == oldID })?.supersededBy, newID)
            try await repository.acknowledgeMutations(ids: [oldID])
            let activeIDs = try await repository.pendingMutations().map(\.id)
            XCTAssertEqual(activeIDs, [newID])
            try await repository.recordMutationAttempt(id: newID, at: createdAt.addingTimeInterval(1))
        }

        let reopened = try TildoneRepository(descriptor: descriptor, replicaID: ReplicaID())
        let retried = try await reopened.pendingMutations()[0]
        XCTAssertEqual(retried.id, newID)
        XCTAssertEqual(retried.attemptCount, 1)
        XCTAssertEqual(retried.lastAttemptAt, createdAt.addingTimeInterval(1))
        try await reopened.acknowledgeMutations(ids: [oldID])
        let activeIDs = try await reopened.pendingMutations().map(\.id)
        XCTAssertEqual(activeIDs, [newID])
        try await reopened.acknowledgeMutations(ids: [newID])
        let empty = try await reopened.pendingMutations(includeSuperseded: true)
        XCTAssertTrue(empty.isEmpty)
    }

    func testAcknowledgingNewerWorkReconcilesSupersededAncestors() async throws {
        let repository = try makeRepository()
        _ = try await repository.createNote(id: noteID, createdAt: createdAt, title: "first")
        let oldID = try await repository.pendingMutations()[0].id
        try await repository.recordMutationAttempt(id: oldID, at: createdAt)
        _ = try await repository.renameNote(id: noteID, to: "newer", editedAt: createdAt)
        let newID = try await repository.pendingMutations()[0].id

        try await repository.acknowledgeMutations(ids: [newID])
        let reconciled = try await repository.pendingMutations(includeSuperseded: true)
        XCTAssertTrue(reconciled.isEmpty)
        try await repository.acknowledgeMutations(ids: [oldID])
        let staleAcknowledgement = try await repository.pendingMutations(includeSuperseded: true)
        XCTAssertTrue(staleAcknowledgement.isEmpty)
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
        XCTAssertEqual(versions[1].logicalCounter, versions[0].logicalCounter + 2)
        let workspace = try await repository.workspaceSnapshot()
        let finalNote = try await repository.note(id: noteID)
        XCTAssertEqual(workspace.logicalCounter, finalNote.lastMeaningfulEditVersion.logicalCounter)
        XCTAssertEqual(workspace.logicalCounter, versions[1].logicalCounter + 1)
    }

    func testSchemaAndMigrationPlanAreDeliberatelyWired() {
        XCTAssertEqual(TildoneSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(TildoneSchemaV1.models.count, 5)
        XCTAssertEqual(TildoneSchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(TildoneSchemaV2.models.count, 7)
        XCTAssertEqual(TildoneSchemaMigrationPlan.schemas.count, 2)
        XCTAssertEqual(TildoneSchemaMigrationPlan.stages.count, 1)
    }

    func testActualV1OnDiskFixtureOpensThroughMigrationPlan() async throws {
        let resource = try XCTUnwrap(Bundle.module.url(
            forResource: "TildoneSharedStoreV1",
            withExtension: nil,
            subdirectory: "Fixtures"
        ))
        let temporaryRoot = try temporaryDirectory()
        let fixtureBase = temporaryRoot.appendingPathComponent("copied-v1", isDirectory: true)
        try FileManager.default.copyItem(at: resource, to: fixtureBase)

        let repository = try TildoneRepository(
            descriptor: .persistent(baseDirectory: fixtureBase, workspace: .localOnly),
            replicaID: ReplicaID()
        )
        let fixtureNoteID = NoteID(UUID(uuidString: "abcdef00-0000-0000-0000-000000000002")!)
        let fixtureTaskID = TaskID(UUID(uuidString: "abcdef00-0000-0000-0000-000000000003")!)
        let note = try await repository.note(id: fixtureNoteID)
        let task = try await repository.task(id: fixtureTaskID)
        let workspace = try await repository.workspaceSnapshot()
        let outbox = try await repository.pendingMutations(includeSuperseded: true)
        let quarantine = try await repository.quarantinedRecords()

        XCTAssertEqual(note.title, "V1 fixture 📝")
        XCTAssertEqual(task.text, "Preserved edited task café 漢字")
        XCTAssertEqual(workspace.replicaID.stringValue, "abcdef00-0000-0000-0000-000000000001")
        XCTAssertEqual(workspace.logicalCounter, 5)
        XCTAssertEqual(workspace.sharedSchemaVersion, 2)
        XCTAssertEqual(workspace.futureSyncEngineState, Data([0x01, 0x02, 0xff]))
        XCTAssertEqual(outbox.count, 3)
        XCTAssertEqual(outbox.filter { $0.supersededBy != nil }.count, 1)
        XCTAssertEqual(quarantine.count, 1)
        XCTAssertEqual(quarantine[0].opaqueRecordID, "task-abcdef00-0000-0000-0000-000000000004")
    }

    func testReleased160LegacyFixtureRemainsByteForByteUntouched() async throws {
        let legacyURL = try XCTUnwrap(Bundle.module.url(
            forResource: "default",
            withExtension: "store",
            subdirectory: "Fixtures/TildoneLegacy160"
        ))
        let before = try Data(contentsOf: legacyURL)
        XCTAssertEqual(before.count, 77_824)

        let base = try temporaryDirectory()
        let descriptor = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .localOnly)
        let sharedURL = try XCTUnwrap(TildoneRepository.storeURL(for: descriptor))
        XCTAssertNotEqual(sharedURL.standardizedFileURL, legacyURL.standardizedFileURL)
        let repository = try TildoneRepository(descriptor: descriptor, replicaID: replica)
        _ = try await repository.createNote(id: noteID, createdAt: createdAt, title: "separate shared store")

        let after = try Data(contentsOf: legacyURL)
        XCTAssertEqual(after, before)
    }

    func testLegacyImportIsAtomicOutboxFreeIdempotentAndStableAcrossRestart() async throws {
        let base = try temporaryDirectory()
        let destination = base.appendingPathComponent("shared.sqlite")
        let descriptor = PersistenceStoreDescriptor.temporaryMigration(storeURL: destination)
        let fingerprint = migrationFingerprint()
        let counts = LegacyMigrationCounts(
            eligibleNotes: 1, eligibleTasks: 1, excludedSystemNotes: 1,
            excludedSystemTasks: 1, excludedTransientTasks: 1
        )
        let noteKey = String(repeating: "1", count: 64)
        let taskKey = String(repeating: "2", count: 64)
        let systemKey = String(repeating: "3", count: 64)
        let transientKey = String(repeating: "4", count: 64)
        let noteMapping: LegacyMappingSnapshot
        let taskMapping: LegacyMappingSnapshot

        do {
            let repository = try TildoneRepository(descriptor: descriptor, replicaID: replica)
            _ = try await repository.prepareLegacyMigration(
                formatVersion: 1, sourceFingerprint: fingerprint, sourceCounts: counts, at: createdAt
            )
            try await repository.advanceLegacyMigration(to: .sourceInspected, at: createdAt)
            try await repository.advanceLegacyMigration(to: .destinationPrepared, at: createdAt)
            let mappings = try await repository.prepareLegacyMappings([
                LegacyMappingRequest(legacyKey: noteKey, entityKind: .note, classification: .userContent),
                LegacyMappingRequest(
                    legacyKey: taskKey, entityKind: .task, classification: .userContent,
                    ownerLegacyKey: noteKey, visibleOrder: 0
                ),
                LegacyMappingRequest(
                    legacyKey: systemKey, entityKind: .note, classification: .excludedSystemNote
                ),
                LegacyMappingRequest(
                    legacyKey: transientKey, entityKind: .task,
                    classification: .excludedTransientEmptyTask,
                    ownerLegacyKey: noteKey, visibleOrder: 1
                )
            ], at: createdAt)
            noteMapping = mappings[0]
            taskMapping = mappings[1]
            XCTAssertNil(mappings[2].stableID)
            XCTAssertNil(mappings[3].stableID)

            let noteImport = LegacyImportedNote(
                legacyKey: noteKey, createdAt: createdAt, title: "", lastMeaningfulEditAt: createdAt
            )
            let taskImport = LegacyImportedTask(
                legacyKey: taskKey, ownerLegacyKey: noteKey, createdAt: createdAt,
                text: "Unicode 🧡\nCafé", completedAt: createdAt.addingTimeInterval(10),
                orderToken: try OrderToken(rawValue: "0000000000001h")
            )
            try await repository.importLegacyNotes([noteImport], at: createdAt)
            try await repository.importLegacyTasks([taskImport], at: createdAt)
            try await repository.importLegacyNotes([noteImport], at: createdAt)
            try await repository.importLegacyTasks([taskImport], at: createdAt)
            let pending = try await repository.pendingMutations(includeSuperseded: true)
            XCTAssertTrue(pending.isEmpty)
            let audit = try await repository.legacyMigrationAudit()
            XCTAssertEqual(audit.noteCount, 1)
            XCTAssertEqual(audit.taskCount, 1)
            XCTAssertEqual(audit.mappingCount, 4)
            XCTAssertFalse(audit.duplicateMappedStableIDs)
        }

        let reopened = try TildoneRepository(descriptor: descriptor, replicaID: ReplicaID())
        let reopenedNoteMapping = try await reopened.legacyMapping(for: noteKey)
        let reopenedTaskMapping = try await reopened.legacyMapping(for: taskKey)
        XCTAssertEqual(reopenedNoteMapping, noteMapping)
        XCTAssertEqual(reopenedTaskMapping, taskMapping)
        let note = try await reopened.note(id: NoteID(string: noteMapping.stableID!)!)
        let task = try await reopened.task(id: TaskID(string: taskMapping.stableID!)!)
        XCTAssertEqual(note.title, "")
        XCTAssertEqual(note.lifecycle, .active)
        XCTAssertEqual(task.text, "Unicode 🧡\nCafé")
        XCTAssertEqual(task.completedAt, createdAt.addingTimeInterval(10))
        XCTAssertEqual(task.noteID, note.id)
        XCTAssertEqual(task.textVersion.logicalCounter, taskMapping.firstVersionCounter)
        XCTAssertEqual(task.lifecycleVersion.logicalCounter, taskMapping.firstVersionCounter! + 3)
        XCTAssertEqual(note.titleVersion.replicaID, replica)
        XCTAssertEqual(task.textVersion.replicaID, replica)
    }

    func testLegacyMappingSaveFailureRollsBackMappingCounterAndContentTogether() async throws {
        let repository = try makeRepository()
        _ = try await repository.prepareLegacyMigration(
            formatVersion: 1,
            sourceFingerprint: migrationFingerprint(),
            sourceCounts: LegacyMigrationCounts(
                eligibleNotes: 1, eligibleTasks: 0, excludedSystemNotes: 0,
                excludedSystemTasks: 0, excludedTransientTasks: 0
            ),
            at: createdAt
        )
        try await repository.advanceLegacyMigration(to: .sourceInspected, at: createdAt)
        try await repository.advanceLegacyMigration(to: .destinationPrepared, at: createdAt)
        let before = try await repository.workspaceSnapshot().logicalCounter
        await repository.failNextSaveForTesting()
        await XCTAssertThrowsLegacyMigrationError(.saveFailure) {
            _ = try await repository.prepareLegacyMappings([
                LegacyMappingRequest(
                    legacyKey: String(repeating: "5", count: 64),
                    entityKind: .note,
                    classification: .userContent
                )
            ], at: self.createdAt)
        }
        let workspaceAfterFailure = try await repository.workspaceSnapshot()
        let auditAfterFailure = try await repository.legacyMigrationAudit()
        XCTAssertEqual(workspaceAfterFailure.logicalCounter, before)
        XCTAssertEqual(auditAfterFailure.mappingCount, 0)
    }

    func testLegacyFailureIsDurableAndRequiresExplicitResume() async throws {
        let repository = try makeRepository()
        let counts = LegacyMigrationCounts.zero
        _ = try await repository.prepareLegacyMigration(
            formatVersion: 1, sourceFingerprint: migrationFingerprint(), sourceCounts: counts, at: createdAt
        )
        try await repository.advanceLegacyMigration(to: .sourceInspected, at: createdAt)
        try await repository.recordLegacyMigrationFailure(.sourceChanged, at: createdAt.addingTimeInterval(1))
        var failed = try await repository.legacyMigrationSnapshot()
        XCTAssertEqual(failed.phase, .failed)
        XCTAssertEqual(failed.lastCompletedPhase, .sourceInspected)
        XCTAssertEqual(failed.failureCategory, .sourceChanged)
        await XCTAssertThrowsLegacyMigrationError(.incompatibleExistingState(.priorFailedDestination)) {
            _ = try await repository.prepareLegacyMigration(
                formatVersion: 1,
                sourceFingerprint: self.migrationFingerprint(),
                sourceCounts: counts,
                at: self.createdAt
            )
        }
        try await repository.resumeFailedLegacyMigration(at: createdAt.addingTimeInterval(2))
        failed = try await repository.legacyMigrationSnapshot()
        XCTAssertEqual(failed.phase, .sourceInspected)
        XCTAssertNil(failed.failureCategory)
    }

    func testOnlyVerifiedEligibleMigrationCanActivateAndActivationIsDurable() async throws {
        let repository = try makeRepository()
        _ = try await repository.prepareLegacyMigration(
            formatVersion: 1,
            sourceFingerprint: migrationFingerprint(),
            sourceCounts: .zero,
            at: createdAt
        )
        await XCTAssertThrowsLegacyMigrationError(.invalidState) {
            _ = try await repository.activateVerifiedLegacyMigration(at: self.createdAt)
        }
        try await repository.advanceLegacyMigration(to: .sourceInspected, at: createdAt)
        try await repository.advanceLegacyMigration(to: .destinationPrepared, at: createdAt)
        try await repository.advanceLegacyMigration(to: .copyInProgress, at: createdAt)
        try await repository.advanceLegacyMigration(to: .copyCompleted, at: createdAt)
        try await repository.advanceLegacyMigration(to: .verificationInProgress, at: createdAt)
        try await repository.advanceLegacyMigration(to: .verified, at: createdAt)
        try await repository.advanceLegacyMigration(to: .eligibleForCutover, at: createdAt)

        let activated = try await repository.activateVerifiedLegacyMigration(at: createdAt.addingTimeInterval(1))
        XCTAssertEqual(activated.phase, .eligibleForCutover)
        XCTAssertEqual(activated.activationState, .activated)
        XCTAssertFalse(activated.cloudSeedingEverBegun)
        let pending = try await repository.pendingMutations(includeSuperseded: true)
        XCTAssertTrue(pending.isEmpty)
        await XCTAssertThrowsLegacyMigrationError(.invalidState) {
            _ = try await repository.activateVerifiedLegacyMigration(at: self.createdAt.addingTimeInterval(2))
        }
    }

    func testLegacyStateRejectsDifferentCopiedChangedAndUpgradedSources() async throws {
        let repository = try makeRepository()
        _ = try await repository.prepareLegacyMigration(
            formatVersion: 1,
            sourceFingerprint: migrationFingerprint(),
            sourceCounts: .zero,
            at: createdAt
        )
        let differentIdentity = LegacySourceFingerprint(
            identityDigest: String(repeating: "c", count: 64),
            contentDigest: String(repeating: "b", count: 64),
            fileCount: 1,
            totalByteCount: 100
        )
        await XCTAssertThrowsLegacyMigrationError(.incompatibleExistingState(.differentSource)) {
            _ = try await repository.prepareLegacyMigration(
                formatVersion: 1, sourceFingerprint: differentIdentity, sourceCounts: .zero, at: self.createdAt
            )
        }
        let changed = LegacySourceFingerprint(
            identityDigest: String(repeating: "a", count: 64),
            contentDigest: String(repeating: "d", count: 64),
            fileCount: 1,
            totalByteCount: 100
        )
        await XCTAssertThrowsLegacyMigrationError(.incompatibleExistingState(.sourceChanged)) {
            _ = try await repository.prepareLegacyMigration(
                formatVersion: 1, sourceFingerprint: changed, sourceCounts: .zero, at: self.createdAt
            )
        }
        await XCTAssertThrowsLegacyMigrationError(.incompatibleExistingState(.migrationVersionMismatch)) {
            _ = try await repository.prepareLegacyMigration(
                formatVersion: 2,
                sourceFingerprint: self.migrationFingerprint(),
                sourceCounts: .zero,
                at: self.createdAt
            )
        }
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
            titleVersion: stamp(1), lifecycleVersion: stamp(1), lastMeaningfulEditAt: createdAt,
            lastMeaningfulEditVersion: stamp(1)
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

    private func migrationFingerprint() -> LegacySourceFingerprint {
        LegacySourceFingerprint(
            identityDigest: String(repeating: "a", count: 64),
            contentDigest: String(repeating: "b", count: 64),
            fileCount: 1,
            totalByteCount: 100
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TildonePersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func withRawStore(
        _ descriptor: PersistenceStoreDescriptor,
        body: (ModelContext) throws -> Void
    ) throws {
        let url = try XCTUnwrap(TildoneRepository.storeURL(for: descriptor))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let schema = Schema(versionedSchema: TildoneSchemaV1.self)
        let configuration = ModelConfiguration(
            "RawTestStore-\(UUID().uuidString)",
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TildoneSchemaMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try body(context)
        try context.save()
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

    func XCTAssertThrowsLegacyMigrationError(
        _ expected: LegacyMigrationPersistenceError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? LegacyMigrationPersistenceError, expected)
        }
    }
}
