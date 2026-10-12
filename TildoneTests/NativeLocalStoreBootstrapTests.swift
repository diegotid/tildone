import Foundation
import AppKit
import SwiftUI
import XCTest
import TildoneDomain
import TildonePersistence
@testable import Tildone

@MainActor
final class NativeLocalStoreBootstrapTests: XCTestCase {
    private struct Snapshot: Equatable {
        let notes: [TildoneDomain.Note]
        let tasks: [TildoneDomain.Task]
        let pending: [PendingMutationSnapshot]
        let workspace: WorkspaceSnapshot
    }

    private func locations() throws -> (
        base: URL, legacy: URL, descriptor: PersistenceStoreDescriptor, receipt: URL
    ) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TildoneNativeBootstrapFixture-\(UUID().uuidString)", isDirectory: true
        )
        let descriptor = PersistenceStoreDescriptor.persistent(baseDirectory: base, workspace: .localOnly)
        return (
            base, base.appendingPathComponent("explicitly-absent-default.store"),
            descriptor, try MacLocalStoreActivationReceipt.url(for: descriptor)
        )
    }

    private func snapshot(_ repository: TildoneRepository) async throws -> Snapshot {
        try await Snapshot(
            notes: repository.allSyncNotes(), tasks: repository.allSyncTasks(),
            pending: repository.pendingMutations(includeSuperseded: true),
            workspace: repository.workspaceSnapshot()
        )
    }

    private func writeFixture(
        base: URL, legacy: URL, descriptor: PersistenceStoreDescriptor, nativeAdmission: Bool
    ) async throws -> Snapshot {
        let repository: TildoneRepository
        if nativeAdmission {
            repository = try await MacSharedStoreBootstrapper.openRepository(
                baseDirectory: base, legacySourceURL: legacy
            )
        } else {
            repository = try TildoneRepository(descriptor: descriptor)
        }
        for index in 0..<2 {
            let note = try await repository.createNote(
                id: NoteID(), createdAt: Date(timeIntervalSince1970: Double(100 + index)),
                title: "Native fixture \(index) · café 你好"
            )
            for taskIndex in 0..<2 {
                let task = try await repository.addTask(
                    id: TaskID(), to: note.id,
                    createdAt: Date(timeIntervalSince1970: Double(200 + index * 2 + taskIndex)),
                    text: "Retained fixture \(index)-\(taskIndex) · 你好",
                    orderToken: OrderToken(rawValue: taskIndex == 0 ? "g" : "m")
                )
                if index == 0 && taskIndex == 1 {
                    _ = try await repository.setTaskCompletion(
                        id: task.id, completion: .completed(at: Date(timeIntervalSince1970: 300))
                    )
                }
            }
        }
        return try await snapshot(repository)
    }

    private func assertAdmissionRefused(base: URL, legacy: URL) async {
        do {
            _ = try await MacSharedStoreBootstrapper.openRepository(
                baseDirectory: base, legacySourceURL: legacy
            )
            XCTFail("Unverified fixture must remain unpresented")
        } catch MacSharedStoreBootstrapError.unverifiedSharedStore {
            // Expected preservation boundary.
        } catch {
            XCTFail("Unexpected admission failure category")
        }
    }

    func testNativeLocalNotesAndPendingWorkSurviveIndependentBootstrapReopen() async throws {
        let paths = try locations()
        let before = try await writeFixture(
            base: paths.base, legacy: paths.legacy, descriptor: paths.descriptor, nativeAdmission: true
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.receipt.path))
        let receiptBefore = try Data(contentsOf: paths.receipt)
        let reopened = try await MacSharedStoreBootstrapper.openRepository(
            baseDirectory: paths.base, legacySourceURL: paths.legacy
        )
        let after = try await snapshot(reopened)
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.notes.count, 2)
        XCTAssertEqual(after.tasks.count, 4)
        XCTAssertEqual(after.pending.count, 6)
        XCTAssertEqual(try Data(contentsOf: paths.receipt), receiptBefore)
        let permissions = try FileManager.default.attributesOfItem(atPath: paths.receipt.path)
        XCTAssertEqual((permissions[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testUnmarkedPopulatedSharedStoreRemainsBlockedAndPreserved() async throws {
        let paths = try locations()
        let before = try await writeFixture(
            base: paths.base, legacy: paths.legacy, descriptor: paths.descriptor, nativeAdmission: false
        )
        await assertAdmissionRefused(base: paths.base, legacy: paths.legacy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.receipt.path))
        let audit = try TildoneRepository(descriptor: paths.descriptor)
        let after = try await snapshot(audit)
        XCTAssertEqual(after, before)
    }

    func testUnmarkedTombstonesAreNotMisclassifiedAsEmptyNativeStore() async throws {
        let paths = try locations()
        _ = try await writeFixture(
            base: paths.base, legacy: paths.legacy, descriptor: paths.descriptor, nativeAdmission: false
        )
        let before: Snapshot
        do {
            let repository = try TildoneRepository(descriptor: paths.descriptor)
            for note in try await repository.visibleNotes() {
                try await repository.deleteNote(id: note.id)
            }
            let visible = try await repository.visibleNotes()
            XCTAssertTrue(visible.isEmpty)
            before = try await snapshot(repository)
        }
        await assertAdmissionRefused(base: paths.base, legacy: paths.legacy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.receipt.path))
        let audit = try TildoneRepository(descriptor: paths.descriptor)
        let after = try await snapshot(audit)
        XCTAssertEqual(after, before)
    }

    func testBootstrapFailureCanExpandFromZeroSizeInEverySupportedLocale() {
        for identifier in ["en", "es", "fr", "zh-Hans"] {
            let host = NSHostingView(rootView: AnyView(Color.clear.frame(width: 0, height: 0)))
            host.frame = .zero
            host.rootView = AnyView(MacBootstrapFailureView().environment(\.locale, Locale(identifier: identifier)))
            host.layoutSubtreeIfNeeded()
            let fitting = host.fittingSize
            XCTAssertEqual(fitting.width, 420, accuracy: 1)
            XCTAssertGreaterThan(fitting.height, 80)
            XCTAssertLessThan(fitting.height, 320)
        }
    }

    func testMismatchedReceiptCannotActivateAnotherWorkspace() async throws {
        let paths = try locations()
        let before = try await writeFixture(
            base: paths.base, legacy: paths.legacy, descriptor: paths.descriptor, nativeAdmission: true
        )
        let wrongReceipt = MacLocalStoreActivationReceipt(formatVersion: 1, replicaID: ReplicaID().stringValue)
        let wrongData = try JSONEncoder().encode(wrongReceipt)
        try wrongData.write(to: paths.receipt)
        await assertAdmissionRefused(base: paths.base, legacy: paths.legacy)
        XCTAssertEqual(try Data(contentsOf: paths.receipt), wrongData)
        let audit = try TildoneRepository(descriptor: paths.descriptor)
        let after = try await snapshot(audit)
        XCTAssertEqual(after, before)
    }

    func testCorruptReceiptIsNotReplacedEvenForEmptyWorkspace() async throws {
        let paths = try locations()
        do {
            _ = try await MacSharedStoreBootstrapper.openRepository(
                baseDirectory: paths.base, legacySourceURL: paths.legacy
            )
        }
        let corrupt = Data("corrupt synthetic receipt".utf8)
        try corrupt.write(to: paths.receipt)
        await assertAdmissionRefused(base: paths.base, legacy: paths.legacy)
        XCTAssertEqual(try Data(contentsOf: paths.receipt), corrupt)
    }

    func testInterruptedEmptyInitializationCanBeAdmittedBeforeFirstContentWrite() async throws {
        let paths = try locations()
        do { _ = try TildoneRepository(descriptor: paths.descriptor) }
        let repository = try await MacSharedStoreBootstrapper.openRepository(
            baseDirectory: paths.base, legacySourceURL: paths.legacy
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.receipt.path))
        let audit = try await repository.legacyMigrationAudit()
        XCTAssertEqual(audit.noteCount, 0)
        XCTAssertEqual(audit.taskCount, 0)
        XCTAssertEqual(audit.pendingMutationCount, 0)
    }

    func testNativeReceiptCannotBypassIncompleteLegacyMigration() async throws {
        let paths = try locations()
        do {
            let repository = try await MacSharedStoreBootstrapper.openRepository(
                baseDirectory: paths.base, legacySourceURL: paths.legacy
            )
            _ = try await repository.prepareLegacyMigration(
                formatVersion: 1,
                sourceFingerprint: LegacySourceFingerprint(
                    identityDigest: String(repeating: "a", count: 64),
                    contentDigest: String(repeating: "b", count: 64), fileCount: 1, totalByteCount: 100
                ), sourceCounts: .zero, at: Date(timeIntervalSince1970: 100)
            )
        }
        let receipt = try Data(contentsOf: paths.receipt)
        do {
            _ = try await MacSharedStoreBootstrapper.openRepository(
                baseDirectory: paths.base, legacySourceURL: paths.legacy
            )
            XCTFail("Native receipt must not bypass migration verification")
        } catch MacSharedStoreBootstrapError.legacySourceMissing {
            // The original legacy path still controls this destination.
        }
        XCTAssertEqual(try Data(contentsOf: paths.receipt), receipt)
        let audit = try TildoneRepository(descriptor: paths.descriptor)
        let migration = try await audit.legacyMigrationSnapshot()
        XCTAssertEqual(migration.phase, .notStarted)
    }
}
