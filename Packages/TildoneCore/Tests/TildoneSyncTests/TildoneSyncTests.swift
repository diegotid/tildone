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

    func testTransportDefaultsAreAutomaticOnlyForNonTestDebugBuilds() {
        XCTAssertTrue(TransportDefaultPolicy.isEnabled(
            buildMode: .debug,
            isTestProcess: false
        ))
        XCTAssertFalse(TransportDefaultPolicy.isEnabled(
            buildMode: .debug,
            isTestProcess: true
        ))
        XCTAssertFalse(TransportDefaultPolicy.isEnabled(
            buildMode: .release,
            isTestProcess: false
        ))
        XCTAssertFalse(TransportDefaultPolicy.isEnabled(
            buildMode: .release,
            isTestProcess: true
        ))
    }

    func testFrozenLocalRefreshFailureCannotReturnToHealthyCheckpointStatus() {
        let failure = SyncStatus(
            availability: .available,
            activity: .attentionNeeded,
            pendingMutationCount: 2,
            lastSuccessfulSyncAt: date.addingTimeInterval(-10),
            issue: .unknown
        )
        let laterCheckpoint = SyncStatus(
            availability: .available,
            activity: .idle,
            pendingMutationCount: 0,
            lastSuccessfulSyncAt: date,
            issue: nil
        )

        let resolved = SyncStatusLatchPolicy.resolve(
            requested: laterCheckpoint,
            current: failure,
            zoneResetRequired: false,
            coordinatorFrozen: true
        )

        XCTAssertEqual(resolved.activity, .attentionNeeded)
        XCTAssertEqual(resolved.issue, .unknown)
        XCTAssertEqual(resolved.lastSuccessfulSyncAt, failure.lastSuccessfulSyncAt)
    }

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
        XCTAssertEqual(TildoneCloudSchema.clientRecordType, "TDClient")
        let noteRecord = mapper.record(from: .note(fixture.note))
        XCTAssertEqual(noteRecord["color"] as? String, fixture.note.color.rawValue)
        XCTAssertNotNil(noteRecord["colorVersionCounter"])
    }

    func testDevelopmentContractManifestMatchesEveryEncodedMapperField() throws {
        let mapper = CloudKitRecordMapper()
        let fixture = Fixture()
        let contracts = Dictionary(
            uniqueKeysWithValues: DevelopmentCloudKitContractManifest.records.map {
                ("\($0.recordType)-\($0.schemaVersion)", $0)
            }
        )
        XCTAssertEqual(Set(contracts.keys), Set(["TDNote-1", "TDNote-2", "TDTask-1", "TDClient-1"]))

        let v1Note = Note(
            id: fixture.note.id, createdAt: fixture.note.createdAt,
            title: fixture.note.title, titleVersion: fixture.note.titleVersion,
            lifecycle: fixture.note.lifecycle, lifecycleVersion: fixture.note.lifecycleVersion,
            lastMeaningfulEditAt: fixture.note.lastMeaningfulEditAt,
            lastMeaningfulEditVersion: fixture.note.lastMeaningfulEditVersion,
            schemaVersion: 1
        )
        let records: [(String, CKRecord)] = [
            ("TDNote-1", mapper.record(from: .note(v1Note))),
            ("TDNote-2", mapper.record(from: .note(fixture.note))),
            ("TDTask-1", mapper.record(from: .task(fixture.task))),
            ("TDClient-1", mapper.clientRecord(replicaID: ReplicaID(UUID(int: 601)), platform: .mac))
        ]
        for (key, record) in records {
            let contract = try XCTUnwrap(contracts[key])
            XCTAssertEqual(Set(record.allKeys()), Set(contract.fields.map(\.name)), key)
        }

        let contentManifestFields = Set(
            try XCTUnwrap(contracts["TDNote-2"]).fields.map(\.name) +
            (try XCTUnwrap(contracts["TDTask-1"])).fields.map(\.name)
        )
        XCTAssertEqual(contentManifestFields, Set(CloudKitRecordMapper.Field.all))
        XCTAssertEqual(DevelopmentCloudKitContractManifest.database, "private")
        XCTAssertEqual(DevelopmentCloudKitContractManifest.zoneOwner, "CKCurrentUserDefaultName")

        let optionalByRecord = contracts.mapValues { contract in
            Set(contract.fields.filter(\.optional).map(\.name))
        }
        XCTAssertEqual(optionalByRecord["TDNote-1"], Set(["title"]))
        XCTAssertEqual(optionalByRecord["TDNote-2"], Set(["title"]))
        XCTAssertEqual(optionalByRecord["TDTask-1"], Set(["completedAt"]))
        XCTAssertEqual(optionalByRecord["TDClient-1"], Set<String>())
    }

    func testCloudMapperReadsV1NotesWithoutColorAndUsesDeterministicFallback() throws {
        let mapper = CloudKitRecordMapper()
        let fixture = Fixture()
        let record = mapper.record(from: .note(fixture.note))
        record["schemaVersion"] = NSNumber(value: 1)
        record["color"] = nil
        record["colorVersionCounter"] = nil
        record["colorVersionReplicaID"] = nil

        guard case let .note(note) = try mapper.syncRecord(from: record) else {
            return XCTFail("Expected a note")
        }
        XCTAssertEqual(note.schemaVersion, 1)
        XCTAssertEqual(note.color, .yellow)
        XCTAssertEqual(note.colorVersion, note.titleVersion)
    }

    func testLateV1CloudNoteIsBackfilledAndQueuedAsCurrentSchema() async throws {
        let replica = try Replica(id: 90)
        let mapper = CloudKitRecordMapper()
        let fixture = Fixture()
        let record = mapper.record(from: .note(fixture.note))
        record["schemaVersion"] = NSNumber(value: 1)
        record["color"] = nil
        record["colorVersionCounter"] = nil
        record["colorVersionReplicaID"] = nil

        let legacy = try mapper.syncRecord(from: record)
        _ = try await replica.pipeline.apply([legacy], at: date)
        let pendingBeforeMigration = try await replica.pipeline.pendingCount()
        XCTAssertEqual(pendingBeforeMigration, 0)

        try await replica.repository.migrateMissingNoteColors(
            colorsByNoteID: [fixture.note.id: .purple],
            defaultColor: .green
        )

        let migrated = try await replica.repository.note(id: fixture.note.id)
        XCTAssertEqual(migrated.schemaVersion, Note.currentSchemaVersion)
        XCTAssertEqual(migrated.color, .purple)
        let pendingAfterMigration = try await replica.pipeline.pendingCount()
        XCTAssertEqual(pendingAfterMigration, 1)
        let outbound = try await replica.pipeline.prepareOutboundMutation(
            recordName: fixture.note.id.recordName,
            at: date
        )
        guard case let .note(note)? = outbound?.record else {
            return XCTFail("Expected a queued note mutation")
        }
        XCTAssertEqual(note.schemaVersion, Note.currentSchemaVersion)
        XCTAssertEqual(note.color, .purple)
    }

    func testMacColorBackfillConvergesOverPhoneDefaultInBothUpgradeOrders() async throws {
        for macUploadsFirst in [true, false] {
            let mac = try Replica(id: macUploadsFirst ? 101 : 103)
            let phone = try Replica(id: macUploadsFirst ? 102 : 104)
            let noteID = NoteID(UUID(int: macUploadsFirst ? 110 : 120))
            let legacyReplica = ReplicaID(UUID(int: 99))
            let legacyStamp = VersionStamp(logicalCounter: 7, replicaID: legacyReplica)
            let v1 = Note(
                id: noteID,
                createdAt: date,
                title: "V1",
                titleVersion: legacyStamp,
                color: .yellow,
                colorVersion: legacyStamp,
                lifecycleVersion: legacyStamp,
                lastMeaningfulEditAt: date,
                lastMeaningfulEditVersion: legacyStamp,
                schemaVersion: 1
            )
            _ = try await mac.pipeline.apply([.note(v1)], at: date)
            _ = try await phone.pipeline.apply([.note(v1)], at: date)
            var server: [String: SyncRecord] = [:]
            if macUploadsFirst {
                try await mac.repository.migrateMissingNoteColors(
                    colorsByNoteID: [noteID: .orange],
                    authority: .legacyMac
                )
                try await upload(mac, server: &server)
                try await deliver(server, to: phone)
                try await phone.repository.migrateMissingNoteColors(
                    colorsByNoteID: [:],
                    authority: .platformDefault
                )
                try await upload(phone, server: &server)
            } else {
                try await phone.repository.migrateMissingNoteColors(
                    colorsByNoteID: [:],
                    authority: .platformDefault
                )
                try await upload(phone, server: &server)
                try await deliver(server, to: mac)
                let deliveredBeforeMacUpgrade = try await mac.repository.note(id: noteID)
                XCTAssertEqual(deliveredBeforeMacUpgrade.color, .yellow)
                XCTAssertEqual(
                    NoteColorMigrationAuthority.authority(
                        for: deliveredBeforeMacUpgrade.colorVersion.replicaID
                    ),
                    .platformDefault
                )
                try await mac.repository.migrateMissingNoteColors(
                    colorsByNoteID: [noteID: .orange],
                    authority: .legacyMac
                )
                try await upload(mac, server: &server)
            }
            try await converge([phone, mac], server: &server)

            for replica in [mac, phone] {
                let note = try await replica.repository.note(id: noteID)
                XCTAssertEqual(note.color, .orange)
                XCTAssertEqual(
                    NoteColorMigrationAuthority.authority(for: note.colorVersion.replicaID),
                    .legacyMac
                )
                let pendingCount = try await replica.pipeline.pendingCount()
                XCTAssertEqual(pendingCount, 0)
            }
        }
    }

    func testExistingV2RemoteColorBeatsBackfillDuringServerConflictRetry() async throws {
        let replica = try Replica(id: 130)
        let noteID = NoteID(UUID(int: 131))
        let baseStamp = VersionStamp(logicalCounter: 5, replicaID: ReplicaID(UUID(int: 132)))
        let v1 = Note(
            id: noteID, createdAt: date, title: nil, titleVersion: baseStamp,
            lifecycleVersion: baseStamp, lastMeaningfulEditAt: date,
            lastMeaningfulEditVersion: baseStamp, schemaVersion: 1
        )
        _ = try await replica.pipeline.apply([.note(v1)], at: date)
        try await replica.repository.migrateMissingNoteColors(
            colorsByNoteID: [noteID: .green],
            authority: .legacyMac
        )

        let remoteStamp = VersionStamp(logicalCounter: 1, replicaID: ReplicaID(UUID(int: 133)))
        let existingV2 = Note(
            id: noteID, createdAt: date, title: nil, titleVersion: baseStamp,
            color: .purple, colorVersion: remoteStamp,
            lifecycleVersion: baseStamp, lastMeaningfulEditAt: date,
            lastMeaningfulEditVersion: baseStamp, schemaVersion: 2
        )
        _ = try await replica.pipeline.apply([.note(existingV2)], at: date)
        let merged = try await replica.repository.note(id: noteID)
        XCTAssertEqual(merged.color, .purple)

        let outbound = try await replica.pipeline.prepareOutboundMutation(
            recordName: noteID.recordName,
            at: date
        )
        guard case let .note(retry)? = outbound?.record else {
            return XCTFail("Expected retry payload")
        }
        XCTAssertEqual(retry.color, .purple)
        XCTAssertEqual(retry.colorVersion, remoteStamp)
    }

    func testClientRegistrationCloudRecordIsContentFreeAndRoundTrips() throws {
        let mapper = CloudKitRecordMapper()
        let replicaID = ReplicaID(UUID(int: 3))
        let observedAt = date.addingTimeInterval(10)
        let record = mapper.clientRecord(replicaID: replicaID, platform: .iPhone)

        XCTAssertEqual(record.recordType, TildoneCloudSchema.clientRecordType)
        XCTAssertEqual(record.recordID.recordName, "client-" + replicaID.stringValue)
        XCTAssertEqual(Set(record.allKeys()), Set(["schemaVersion", "replicaID", "platform"]))
        XCTAssertNil(record["title"])
        XCTAssertNil(record["text"])

        let registration = try mapper.clientRegistration(
            from: record,
            observedAt: observedAt
        )
        XCTAssertEqual(registration.replicaID, replicaID)
        XCTAssertEqual(registration.platform, .iPhone)
        XCTAssertEqual(registration.lastSeenAt, observedAt)
    }

    func testClientActivityCountsCurrentAndRecentInstallationsOnly() {
        let current = ReplicaID(UUID(int: 1))
        let recent = ReplicaID(UUID(int: 2))
        let stale = ReplicaID(UUID(int: 3))
        let registrations = [
            recent.stringValue: SyncClientRegistration(
                replicaID: recent,
                platform: .mac,
                lastSeenAt: date.addingTimeInterval(-SyncClientActivityPolicy.activeWindow + 1)
            ),
            stale.stringValue: SyncClientRegistration(
                replicaID: stale,
                platform: .iPhone,
                lastSeenAt: date.addingTimeInterval(-SyncClientActivityPolicy.activeWindow - 1)
            )
        ]

        let summary = SyncClientActivityPolicy.activeDeviceSummary(
            registrations: registrations,
            currentReplicaID: current,
            currentPlatform: .iPhone,
            at: date
        )
        XCTAssertEqual(summary.currentPlatform, .iPhone)
        XCTAssertEqual(summary.otherIPhoneCount, 0)
        XCTAssertEqual(summary.otherIPadCount, 0)
        XCTAssertEqual(summary.otherMacCount, 1)
        XCTAssertEqual(summary.totalDeviceCount, 2)
        XCTAssertTrue(SyncClientActivityPolicy.shouldRefresh(registration: nil, at: date))
        let freshHeartbeat = SyncClientRegistration(
            replicaID: current,
            platform: .iPhone,
            lastSeenAt: date.addingTimeInterval(-SyncClientActivityPolicy.heartbeatInterval + 1)
        )
        XCTAssertFalse(SyncClientActivityPolicy.shouldRefresh(
            registration: freshHeartbeat,
            at: date
        ))
        let oldHeartbeat = SyncClientRegistration(
            replicaID: current,
            platform: .iPhone,
            lastSeenAt: date.addingTimeInterval(-SyncClientActivityPolicy.heartbeatInterval)
        )
        XCTAssertTrue(SyncClientActivityPolicy.shouldRefresh(
            registration: oldHeartbeat,
            at: date
        ))
    }

    func testPersistentStateDecodesDataFromBeforeClientRegistrations() throws {
        struct LegacyPersistentState: Codable {
            let version: Int
            let engineSerialization: Data?
            let systemFieldsByRecordName: [String: Data]
            let zoneCreated: Bool
            let zoneResetRequired: Bool
        }

        let data = try PropertyListEncoder().encode(LegacyPersistentState(
            version: SyncPersistentState.currentVersion,
            engineSerialization: nil,
            systemFieldsByRecordName: [:],
            zoneCreated: true,
            zoneResetRequired: false
        ))
        let restored = SyncPersistentState(data: data)

        XCTAssertTrue(restored.zoneCreated)
        XCTAssertFalse(restored.zoneResetRequired)
        XCTAssertTrue(restored.clientRegistrationsByReplicaID.isEmpty)
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

    func testOutboundPreparationSurvivesConcurrentTaskDeletion() async throws {
        let repository = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(UUID(int: 92))),
            replicaID: ReplicaID(UUID(int: 93)),
            now: { self.date }
        )
        let noteID = NoteID(UUID(int: 94))
        let taskID = TaskID(UUID(int: 95))
        _ = try await repository.createNote(id: noteID, createdAt: date, title: nil)
        _ = try await repository.addTask(
            id: taskID,
            to: noteID,
            createdAt: date,
            text: "Before deletion",
            orderToken: try OrderToken(rawValue: "m")
        )

        let gate = OutboundClaimGate()
        let pipeline = SyncPipeline(
            repository: repository,
            beforeOutboundClaim: { await gate.pause() }
        )
        let preparation = Swift.Task {
            try await pipeline.prepareOutboundMutation(
                recordName: taskID.recordName,
                at: date.addingTimeInterval(1)
            )
        }

        await gate.waitUntilPaused()
        try await repository.deleteTask(id: taskID)
        await gate.resume()

        let prepared = try await preparation.value
        let outbound = try XCTUnwrap(prepared)
        guard case let .task(task) = outbound.record else {
            return XCTFail("Expected a task mutation")
        }
        XCTAssertEqual(task.lifecycle, .deleted)
        let pending = try await repository.pendingMutations()
        let pendingTask = try XCTUnwrap(
            pending.first { mutation in
                mutation.targetKind == .task && mutation.targetStableID == taskID.stringValue
            }
        )
        XCTAssertEqual(pendingTask.id, outbound.mutationID)
        XCTAssertEqual(pendingTask.attemptCount, 1)
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

    func testZoneResetStatusStaysLatchedAcrossCheckpointAndLocalChanges() {
        let lastSuccessfulSyncAt = date
        let current = SyncStatus(
            availability: .zoneResetRequired,
            activity: .attentionNeeded,
            pendingMutationCount: 0,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
            issue: .zoneReset
        )
        let requestedStatuses = [
            SyncStatus(
                availability: .available,
                activity: .idle,
                pendingMutationCount: 0,
                lastSuccessfulSyncAt: date.addingTimeInterval(10),
                issue: nil
            ),
            SyncStatus(
                availability: .available,
                activity: .syncing,
                pendingMutationCount: 1,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                issue: nil
            )
        ]

        for requested in requestedStatuses {
            let resolved = SyncStatusLatchPolicy.resolve(
                requested: requested,
                current: current,
                zoneResetRequired: true
            )
            XCTAssertEqual(resolved.availability, .zoneResetRequired)
            XCTAssertEqual(resolved.activity, .attentionNeeded)
            XCTAssertEqual(resolved.pendingMutationCount, requested.pendingMutationCount)
            XCTAssertEqual(resolved.lastSuccessfulSyncAt, lastSuccessfulSyncAt)
            XCTAssertEqual(resolved.issue, .zoneReset)
        }
    }

    func testZoneBootstrapDefersRecordsAndMissingZoneLatchUntilCreation() {
        XCTAssertFalse(SyncZoneBootstrapPolicy.shouldScheduleRecordChanges(
            zoneCreated: false,
            zoneResetRequired: false
        ))
        XCTAssertFalse(SyncZoneBootstrapPolicy.shouldLatchMissingZone(
            zoneCreated: false
        ))

        XCTAssertTrue(SyncZoneBootstrapPolicy.shouldScheduleRecordChanges(
            zoneCreated: true,
            zoneResetRequired: false
        ))
        XCTAssertTrue(SyncZoneBootstrapPolicy.shouldLatchMissingZone(
            zoneCreated: true
        ))

        XCTAssertFalse(SyncZoneBootstrapPolicy.shouldScheduleRecordChanges(
            zoneCreated: true,
            zoneResetRequired: true
        ))
    }

    func testLateZoneSaveCannotClearFrozenZoneReset() async throws {
        let repository = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(UUID(int: 808)))
        )
        let state = SyncCoordinatorState(
            persistent: SyncPersistentState(),
            repository: repository
        )

        try await state.freezeForZoneReset()
        let didMarkCreated = try await state.markZoneCreated()

        let persistent = await state.snapshot()
        let isFrozen = await state.isFrozen()
        XCTAssertFalse(didMarkCreated)
        XCTAssertFalse(persistent.zoneCreated)
        XCTAssertTrue(persistent.zoneResetRequired)
        XCTAssertTrue(isFrozen)
    }

    func testZoneSaveConfirmationEnablesRecordBootstrap() async throws {
        let repository = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(UUID(int: 809)))
        )
        let state = SyncCoordinatorState(
            persistent: SyncPersistentState(),
            repository: repository
        )

        let didMarkCreated = try await state.markZoneCreated()

        let persistent = await state.snapshot()
        let isFrozen = await state.isFrozen()
        XCTAssertTrue(didMarkCreated)
        XCTAssertTrue(persistent.zoneCreated)
        XCTAssertFalse(persistent.zoneResetRequired)
        XCTAssertFalse(isFrozen)
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
                color: .purple,
                colorVersion: stamp,
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

private actor OutboundClaimGate {
    private var isPaused = false
    private var pausedContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
            isPaused = true
            pausedContinuation?.resume()
            pausedContinuation = nil
        }
    }

    func waitUntilPaused() async {
        if isPaused { return }
        await withCheckedContinuation { continuation in
            pausedContinuation = continuation
        }
    }

    func resume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
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
