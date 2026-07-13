//
//  LegacyMigrationTests.swift
//  TildoneTests
//
//  Created by OpenAI Codex on 7/13/26.
//
import Foundation
import SwiftData
import XCTest
import TildoneDomain
import TildonePersistence
@testable import Tildone

@MainActor
final class LegacyMigrationTests: XCTestCase {
    func testDiscoveryUsesReleasedConfigurationAndRequiresExplicitExistingSource() throws {
        let schema = Schema([Todo.self, TodoList.self])
        let exactReleasedConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        XCTAssertEqual(LegacyStoreFileSet.releasedShippingURL(), exactReleasedConfiguration.url)
        XCTAssertEqual(exactReleasedConfiguration.url.lastPathComponent, "default.store")

        let root = try temporaryDirectory()
        let missing = root.appendingPathComponent("missing.store")
        XCTAssertThrowsError(try LegacyStoreFileSet.inspect(sourceURL: missing)) {
            XCTAssertEqual($0 as? LegacyStoreDiscoveryError, .missingSource)
        }
        let source = root.appendingPathComponent("source.store")
        try Data("source".utf8).write(to: source)
        XCTAssertThrowsError(try LegacyStoreFileSet.inspect(sourceURL: source, destinationURL: source)) {
            XCTAssertEqual($0 as? LegacyStoreDiscoveryError, .sourceDestinationCollision)
        }
    }

