import AppKit
import SwiftUI
import XCTest
import TildoneDomain
import TildonePersistence
import TildoneSync
@testable import Tildone

@MainActor
final class AccountStartupPresentationTests: XCTestCase {
    private final class Gate<Value> {
        var waiting = false
        private var continuation: CheckedContinuation<Value, Never>?
        func value() async -> Value {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                waiting = true
            }
        }
        func finish(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
    }
    private func defaults() -> UserDefaults {
        let name = "TildoneAccountStartupFixture.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }
    private func repository(_ workspace: WorkspaceIdentity = .localOnly, title: String? = nil) async throws -> TildoneRepository {
        let repository = try TildoneRepository(descriptor: .inMemory(workspace: workspace))
        if let title {
            let note = try await repository.createNote(id: NoteID(), createdAt: Date(timeIntervalSince1970: 100), title: title)
            _ = try await repository.addTask(id: TaskID(), to: note.id, createdAt: Date(timeIntervalSince1970: 101), text: "Retained fixture", orderToken: OrderToken(rawValue: "m"))
        }
        return repository
    }
    private func wait(_ condition: @escaping () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Swift.Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Startup fixture did not reach its expected state", file: file, line: line)
    }

    func testPendingAccountBecomesVisibleWithoutChoosingOrWritingWorkspace() async throws {
        let local = try await repository()
        let initial = try await local.workspaceSnapshot()
        let gate = Gate<CloudAccountSnapshot>()
        var opened = 0
        let model = MacSharedStoreBootstrapper.isolatedStartup(
            localRepository: local, resolveAccount: { await gate.value() },
            openAccount: { _ in opened += 1; return try await self.repository() }, defaults: defaults()
        )
        model.start(); model.start()
        await wait { gate.waiting && model.showsStartupAccountStatus }
        XCTAssertEqual(model.startupAccountState, .waiting)
        XCTAssertTrue(model.showsCoordinatorWindow)
        XCTAssertNil(model.store)
        XCTAssertFalse(model.hasResolvedAccountWorkspace)
        XCTAssertFalse(model.canControlTransport)
        XCTAssertEqual(opened, 0)
        let notes = try await local.allSyncNotes()
        let pending = try await local.pendingMutations(includeSuperseded: true)
        let workspace = try await local.workspaceSnapshot()
        XCTAssertTrue(notes.isEmpty); XCTAssertTrue(pending.isEmpty); XCTAssertEqual(workspace, initial)
        gate.finish(CloudAccountSnapshot(state: .couldNotDetermine, workspaceID: nil))
        await wait { model.startupAccountState == .unresolved }
    }

    func testUncertainAndIncompleteIdentityNeverFallBackToLocalNotes() async throws {
        for snapshot in [CloudAccountSnapshot(state: .temporarilyUnavailable, workspaceID: nil), CloudAccountSnapshot(state: .couldNotDetermine, workspaceID: nil), CloudAccountSnapshot(state: .available, workspaceID: nil)] {
            let local = try await repository(title: "Local fixture stays private")
            let notes = try await local.allSyncNotes(); let pending = try await local.pendingMutations(includeSuperseded: true)
            var opened = false
            let model = MacSharedStoreBootstrapper.isolatedStartup(
                localRepository: local, resolveAccount: { snapshot },
                openAccount: { _ in opened = true; return local }, defaults: defaults()
            )
            model.start()
            await wait { model.startupAccountState == .unresolved }
            XCTAssertNil(model.store); XCTAssertFalse(model.hasResolvedAccountWorkspace)
            XCTAssertFalse(opened); XCTAssertTrue(model.showsCoordinatorWindow)
            let afterNotes = try await local.allSyncNotes(); let afterPending = try await local.pendingMutations(includeSuperseded: true)
            XCTAssertEqual(afterNotes, notes); XCTAssertEqual(afterPending, pending)
        }
    }

    func testConfirmedNoAccountAndRestrictionPreserveLocalPresentation() async throws {
        for state in [CloudAccountState.noAccount, .restricted] {
            let local = try await repository(title: "Confirmed local fixture")
            var opened = false
            let model = MacSharedStoreBootstrapper.isolatedStartup(
                localRepository: local, resolveAccount: { CloudAccountSnapshot(state: state, workspaceID: nil) },
                openAccount: { _ in opened = true; return local }, defaults: defaults()
            )
            model.start(); await wait { model.store != nil }
            XCTAssertFalse(opened); XCTAssertFalse(model.isUsingAccountWorkspace)
            XCTAssertEqual(model.store?.notes.first?.title, "Confirmed local fixture")
            XCTAssertFalse(model.showsCoordinatorWindow)
            XCTAssertEqual(model.syncStatus.availability, state == .noAccount ? .noAccount : .restricted)
        }
    }

    func testLateOldAccountReplyCannotChooseWorkspaceAfterExplicitRetry() async throws {
        let local = try await repository(); let a = UUID(); let b = UUID()
        let accountB = try await repository(.account(b), title: "Current B")
        let old = Gate<CloudAccountSnapshot>(); let current = Gate<CloudAccountSnapshot>()
        var requests = 0; var opened: [UUID] = []
        let model = MacSharedStoreBootstrapper.isolatedStartup(
            localRepository: local, resolveAccount: {
                requests += 1
                return requests == 1 ? await old.value() : await current.value()
            }, openAccount: { id in opened.append(id); return accountB }, defaults: defaults()
        )
        model.start(); await wait { old.waiting }
        await model.handleAccountChangeNotification()
        XCTAssertEqual(model.startupAccountState, .unresolved)
        model.retryStartupAccount(); model.retryStartupAccount()
        await wait { current.waiting }
        current.finish(CloudAccountSnapshot(state: .available, workspaceID: b))
        await wait { model.store != nil }
        old.finish(CloudAccountSnapshot(state: .available, workspaceID: a))
        for _ in 0..<20 { await Swift.Task.yield() }
        XCTAssertEqual(requests, 2); XCTAssertEqual(opened, [b])
        XCTAssertEqual(model.store?.notes.first?.title, "Current B")
        XCTAssertTrue(model.isUsingAccountWorkspace); XCTAssertNil(model.error)
    }

    func testExplicitRetrySupersedesPendingReplyWithoutAccountNotification() async throws {
        let local = try await repository(); let a = UUID(); let b = UUID()
        let accountB = try await repository(.account(b), title: "Current B")
        let old = Gate<CloudAccountSnapshot>(); let current = Gate<CloudAccountSnapshot>()
        var requests = 0; var opened: [UUID] = []
        let model = MacSharedStoreBootstrapper.isolatedStartup(
            localRepository: local, resolveAccount: {
                requests += 1
                return requests == 1 ? await old.value() : await current.value()
            }, openAccount: { id in opened.append(id); return accountB }, defaults: defaults(), waitNanoseconds: 20_000_000
        )
        model.start(); await wait { model.startupAccountState == .waiting }
        model.retryStartupAccount(); model.retryStartupAccount()
        await wait { current.waiting }
        XCTAssertTrue(model.showsCoordinatorWindow, "Retry must keep the explanation visible")
        current.finish(CloudAccountSnapshot(state: .available, workspaceID: b))
        await wait { model.store != nil }
        old.finish(CloudAccountSnapshot(state: .available, workspaceID: a))
        for _ in 0..<20 { await Swift.Task.yield() }
        XCTAssertEqual(requests, 2); XCTAssertEqual(opened, [b])
        XCTAssertEqual(model.store?.notes.first?.title, "Current B")
        XCTAssertFalse(model.showsCoordinatorWindow); XCTAssertNil(model.error)
    }

    func testAccountChangeWhileOpeningOldRepositoryCannotPublishIt() async throws {
        let local = try await repository(); let a = UUID(); let b = UUID()
        let accountA = try await repository(.account(a), title: "Old A")
        let accountB = try await repository(.account(b), title: "Current B")
        let opening = Gate<TildoneRepository>(); var requests = 0
        let before = try await accountA.allSyncNotes(); let beforePending = try await accountA.pendingMutations(includeSuperseded: true)
        let model = MacSharedStoreBootstrapper.isolatedStartup(
            localRepository: local, resolveAccount: {
                requests += 1; return CloudAccountSnapshot(state: .available, workspaceID: requests == 1 ? a : b)
            }, openAccount: { id in id == a ? await opening.value() : accountB }, defaults: defaults()
        )
        model.start(); await wait { opening.waiting }
        await model.handleAccountChangeNotification(); model.retryStartupAccount()
        await wait { model.store != nil }
        opening.finish(accountA)
        for _ in 0..<20 { await Swift.Task.yield() }
        XCTAssertEqual(model.store?.notes.first?.title, "Current B")
        let after = try await accountA.allSyncNotes(); let afterPending = try await accountA.pendingMutations(includeSuperseded: true)
        XCTAssertEqual(after, before); XCTAssertEqual(afterPending, beforePending)
        XCTAssertNil(model.error)
    }

    func testInvalidatedAttemptCannotCleanUpOrPublishBeforePresentation() async throws {
        let local = try await repository(); let a = UUID(); let b = UUID()
        let accountA = try await repository(.account(a))
        let empty = try await accountA.createNote(id: NoteID(), createdAt: Date(timeIntervalSince1970: 100), title: nil)
        let accountB = try await repository(.account(b), title: "Current B")
        let barrier = Gate<Bool>(); var requests = 0; var preparation = 0
        let model = MacSharedStoreBootstrapper.isolatedStartup(
            localRepository: local, resolveAccount: {
                requests += 1; return CloudAccountSnapshot(state: .available, workspaceID: requests == 1 ? a : b)
            }, openAccount: { $0 == a ? accountA : accountB }, defaults: defaults(),
            beforePresentation: { preparation += 1; if preparation == 1 { _ = await barrier.value() } }
        )
        model.start(); await wait { barrier.waiting }
        await model.handleAccountChangeNotification(); model.retryStartupAccount()
        await wait { model.store != nil }
        barrier.finish(true)
        for _ in 0..<20 { await Swift.Task.yield() }
        XCTAssertEqual(model.store?.notes.first?.title, "Current B")
        let retained = try await accountA.note(id: empty.id, includingDeleted: true)
        XCTAssertEqual(retained.lifecycle, .active)
    }

    func testPresentationCleanupGuardPreservesEmptyFixtureWhenSuperseded() async throws {
        let repository = try await repository()
        let empty = try await repository.createNote(id: NoteID(), createdAt: Date(timeIntervalSince1970: 100), title: nil)
        let pending = try await repository.pendingMutations(includeSuperseded: true)
        let store = MacSharedStore(repository: repository)
        try await store.prepareForPresentation(whileValid: { false })
        let retained = try await repository.note(id: empty.id, includingDeleted: true)
        let afterPending = try await repository.pendingMutations(includeSuperseded: true)
        XCTAssertEqual(retained.lifecycle, .active); XCTAssertEqual(afterPending, pending)
    }

    func testLateOpeningFailureCannotReplaceCurrentAccountWithError() async throws {
        let local = try await repository(); let a = UUID(); let b = UUID()
        let current = try await repository(.account(b), title: "Current B")
        let failure = Gate<Bool>(); var requests = 0
        let model = MacSharedStoreBootstrapper.isolatedStartup(
            localRepository: local, resolveAccount: {
                requests += 1; return CloudAccountSnapshot(state: .available, workspaceID: requests == 1 ? a : b)
            }, openAccount: { id in
                if id == a { _ = await failure.value(); throw PersistenceError.openFailure }
                return current
            }, defaults: defaults()
        )
        model.start(); await wait { failure.waiting }
        await model.handleAccountChangeNotification(); model.retryStartupAccount()
        await wait { model.store != nil }
        failure.finish(true)
        for _ in 0..<20 { await Swift.Task.yield() }
        XCTAssertNil(model.error); XCTAssertEqual(model.store?.notes.first?.title, "Current B")
        XCTAssertFalse(model.showsCoordinatorWindow)
    }

    func testPresentedPausedAccountRetainsOfflineWorkDuringTransientUncertainty() async throws {
        let local = try await repository(); let id = UUID()
        let account = try await repository(.account(id), title: "Retained paused fixture")
        let pending = try await account.pendingMutations(includeSuperseded: true)
        let notes = try await account.allSyncNotes()
        let model = try await MacSharedStoreBootstrapper.isolatedPresentation(
            localRepository: local, accountRepository: account, workspaceID: id,
            defaults: defaults(), status: SyncStatus(availability: .available, activity: .paused, pendingMutationCount: pending.count),
            resolvedAccount: CloudAccountSnapshot(state: .temporarilyUnavailable, workspaceID: nil)
        )
        let store = model.store
        await model.handleAccountChangeNotification()
        XCTAssertTrue(model.store === store); XCTAssertTrue(model.isUsingAccountWorkspace)
        XCTAssertEqual(model.transportState, .paused); XCTAssertFalse(model.showsCoordinatorWindow)
        let afterPending = try await account.pendingMutations(includeSuperseded: true)
        let afterNotes = try await account.allSyncNotes()
        XCTAssertEqual(afterPending, pending); XCTAssertEqual(afterNotes, notes)
    }

    func testVisibleWaitingAndUnresolvedViewsHaveUsableRealWindowSize() async throws {
        let previous = NSApplication.shared.keyWindow
        defer { previous?.makeKey() }
        for language in ["en", "es", "fr", "zh-Hans"] {
            for state in [MacSharedStoreBootstrapper.StartupAccountState.checking, .waiting, .unresolved] {
                let root = MacAccountStartupView(state: state, onRetry: {}, onQuit: {}).environment(\.locale, Locale(identifier: language))
                let controller = NSHostingController(rootView: root)
                let window = NSWindow(contentViewController: controller)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: .aqua)
                let visibility = CoordinatorWindowVisibility.CoordinatorView(isVisible: true)
                controller.view.addSubview(visibility)
                window.orderFront(nil)
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
                XCTAssertTrue(window.isVisible); XCTAssertEqual(window.alphaValue, 1)
                XCTAssertFalse(window.ignoresMouseEvents)
                XCTAssertGreaterThanOrEqual(controller.view.fittingSize.width, 420)
                XCTAssertGreaterThan(controller.view.fittingSize.height, 100)
                XCTAssertLessThan(controller.view.fittingSize.height, 400)
                XCTAssertFalse(window.isRestorable)
                controller.view.layoutSubtreeIfNeeded()
                window.orderOut(nil)
            }
        }
    }
}
