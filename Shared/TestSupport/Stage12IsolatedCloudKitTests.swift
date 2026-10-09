import CloudKit
import CryptoKit
import Foundation
import XCTest
import TildoneDomain
import TildonePersistence
@testable import TildoneSync

/// Hosted by either signed Development app; normal launches remain transport-off.
/// All service access is opt-in and limited to freshly generated synthetic IDs.
final class Stage12IsolatedCloudKitTests: XCTestCase {
    /// Opens only an independently verified copy of the immutable V2 resource.
    /// Does not resolve an installed app store, account, CloudKit zone or record.
    func testFrozenV2StoreMigrationAndReopenOnHostedPlatform() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "TildoneSharedStoreV2", withExtension: nil))
        let account = try XCTUnwrap(UUID(uuidString: "abcdef00-0000-0000-0000-000000000010"))
        let noteID = NoteID(try XCTUnwrap(UUID(uuidString: "abcdef00-0000-0000-0000-000000000012")))
        let relativeStore = "TildoneSharedStore-v1/accounts/abcdef00-0000-0000-0000-000000000010/tildone-shared.sqlite"
        let source = fixture.appendingPathComponent(relativeStore)
        let original = try Data(contentsOf: source)
        let checksum = SHA256.hash(data: original).map { String(format: "%02x", $0) }.joined()
        guard checksum == "e034619f0701283acfbc62f9817ac7f25149eb4061a1a98b7712980e03b6bb25" else {
            return XCTFail("Frozen V2 resource checksum mismatch; no store opened")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stage12-frozen-v2-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: fixture, to: root)
        let descriptor = PersistenceStoreDescriptor.persistent(baseDirectory: root, workspace: .account(account))
        func migrateAndClose() async throws -> (VersionStamp, [PendingMutationSnapshot], Int) {
            let repository = try TildoneRepository(descriptor: descriptor)
            let old = try await repository.note(id: noteID)
            XCTAssertEqual(old.schemaVersion, 1)
            XCTAssertEqual(old.color, .yellow)
            let evidence = try await repository.legacyMigrationSnapshot()
            XCTAssertEqual(evidence.activationState, .activated)
            XCTAssertTrue(evidence.cloudSeedingEverBegun)
            let baselineQuarantine = try await repository.quarantinedRecords().count
            try await repository.migrateMissingNoteColors(colorsByNoteID: [noteID: .orange], authority: .legacyMac)
            let migrated = try await repository.note(id: noteID)
            XCTAssertEqual(migrated.color, .orange)
            XCTAssertEqual(NoteColorMigrationAuthority.authority(for: migrated.colorVersion.replicaID), .legacyMac)
            let outbox = try await repository.pendingMutations(includeSuperseded: true)
            XCTAssertTrue(outbox.contains { $0.targetStableID == noteID.stringValue && $0.supersededBy == nil })
            return (migrated.colorVersion, outbox, baselineQuarantine)
        }
        let (version, outbox, quarantineCount) = try await migrateAndClose()
        let reopened = try TildoneRepository(descriptor: descriptor)
        let after = try await reopened.note(id: noteID)
        XCTAssertEqual(after.color, .orange)
        XCTAssertEqual(after.colorVersion, version)
        XCTAssertEqual(after.singleMemoFont, .overlock)
        let retainedOutbox = try await reopened.pendingMutations(includeSuperseded: true)
        XCTAssertEqual(retainedOutbox, outbox)
        let retainedQuarantine = try await reopened.quarantinedRecords().count
        XCTAssertEqual(retainedQuarantine, quarantineCount)
        XCTAssertEqual(try Data(contentsOf: source), original)
        print("TildoneIsolatedQualification case=frozen-v2-store status=passed count=1")
    }

    private enum Stage12IsolatedFixtureError: Error {
        case unexpectedExistingRecord
        case unexpectedCloudFailure(Int)
        case missingServerConflictRecord
    }

    private func stage12IsolatedDevelopmentDatabase() async throws -> CKDatabase {
        guard ProcessInfo.processInfo.environment["TILDONE_STAGE12_ISOLATED_RECORD_TESTS"]
                == "iCloud.studio.cuatro.tildone:Development:fixture-records-only" else {
            throw XCTSkip("Stage 12 isolated Development records require explicit opt-in")
        }
        let container = CKContainer(identifier: TildoneCloudSchema.containerIdentifier)
        guard try await container.accountStatus() == .available else {
            throw XCTSkip("The approved Development account must be available")
        }
        let database = container.privateCloudDatabase
        // Metadata read only: never create/recreate a zone in this qualification.
        let zone = try await database.recordZone(for: TildoneCloudSchema.zoneID)
        XCTAssertEqual(zone.zoneID, TildoneCloudSchema.zoneID)
        return database
    }

    private func requireNewStage12FixtureIDs(
        _ ids: [CKRecord.ID], database: CKDatabase
    ) async throws {
        let results = try await database.records(for: ids)
        for id in ids {
            guard let result = results[id] else {
                throw Stage12IsolatedFixtureError.unexpectedExistingRecord
            }
            switch result {
            case .success:
                // Do not log or overwrite an unexpected existing payload.
                throw Stage12IsolatedFixtureError.unexpectedExistingRecord
            case let .failure(error):
                guard (error as? CKError)?.code == .unknownItem else {
                    throw Stage12IsolatedFixtureError.unexpectedCloudFailure(
                        (error as? CKError)?.code.rawValue ?? -1
                    )
                }
            }
        }
    }

    private func saveStage12Fixture(
        _ record: CKRecord, database: CKDatabase
    ) async throws -> CKRecord {
        let results = try await database.modifyRecords(
            saving: [record], deleting: [],
            savePolicy: .ifServerRecordUnchanged, atomically: false
        )
        return try XCTUnwrap(results.saveResults[record.recordID]).get()
    }

    /// Uses one new content-free replica key; never touches a real installation's key.
    func testStage12IsolatedClientConflictWhenExplicitlyEnabled() async throws {
        do {
            let database = try await stage12IsolatedDevelopmentDatabase()
            let mapper = CloudKitRecordMapper()
            let replica = ReplicaID()
            let first = mapper.clientRecord(replicaID: replica, platform: .iPhone)
            try await requireNewStage12FixtureIDs([first.recordID], database: database)
            _ = try await saveStage12Fixture(first, database: database)

            let stale = try await database.record(for: first.recordID)
            let concurrent = try await database.record(for: first.recordID)
            _ = try await saveStage12Fixture(
                mapper.clientRecord(replicaID: replica, platform: .mac, reusing: concurrent),
                database: database
            )
            var actualConflict: CKError?
            do {
                _ = try await saveStage12Fixture(
                    mapper.clientRecord(replicaID: replica, platform: .iPhone, reusing: stale),
                    database: database
                )
                XCTFail("The stale fixture save must produce a real server conflict")
            } catch let error as CKError {
                guard error.code == .serverRecordChanged else { throw error }
                actualConflict = error
            }
            let conflict = try XCTUnwrap(actualConflict)
            guard let server = conflict.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                throw Stage12IsolatedFixtureError.missingServerConflictRecord
            }
            let observedAt = try XCTUnwrap(server.modificationDate)
            let registration = try mapper.clientRegistration(from: server, observedAt: observedAt)
            XCTAssertEqual(registration.replicaID, replica)
            XCTAssertEqual(registration.platform, .mac)
            XCTAssertEqual(registration.lastSeenAt, observedAt)
            let retry = mapper.clientRecord(replicaID: replica, platform: .iPhone, reusing: server)
            XCTAssertEqual(retry.recordID, first.recordID)
            XCTAssertEqual(Set(retry.allKeys()), Set(["schemaVersion", "replicaID", "platform"]))
            _ = try await saveStage12Fixture(retry, database: database)
            let fetched = try await database.record(for: first.recordID)
            let final = try mapper.clientRegistration(
                from: fetched, observedAt: try XCTUnwrap(fetched.modificationDate)
            )
            XCTAssertEqual(final.replicaID, replica)
            XCTAssertEqual(final.platform, .iPhone)
            XCTAssertEqual(final.schemaVersion, 1)
            XCTAssertNil(fetched["title"])
            XCTAssertNil(fetched["text"])
            print("TildoneIsolatedQualification case=client-conflict status=passed count=1")
            // Retain the fixture. No permanent deletion or invented cleanup field.
        } catch let skipped as XCTSkip {
            throw skipped
        } catch let error as CKError {
            throw Stage12IsolatedFixtureError.unexpectedCloudFailure(error.code.rawValue)
        }
    }

    private func stage12FixtureNote(
        id: NoteID = NoteID(), title: String, schema: Int,
        color: TildoneDomain.NoteColor = .yellow, colorVersion: VersionStamp? = nil
    ) -> TildoneDomain.Note {
        let stamp = VersionStamp(logicalCounter: 7, replicaID: ReplicaID())
        let date = Date(timeIntervalSince1970: 1_791_547_200)
        return TildoneDomain.Note(
            id: id, createdAt: date, title: title, titleVersion: stamp,
            color: color, colorVersion: colorVersion,
            lifecycleVersion: stamp, lastMeaningfulEditAt: date,
            lastMeaningfulEditVersion: stamp, schemaVersion: schema
        )
    }

    private func stage12FixtureTask(for note: TildoneDomain.Note) throws -> TildoneDomain.Task {
        TildoneDomain.Task(
            id: TaskID(), noteID: note.id, createdAt: note.createdAt,
            text: "Keep this synthetic compatibility check pending",
            textVersion: note.titleVersion, completionVersion: note.titleVersion,
            orderToken: try OrderToken(rawValue: "m"), orderVersion: note.titleVersion,
            lifecycleVersion: note.titleVersion, schemaVersion: 1
        )
    }

    private func stage12FixtureRepositoryDescriptor(root: URL) -> PersistenceStoreDescriptor {
        .persistent(baseDirectory: root, workspace: .account(UUID()))
    }

    /// Exact new IDs only. Saving is complete before the durable mutation is acknowledged.
    private func stage12UploadFixtureNote(
        id: NoteID, pipeline: SyncPipeline, mapper: CloudKitRecordMapper, database: CKDatabase
    ) async throws {
        guard let outbound = try await pipeline.prepareOutboundMutation(
            recordName: id.recordName, at: Date()
        ) else { return }
        let recordID = CKRecord.ID(recordName: id.recordName, zoneID: TildoneCloudSchema.zoneID)
        let server = try await database.record(for: recordID)
        _ = try await saveStage12Fixture(mapper.record(from: outbound.record, reusing: server), database: database)
        try await pipeline.acknowledge([outbound.mutationID])
    }

    /// Real CloudKit V1/V2 payloads, then persistent isolated replicas and a reopen.
    /// This is SDK/pipeline evidence, not a claim about an original historical app binary.
    func testStage12IsolatedMixedVersionsWhenExplicitlyEnabled() async throws {
        do {
            let database = try await stage12IsolatedDevelopmentDatabase()
            let mapper = CloudKitRecordMapper()
            let v1 = stage12FixtureNote(title: "Stage12 Mixed V1 20261009", schema: 1)
            let v2 = stage12FixtureNote(title: "Stage12 Mixed V2 20261009", schema: 2, color: .pink)
            let t1 = try stage12FixtureTask(for: v1)
            let t2 = try stage12FixtureTask(for: v2)
            let records = [SyncRecord.note(v1), .note(v2), .task(t1), .task(t2)].map { mapper.record(from: $0) }
            XCTAssertNil(records[0]["color"])
            XCTAssertNil(records[0]["kind"])
            XCTAssertNil(records[1]["kind"])
            XCTAssertNil(records[2]["indentLevel"])
            XCTAssertNil(records[2]["richTextJSON"])
            try await requireNewStage12FixtureIDs(records.map(\.recordID), database: database)
            for record in records { _ = try await saveStage12Fixture(record, database: database) }
            let fetched = try await database.records(for: records.map(\.recordID))
            let decoded = try records.map { try mapper.syncRecord(from: XCTUnwrap(fetched[$0.recordID]).get()) }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("stage12-mixed-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            for index in 0..<2 {
                let descriptor = stage12FixtureRepositoryDescriptor(root: root.appendingPathComponent("replica-\(index)"))
                func mergeAndClose() async throws {
                    let repository = try TildoneRepository(descriptor: descriptor)
                    let pipeline = SyncPipeline(repository: repository)
                    // Deliberately deliver children before parents in this batch.
                    _ = try await pipeline.apply(Array(decoded.reversed()), at: Date())
                    let quarantine = try await repository.quarantinedRecords()
                    XCTAssertEqual(quarantine.count, 0)
                    // Valid old tasks create durable schema-upgrade work; drain it
                    // only after the real service acknowledges the exact save.
                    let names = try await pipeline.pendingRecordNames()
                    XCTAssertEqual(Set(names), Set([t1.id.recordName, t2.id.recordName]))
                    for name in names {
                        guard name == t1.id.recordName || name == t2.id.recordName else {
                            throw Stage12IsolatedFixtureError.unexpectedExistingRecord
                        }
                        let prepared = try await pipeline.prepareOutboundMutation(recordName: name, at: Date())
                        let outbound = try XCTUnwrap(prepared)
                        let recordID = CKRecord.ID(recordName: name, zoneID: TildoneCloudSchema.zoneID)
                        let server = try await database.record(for: recordID)
                        _ = try await saveStage12Fixture(mapper.record(from: outbound.record, reusing: server), database: database)
                        try await pipeline.acknowledge([outbound.mutationID])
                    }
                    let pending = try await pipeline.pendingCount()
                    XCTAssertEqual(pending, 0)
                }
                try await mergeAndClose()
                let reopened = try TildoneRepository(descriptor: descriptor)
                let first = try await reopened.note(id: v1.id)
                let second = try await reopened.note(id: v2.id)
                let firstTask = try await reopened.task(id: t1.id)
                let secondTask = try await reopened.task(id: t2.id)
                XCTAssertEqual(first.color, .yellow)
                XCTAssertEqual(second.color, .pink)
                XCTAssertEqual(firstTask.richText, t1.richText)
                XCTAssertEqual(secondTask.richText, t2.richText)
                XCTAssertEqual(firstTask.indentLevel, 0)
                XCTAssertEqual(secondTask.indentLevel, 0)
                let quarantine = try await reopened.quarantinedRecords()
                XCTAssertEqual(quarantine.count, 0)
                let pending = try await reopened.pendingMutations()
                XCTAssertEqual(pending.count, 0)
            }
            print("TildoneIsolatedQualification case=mixed-versions status=passed count=4")
        } catch let skipped as XCTSkip { throw skipped }
        catch let error as CKError {
            throw Stage12IsolatedFixtureError.unexpectedCloudFailure(error.code.rawValue)
        }
    }

    /// Both upload/upgrade orders against the real service with isolated durable replicas.
    func testStage12IsolatedColorUpgradeOrdersWhenExplicitlyEnabled() async throws {
        do {
            let database = try await stage12IsolatedDevelopmentDatabase()
            let mapper = CloudKitRecordMapper()
            for macFirst in [true, false] {
                let base = stage12FixtureNote(
                    title: macFirst ? "Stage12 Mac First 20261009" : "Stage12 Phone First 20261009", schema: 1
                )
                let task = try stage12FixtureTask(for: base)
                let records = [SyncRecord.note(base), .task(task)].map { mapper.record(from: $0) }
                try await requireNewStage12FixtureIDs(records.map(\.recordID), database: database)
                for record in records { _ = try await saveStage12Fixture(record, database: database) }
                let initial = try mapper.syncRecord(from: await database.record(for: records[0].recordID))
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("stage12-order-\(UUID())")
                defer { try? FileManager.default.removeItem(at: root) }
                let macDescriptor = stage12FixtureRepositoryDescriptor(root: root.appendingPathComponent("mac"))
                let phoneDescriptor = stage12FixtureRepositoryDescriptor(root: root.appendingPathComponent("phone"))
                func migrateAndClose() async throws {
                    let mac = try TildoneRepository(descriptor: macDescriptor)
                    let phone = try TildoneRepository(descriptor: phoneDescriptor)
                    let macPipeline = SyncPipeline(repository: mac)
                    let phonePipeline = SyncPipeline(repository: phone)
                    _ = try await macPipeline.apply([initial], at: Date())
                    _ = try await phonePipeline.apply([initial], at: Date())
                    if macFirst {
                        try await mac.migrateMissingNoteColors(colorsByNoteID: [base.id: .orange], authority: .legacyMac)
                        try await stage12UploadFixtureNote(id: base.id, pipeline: macPipeline, mapper: mapper, database: database)
                        let delivery = try mapper.syncRecord(from: await database.record(for: records[0].recordID))
                        _ = try await phonePipeline.apply([delivery], at: Date())
                        try await phone.migrateMissingNoteColors(colorsByNoteID: [:], authority: .platformDefault)
                        try await stage12UploadFixtureNote(id: base.id, pipeline: phonePipeline, mapper: mapper, database: database)
                    } else {
                        try await phone.migrateMissingNoteColors(colorsByNoteID: [:], authority: .platformDefault)
                        try await stage12UploadFixtureNote(id: base.id, pipeline: phonePipeline, mapper: mapper, database: database)
                        let delivery = try mapper.syncRecord(from: await database.record(for: records[0].recordID))
                        _ = try await macPipeline.apply([delivery], at: Date())
                        try await mac.migrateMissingNoteColors(colorsByNoteID: [base.id: .orange], authority: .legacyMac)
                        try await stage12UploadFixtureNote(id: base.id, pipeline: macPipeline, mapper: mapper, database: database)
                    }
                    let delivery = try mapper.syncRecord(from: await database.record(for: records[0].recordID))
                    for (repository, pipeline) in [(mac, macPipeline), (phone, phonePipeline)] {
                        _ = try await pipeline.apply([delivery], at: Date())
                        let note = try await repository.note(id: base.id)
                        XCTAssertEqual(note.color, .orange)
                        XCTAssertEqual(NoteColorMigrationAuthority.authority(for: note.colorVersion.replicaID), .legacyMac)
                        let pending = try await pipeline.pendingCount()
                        XCTAssertEqual(pending, 0)
                        let quarantine = try await repository.quarantinedRecords()
                        XCTAssertEqual(quarantine.count, 0)
                    }
                }
                try await migrateAndClose()
                for descriptor in [macDescriptor, phoneDescriptor] {
                    let reopened = try TildoneRepository(descriptor: descriptor)
                    let note = try await reopened.note(id: base.id)
                    XCTAssertEqual(note.color, .orange)
                    let pending = try await reopened.pendingMutations()
                    XCTAssertEqual(pending.count, 0)
                }
            }
            print("TildoneIsolatedQualification case=color-upgrade-orders status=passed count=2")
        } catch let skipped as XCTSkip { throw skipped }
        catch let error as CKError {
            throw Stage12IsolatedFixtureError.unexpectedCloudFailure(error.code.rawValue)
        }
    }

    /// The winner has an ordinary explicit V2 stamp lower than the migration counter.
    func testStage12IsolatedV2ColorConflictWhenExplicitlyEnabled() async throws {
        do {
            let database = try await stage12IsolatedDevelopmentDatabase()
            let mapper = CloudKitRecordMapper()
            let base = stage12FixtureNote(title: "Stage12 V2 Color Conflict 20261009", schema: 1)
            let task = try stage12FixtureTask(for: base)
            let records = [SyncRecord.note(base), .task(task)].map { mapper.record(from: $0) }
            try await requireNewStage12FixtureIDs(records.map(\.recordID), database: database)
            for record in records { _ = try await saveStage12Fixture(record, database: database) }
            let stale = try await database.record(for: records[0].recordID)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("stage12-v2-conflict-\(UUID())")
            defer { try? FileManager.default.removeItem(at: root) }
            let descriptor = stage12FixtureRepositoryDescriptor(root: root)
            let winnerStamp = VersionStamp(logicalCounter: 1, replicaID: ReplicaID())
            let winner = TildoneDomain.Note(
                id: base.id, createdAt: base.createdAt, title: base.title, titleVersion: base.titleVersion,
                color: .purple, colorVersion: winnerStamp, lifecycleVersion: base.lifecycleVersion,
                lastMeaningfulEditAt: base.lastMeaningfulEditAt,
                lastMeaningfulEditVersion: base.lastMeaningfulEditVersion, schemaVersion: 2
            )
            func conflictAndClose() async throws {
                let repository = try TildoneRepository(descriptor: descriptor)
                let pipeline = SyncPipeline(repository: repository)
                _ = try await pipeline.apply([mapper.syncRecord(from: stale)], at: Date())
                try await repository.migrateMissingNoteColors(colorsByNoteID: [base.id: .green], authority: .legacyMac)
                let prepared = try await pipeline.prepareOutboundMutation(recordName: base.id.recordName, at: Date())
                let outbound = try XCTUnwrap(prepared)
                let concurrent = try await database.record(for: records[0].recordID)
                _ = try await saveStage12Fixture(mapper.record(from: .note(winner), reusing: concurrent), database: database)
                var serverConflict: CKRecord?
                do {
                    _ = try await saveStage12Fixture(mapper.record(from: outbound.record, reusing: stale), database: database)
                    XCTFail("The stale color migration must produce a real server conflict")
                } catch let error as CKError {
                    guard error.code == .serverRecordChanged else { throw error }
                    serverConflict = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord
                }
                guard let server = serverConflict else { throw Stage12IsolatedFixtureError.missingServerConflictRecord }
                _ = try await pipeline.apply([mapper.syncRecord(from: server)], at: Date())
                let preparedRetry = try await pipeline.prepareOutboundMutation(recordName: base.id.recordName, at: Date())
                let retry = try XCTUnwrap(preparedRetry)
                guard case let .note(retryNote) = retry.record else { return XCTFail("Expected a note retry") }
                XCTAssertEqual(retryNote.color, .purple)
                XCTAssertEqual(retryNote.colorVersion, winnerStamp)
                let saved = try await saveStage12Fixture(mapper.record(from: retry.record, reusing: server), database: database)
                try await pipeline.acknowledge([retry.mutationID])
                _ = try await pipeline.apply([mapper.syncRecord(from: saved)], at: Date())
                let pending = try await pipeline.pendingCount()
                XCTAssertEqual(pending, 0)
            }
            try await conflictAndClose()
            let reopened = try TildoneRepository(descriptor: descriptor)
            let note = try await reopened.note(id: base.id)
            XCTAssertEqual(note.color, .purple)
            XCTAssertEqual(note.colorVersion, winnerStamp)
            let pending = try await reopened.pendingMutations()
            XCTAssertEqual(pending.count, 0)
            let final = try mapper.syncRecord(from: await database.record(for: records[0].recordID))
            guard case let .note(serverNote) = final else { return XCTFail("Expected a server note") }
            XCTAssertEqual(serverNote.color, .purple)
            XCTAssertEqual(serverNote.colorVersion, winnerStamp)
            print("TildoneIsolatedQualification case=v2-color-conflict status=passed count=1")
        } catch let skipped as XCTSkip { throw skipped }
        catch let error as CKError {
            throw Stage12IsolatedFixtureError.unexpectedCloudFailure(error.code.rawValue)
        }
    }

}