    func testFileSetFingerprintsAndCopiesMainWALSHMAndJournalWithoutSourceMutation() throws {
        let root = try temporaryDirectory()
        let source = root.appendingPathComponent("default.store")
        let contents: [String: Data] = [
            "": Data("main".utf8),
            "-wal": Data("wal".utf8),
            "-shm": Data("shm".utf8),
            "-journal": Data("journal".utf8)
        ]
        for (suffix, data) in contents { try data.write(to: URL(fileURLWithPath: source.path + suffix)) }
        let before = try sourceBytes(source)
        let files = try LegacyStoreFileSet.inspect(sourceURL: source)
        XCTAssertEqual(files.fileURLs.count, 4)
        let snapshot = try files.makeReadOnlySnapshot()
        XCTAssertEqual(try sourceBytes(snapshot.mainStoreURL), before)
        XCTAssertEqual(try sourceBytes(source), before)

        var sha = TildoneSHA256()
        sha.update(Data("abc".utf8))
        XCTAssertEqual(
            sha.finalizeHex(),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testReaderPreservesNilDuplicateNoncontiguousOrderAndClassifiesEmptyAndSystemRows() throws {
        let fixture = try makeComprehensiveFixture()
        let source = try LegacyStoreFileSet.inspect(sourceURL: fixture)
        let snapshot = try source.makeReadOnlySnapshot()
        let reader = try LegacyStoreReader(isolatedSnapshot: snapshot)
        let counts = try reader.inspect(batchSize: 2)
        XCTAssertEqual(counts.eligibleNotes, 4)
        XCTAssertEqual(counts.eligibleTasks, 6)
        XCTAssertEqual(counts.excludedSystemNotes, 1)
        XCTAssertEqual(counts.excludedSystemTasks, 1)
        XCTAssertEqual(counts.excludedTransientTasks, 1)

        var all: [LegacyNoteSnapshot] = []
        try reader.forEachNoteBatch(batchSize: 2) { all.append(contentsOf: $0) }
        let ordered = try XCTUnwrap(all.first(where: { $0.tasks.count == 5 }))
        XCTAssertEqual(ordered.tasks.map(\.text), [
            "Same", "Same", "", "Café 🚀\n第二行", "Nil index"
        ])
        XCTAssertEqual(ordered.tasks.map(\.originalIndex), [2, 2, 3, 9, nil])
        XCTAssertEqual(ordered.tasks.map(\.normalizedLegacyIndex), [2, 2, 3, 9, 4])
        XCTAssertEqual(ordered.tasks.map(\.visibleOrder), [0, 1, 2, 3, 4])
        XCTAssertEqual(ordered.tasks[2].classification, .excludedTransientEmptyTask)
        XCTAssertEqual(all.filter { $0.title == "" }.count, 1)
        XCTAssertEqual(all.filter { $0.title == nil }.count, 2)
        XCTAssertEqual(all.filter { $0.classification == .excludedSystemNote }.count, 1)
    }

    func testComprehensiveFixtureMigratesEndToEndReopensVerifiesAndLeavesSourceByteIdentical() async throws {
        let source = try makeComprehensiveFixture()
        let before = try sourceBytes(source)
        let destination = try temporaryDirectory().appendingPathComponent("shared.sqlite")
        let coordinator = LegacyMigrationCoordinator(
            sourceURL: source,
            destinationURL: destination,
            options: .init(batchSize: 2)
        )
        let first = try await coordinator.migrate()
        XCTAssertTrue(first.eligibleForCutover)
        XCTAssertFalse(first.activated)
        XCTAssertFalse(first.cloudSeedingEverBegun)
        XCTAssertEqual(first.destinationNoteCount, 4)
        XCTAssertEqual(first.destinationTaskCount, 6)
        XCTAssertEqual(first.mappingCount, 13)
        XCTAssertEqual(try sourceBytes(source), before)

        let second = try await coordinator.migrate()
        XCTAssertEqual(second, first)
        XCTAssertEqual(try sourceBytes(source), before)
        let repository = try TildoneRepository(descriptor: .temporaryMigration(storeURL: destination))
        let audit = try await repository.legacyMigrationAudit()
        XCTAssertEqual(audit.noteCount, 4)
        XCTAssertEqual(audit.taskCount, 6)
        XCTAssertEqual(audit.pendingMutationCount, 0)
        XCTAssertFalse(audit.duplicateMappedStableIDs)
    }

    func testFrozenReleased160FixtureMigratesAndEverySourceFileIsByteIdentical() async throws {
        let checkedIn = frozenLegacyFixtureURL()
        let sourceRoot = try temporaryDirectory()
        let source = sourceRoot.appendingPathComponent("default.store")
        try FileManager.default.copyItem(at: checkedIn, to: source)
        let before = try sourceBytes(source)
        let destination = try temporaryDirectory().appendingPathComponent("shared.sqlite")
        let result = try await LegacyMigrationCoordinator(
            sourceURL: source,
            destinationURL: destination,
            options: .init(batchSize: 1)
        ).migrate()
        XCTAssertTrue(result.eligibleForCutover)
        XCTAssertGreaterThan(result.destinationNoteCount, 0)
        XCTAssertGreaterThan(result.destinationTaskCount, 0)
        XCTAssertGreaterThan(result.mappingCount, result.destinationNoteCount)
        XCTAssertEqual(try sourceBytes(source), before)
        XCTAssertEqual(try Data(contentsOf: checkedIn).count, 77_824)
    }

    func testVerifiedStage6DestinationActivatesWithoutTouchingLegacySource() async throws {
        let source = try makeComprehensiveFixture()
        let before = try sourceBytes(source)
        let destination = try temporaryDirectory().appendingPathComponent("shared.sqlite")

        let migration = try await LegacyMigrationCoordinator(
            sourceURL: source,
            destinationURL: destination
        ).migrate()
        XCTAssertTrue(migration.eligibleForCutover)
        XCTAssertFalse(migration.activated)

        let repository = try TildoneRepository(descriptor: .temporaryMigration(storeURL: destination))
        let activation = try await repository.activateVerifiedLegacyMigration(at: Date())
        XCTAssertEqual(activation.phase, .eligibleForCutover)
        XCTAssertEqual(activation.activationState, .activated)
        XCTAssertFalse(activation.cloudSeedingEverBegun)
        XCTAssertEqual(try sourceBytes(source), before)
    }

    func testEmptyStoreAndLargeListUseBoundedBatchesWithoutSpecialCases() async throws {
        let emptySource = try makeEmptyFixture()
        let emptyDestination = try temporaryDirectory().appendingPathComponent("empty-shared.sqlite")
        let emptyResult = try await LegacyMigrationCoordinator(
            sourceURL: emptySource,
            destinationURL: emptyDestination,
            options: .init(batchSize: 7)
        ).migrate()
        XCTAssertEqual(emptyResult.destinationNoteCount, 0)
        XCTAssertEqual(emptyResult.destinationTaskCount, 0)
        XCTAssertEqual(emptyResult.mappingCount, 0)
        XCTAssertTrue(emptyResult.eligibleForCutover)

        let largeSource = try makeLargeFixture(taskCount: 500)
        let largeDestination = try temporaryDirectory().appendingPathComponent("large-shared.sqlite")
        let largeResult = try await LegacyMigrationCoordinator(
            sourceURL: largeSource,
            destinationURL: largeDestination,
            options: .init(batchSize: 17)
        ).migrate()
        XCTAssertEqual(largeResult.destinationNoteCount, 1)
        XCTAssertEqual(largeResult.destinationTaskCount, 500)
        XCTAssertEqual(largeResult.mappingCount, 501)
        XCTAssertTrue(largeResult.eligibleForCutover)
    }

    func testEveryDurableCheckpointRestartsWithoutDuplicateOrMappingRegression() async throws {
        let source = try makeComprehensiveFixture()
        let checkpoints: [LegacyMigrationCheckpoint] = [
            .afterSourceSnapshot, .afterMarker, .afterMapping, .afterNoteBatch(1),
            .afterTaskBatch(1), .beforeVerification, .duringVerification(1), .afterVerified
        ]
        for target in checkpoints {
            let destination = try temporaryDirectory().appendingPathComponent("shared.sqlite")
            let interrupter = CheckpointInterrupter(target: target)
            let first = LegacyMigrationCoordinator(
                sourceURL: source,
                destinationURL: destination,
                options: .init(batchSize: 2, checkpoint: { checkpoint in
                    try interrupter.call(checkpoint)
                })
            )
            do {
                _ = try await first.migrate()
                XCTFail("Expected interruption at \(target)")
            } catch {
                XCTAssertEqual(error as? LegacyMigrationCoordinatorError, .interrupted(target))
            }

            var mappingsBefore: [String: LegacyMappingSnapshot] = [:]
            if FileManager.default.fileExists(atPath: destination.path),
               let repository = try? TildoneRepository(
                    descriptor: .temporaryMigration(storeURL: destination)
               ), let state = try? await repository.legacyMigrationSnapshot(), state.mappingCount > 0 {
                let sourceFiles = try LegacyStoreFileSet.inspect(sourceURL: source)
                let snapshot = try sourceFiles.makeReadOnlySnapshot()
                let reader = try LegacyStoreReader(isolatedSnapshot: snapshot)
                var legacyKeys: [String] = []
                try reader.forEachNoteBatch(batchSize: 2) { notes in
                    for note in notes {
                        legacyKeys.append(note.legacyKey)
                        legacyKeys.append(contentsOf: note.tasks.map(\.legacyKey))
                    }
                }
                for key in legacyKeys {
                    if let mapping = try? await repository.legacyMapping(for: key) {
                        mappingsBefore[key] = mapping
                    }
                }
            }

            let result = try await LegacyMigrationCoordinator(
                sourceURL: source,
                destinationURL: destination,
                options: .init(batchSize: 2)
            ).migrate()
            XCTAssertTrue(result.eligibleForCutover)
            XCTAssertEqual(result.destinationNoteCount, 4)
            XCTAssertEqual(result.destinationTaskCount, 6)
            let reopened = try TildoneRepository(descriptor: .temporaryMigration(storeURL: destination))
            for (key, mapping) in mappingsBefore {
                let reopenedMapping = try await reopened.legacyMapping(for: key)
                XCTAssertEqual(reopenedMapping, mapping)
            }
            let audit = try await reopened.legacyMigrationAudit()
            XCTAssertFalse(audit.duplicateNoteIDs)
            XCTAssertFalse(audit.duplicateTaskIDs)
            XCTAssertFalse(audit.duplicateMappedStableIDs)
            XCTAssertEqual(audit.pendingMutationCount, 0)
        }
    }

    func testMissingCollisionDifferentCopyChangedSourceAndInvalidRelationshipFailTyped() async throws {
        let root = try temporaryDirectory()
        let missing = root.appendingPathComponent("missing.store")
        await assertMigrationError(.missingSource) {
            _ = try await LegacyMigrationCoordinator(
                sourceURL: missing,
                destinationURL: root.appendingPathComponent("destination.sqlite")
            ).migrate()
        }

        let source = try makeComprehensiveFixture()
        await assertMigrationError(.sourceDestinationCollision) {
            _ = try await LegacyMigrationCoordinator(sourceURL: source, destinationURL: source).migrate()
        }

        let destination = try temporaryDirectory().appendingPathComponent("shared.sqlite")
        let firstInterrupter = CheckpointInterrupter(target: .afterMarker)
        let partial = LegacyMigrationCoordinator(
            sourceURL: source,
            destinationURL: destination,
            options: .init(checkpoint: { checkpoint in
                try firstInterrupter.call(checkpoint)
            })
        )
        _ = try? await partial.migrate()
        let copiedSource = try temporaryDirectory().appendingPathComponent("default.store")
        try copySourceSet(from: source, to: copiedSource)
        await assertMigrationError(.differentSource) {
            _ = try await LegacyMigrationCoordinator(
                sourceURL: copiedSource,
                destinationURL: destination
            ).migrate()
        }

        let changedDestination = try temporaryDirectory().appendingPathComponent("shared.sqlite")
        let secondInterrupter = CheckpointInterrupter(target: .afterMarker)
        _ = try? await LegacyMigrationCoordinator(
            sourceURL: source,
            destinationURL: changedDestination,
            options: .init(checkpoint: { checkpoint in
                try secondInterrupter.call(checkpoint)
            })
        ).migrate()
        let handle = try FileHandle(forWritingTo: source)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([0]))
        try handle.close()
        await assertMigrationError(.sourceChanged) {
            _ = try await LegacyMigrationCoordinator(
                sourceURL: source,
                destinationURL: changedDestination
            ).migrate()
        }

        let orphan = try makeOrphanFixture()
        await assertMigrationError(.invalidRelationship) {
            _ = try await LegacyMigrationCoordinator(
                sourceURL: orphan,
                destinationURL: root.appendingPathComponent("orphan-shared.sqlite")
            ).migrate()
        }


        let notDirectory = root.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: notDirectory)
        let validForDestinationFailure = try makeEmptyFixture()
        await assertMigrationError(.destinationOpen) {
            _ = try await LegacyMigrationCoordinator(
                sourceURL: validForDestinationFailure,
                destinationURL: notDirectory.appendingPathComponent("shared.sqlite")
            ).migrate()
        }
    }

    func testEveryImportantDestinationCorruptionBlocksVerificationAndEligibility() async throws {
        let source = try makeComprehensiveFixture()
        let fields: [LegacyMigrationCorruptionField] = [
            .noteTitle, .taskText, .taskOwnership, .taskCompletion, .taskOrderToken,
            .taskOrderVersion, .mappingStableID, .taskCount, .taskVersion, .systemClassification
        ]
        for field in fields {
            let destination = try temporaryDirectory().appendingPathComponent("shared.sqlite")
            _ = try await LegacyMigrationCoordinator(
                sourceURL: source,
                destinationURL: destination
            ).migrate()
            do {
                let repository = try TildoneRepository(
                    descriptor: .temporaryMigration(storeURL: destination)
                )
                try await repository.corruptLegacyMigrationDestinationForTesting(field)
            }
            await assertMigrationError(.verificationMismatch) {
                _ = try await LegacyMigrationCoordinator(
                    sourceURL: source,
                    destinationURL: destination
                ).migrate()
            }
            let failed = try TildoneRepository(descriptor: .temporaryMigration(storeURL: destination))
            let state = try await failed.legacyMigrationSnapshot()
            XCTAssertEqual(state.phase, .failed)
            XCTAssertEqual(state.failureCategory, .verificationMismatch)
            XCTAssertFalse(state.cloudSeedingEverBegun)
            XCTAssertNotEqual(state.activationState, .activated)
        }
    }

    func testDeveloperToolRequiresExplicitPathsAndNeverDefaultsToProduction() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TILDONE_RUN_STAGE6_TOOL"] == "1" else {
            throw XCTSkip("Developer tool is opt-in; use Scripts/run-stage6-migration.sh")
        }
        let configurationPath = try XCTUnwrap(environment["TILDONE_STAGE6_TOOL_CONFIGURATION"])
        let configurationData = try Data(contentsOf: URL(fileURLWithPath: configurationPath))
        let configuration = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: configurationData, format: nil) as? [String: Any]
        )
        let sourceValue = try XCTUnwrap(configuration["source"] as? String)
        let destinationValue = try XCTUnwrap(configuration["destination"] as? String)
        let allowLiveSource = try XCTUnwrap(configuration["allowLiveSource"] as? Bool)
        let snapshotRootValue = try XCTUnwrap(configuration["snapshotRoot"] as? String)
        XCTAssertTrue(sourceValue.hasPrefix("/"))
        XCTAssertTrue(destinationValue.hasPrefix("/"))
        let source = URL(fileURLWithPath: sourceValue)
        if source.resolvingSymlinksInPath().standardizedFileURL ==
            LegacyStoreFileSet.releasedShippingURL().resolvingSymlinksInPath().standardizedFileURL {
            guard allowLiveSource else {
                XCTFail("Live shipping source requires --allow-live-source")
                return
            }
        }
        let result = try await LegacyMigrationCoordinator(
            sourceURL: source,
            destinationURL: URL(fileURLWithPath: destinationValue),
            options: .init(snapshotRootURL: URL(fileURLWithPath: snapshotRootValue))
        ).migrate()
        print(
            "stage6 phase=\(result.phase.rawValue) notes=\(result.destinationNoteCount) " +
            "tasks=\(result.destinationTaskCount) mappings=\(result.mappingCount) " +
            "replica=\(result.migrationReplicaID.stringValue)"
        )
        XCTAssertTrue(result.eligibleForCutover)
    }

    // MARK: Fixtures and helpers

    private func makeComprehensiveFixture() throws -> URL {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("default.store")
        try withLegacyStore(at: url) { context in
            let primary = makeList(created: date(100), title: nil)
            let first = makeTask("Same", created: date(101), index: 2, done: date(150), owner: primary)
            let second = makeTask("Same", created: date(101), index: 2, owner: primary)
            let empty = makeTask("", created: date(105), index: 3, owner: primary)
            let unicode = makeTask("Café 🚀\n第二行", created: date(104), index: 9, owner: primary)
            let nilIndex = makeTask("Nil index", created: date(103), index: nil, owner: primary)
            primary.items = [second, first, nilIndex, unicode, empty]

            let emptyTitle = makeList(created: date(200), title: "")
            let emptyTitleTask = makeTask(
                "Empty title task", created: date(201), index: 1, owner: emptyTitle
            )
            emptyTitle.items = [emptyTitleTask]
            let completed = makeList(created: date(300), title: "Fully completed")
            let completedTask = makeTask("Done", created: date(301), index: 1, done: date(350), owner: completed)
            completed.items = [completedTask]
            let emptyNote = makeList(created: date(400), title: nil)
            let system = makeList(created: date(500), title: "Updated")
            system.systemContent = "Sanitized release information"
            system.systemURL = URL(string: "https://example.invalid/release")
            let systemTask = makeTask("Check release notes", created: date(501), index: 0, owner: system)
            system.items = [systemTask]

            for list in [primary, emptyTitle, completed, emptyNote, system] { context.insert(list) }
            for task in [
                first, second, empty, unicode, nilIndex, emptyTitleTask, completedTask, systemTask
            ] {
                context.insert(task)
            }
        }
        return url
    }

    private func makeOrphanFixture() throws -> URL {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("default.store")
        try withLegacyStore(at: url) { context in
            let orphan = Todo("Orphan", at: 0)
            orphan.created = date(100)
            orphan.list = nil
            context.insert(orphan)
        }
        return url
    }

    private func makeEmptyFixture() throws -> URL {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("default.store")
        try withLegacyStore(at: url) { _ in }
        return url
    }

    private func makeLargeFixture(taskCount: Int) throws -> URL {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("default.store")
        try withLegacyStore(at: url) { context in
            let list = makeList(created: date(1_000), title: "Large sanitized list")
            var tasks: [Todo] = []
            tasks.reserveCapacity(taskCount)
            for index in 0..<taskCount {
                let task = makeTask(
                    "Task \(index)",
                    created: date(1_001 + Double(index)),
                    index: index % 19 == 0 ? nil : index * 2,
                    done: index.isMultiple(of: 3) ? date(10_000 + Double(index)) : nil,
                    owner: list
                )
                tasks.append(task)
                context.insert(task)
            }
            list.items = tasks
            context.insert(list)
        }
        return url
    }

    private func withLegacyStore(at url: URL, body: (ModelContext) throws -> Void) throws {
        let schema = Schema([Todo.self, TodoList.self])
        let configuration = ModelConfiguration(
            "SanitizedLegacyFixture",
            schema: schema,
            url: url,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        try body(context)
        try context.save()
    }

    private func makeList(created: Date, title: String?) -> TodoList {
        let list = TodoList()
        list.created = created
        list.topic = title
        return list
    }

    private func makeTask(
        _ text: String,
        created: Date,
        index: Int?,
        done: Date? = nil,
        owner: TodoList
    ) -> Todo {
        let task = Todo(text, at: index ?? 0)
        task.what = text
        task.created = created
        task.index = index
        task.done = done
        task.list = owner
        return task
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    private func sourceBytes(_ mainURL: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for suffix in LegacyStoreFileSet.sidecarSuffixes {
            let url = URL(fileURLWithPath: mainURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) {
                result[suffix] = try Data(contentsOf: url)
            }
        }
        return result
    }

    private func copySourceSet(from source: URL, to destination: URL) throws {
        for suffix in LegacyStoreFileSet.sidecarSuffixes {
            let sourceFile = URL(fileURLWithPath: source.path + suffix)
            guard FileManager.default.fileExists(atPath: sourceFile.path) else { continue }
            try FileManager.default.copyItem(
                at: sourceFile,
                to: URL(fileURLWithPath: destination.path + suffix)
            )
        }
    }

    private func frozenLegacyFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Packages/TildoneCore/Tests/TildonePersistenceTests/Fixtures/TildoneLegacy160/default.store")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TildoneLegacyMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func assertMigrationError(
        _ expected: LegacyMigrationCoordinatorError,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? LegacyMigrationCoordinatorError, expected)
        }
    }

}

private final class CheckpointInterrupter: @unchecked Sendable {
    private let lock = NSLock()
    private let target: LegacyMigrationCheckpoint
    private var fired = false

    init(target: LegacyMigrationCheckpoint) {
        self.target = target
    }

    func call(_ checkpoint: LegacyMigrationCheckpoint) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !fired, checkpoint == target else { return }
        fired = true
        throw NSError(domain: "intentional-interruption", code: 1)
    }
}
