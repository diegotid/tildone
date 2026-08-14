//
//  TildoneTests.swift
//  TildoneTests
//

import CloudKit
import SwiftUI
import XCTest
import TildoneDomain
import TildonePersistence
import TildoneSync
@testable import Tildone

final class TildoneTests: XCTestCase {
    @MainActor
    func testMacTransportIsDisabledUnderTests() {
        XCTAssertFalse(MacSharedStoreBootstrapper.transportEnabledByDefault)
    }

    @MainActor
    func testMenuBarAttentionImageKeepsTildoneIconAndAddsBadge() throws {
        let active = try XCTUnwrap(MenuBarController.menuBarImage(
            for: .active,
            accessibilityDescription: "Tildone"
        ))
        let attention = try XCTUnwrap(MenuBarController.menuBarImage(
            for: .attentionNeeded,
            accessibilityDescription: "iCloud sync needs attention"
        ))

        XCTAssertEqual(active.size, NSSize(width: 16, height: 16))
        XCTAssertEqual(attention.size, NSSize(width: 18, height: 18))
        XCTAssertNotEqual(active.tiffRepresentation, attention.tiffRepresentation)
        XCTAssertTrue(active.isTemplate)
        XCTAssertTrue(attention.isTemplate)
    }

    @MainActor
    func testMacNoteSyncIndicatorDistinguishesLocalChoiceAndAttention() {
        XCTAssertEqual(MacNoteTitlebarLayout.titleTrailingInset, 60)
        XCTAssertGreaterThan(
            MacNoteTitlebarLayout.titleTrailingInset,
            MacNoteTitlebarLayout.trailingMargin
                + MacNoteTitlebarLayout.colorPickerWidth
                + MacNoteTitlebarLayout.controlSpacing
                + MacNoteTitlebarLayout.syncIndicatorWidth
        )
        XCTAssertEqual(MacNoteSyncIndicatorState.resolve(
            isUsingNotesOnMacByChoice: false,
            syncNeedsAttention: false
        ), .hidden)
        XCTAssertEqual(MacNoteSyncIndicatorState.resolve(
            isUsingNotesOnMacByChoice: true,
            syncNeedsAttention: false
        ), .onlyOnThisMac)
        XCTAssertEqual(MacNoteSyncIndicatorState.resolve(
            isUsingNotesOnMacByChoice: true,
            syncNeedsAttention: true
        ), .attentionNeeded)

        let localControl = MacNoteSyncTitlebarControl(state: .onlyOnThisMac)
        let localStatus = String(localized: "Only on this Mac — not syncing with iPhone or iCloud.")
        XCTAssertEqual(localControl.toolTip, localStatus)
        XCTAssertEqual(localControl.accessibilityLabel(), localStatus)
        XCTAssertEqual(localControl.accessibilityRole(), .button)
        XCTAssertTrue(localControl.acceptsFirstMouse(for: nil))
        XCTAssertFalse(localControl.mouseDownCanMoveWindow)

        let opensOptions = expectation(
            forNotification: .openSyncResolutionOptions,
            object: nil
        )
        XCTAssertTrue(localControl.accessibilityPerformPress())
        wait(for: [opensOptions], timeout: 1)

        let attentionControl = MacNoteSyncTitlebarControl(state: .attentionNeeded)
        let attentionStatus = String(localized: "Not syncing with iCloud right now. Your notes are safe on this Mac.")
        XCTAssertEqual(MacNoteSyncIndicatorState.attentionNeeded.symbolName, "exclamationmark.icloud")
        XCTAssertNotNil(NSImage(
            systemSymbolName: MacNoteSyncIndicatorState.attentionNeeded.symbolName,
            accessibilityDescription: attentionStatus
        ))
        XCTAssertEqual(attentionControl.toolTip, attentionStatus)
        XCTAssertEqual(attentionControl.accessibilityLabel(), attentionStatus)
        XCTAssertEqual(attentionControl.accessibilityRole(), .button)

        let opensStatus = expectation(forNotification: .openSyncStatus, object: nil)
        XCTAssertTrue(attentionControl.accessibilityPerformPress())
        wait(for: [opensStatus], timeout: 1)
    }

    @MainActor
    func testMacNoteTitlebarControlsRemainClickableWhileWindowIsInactive() {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 14, height: 16))
        button.style()
        XCTAssertTrue(button.hitTest(NSPoint(x: 7, y: 8)) === button)

        let restore = MinimizedNoteRestoreTitlebarControl(onRestore: {})
        XCTAssertTrue(restore.acceptsFirstMouse(for: nil))
        XCTAssertFalse(restore.mouseDownCanMoveWindow)
    }

    func testMinimizedRestoreControlUsesTheFullTitlebarHeight() {
        let pickerFrame = NSRect(x: 220, y: 272, width: 26, height: 22)
        let frame = MacNoteTitlebarLayout.minimizedRestoreFrame(
            in: NSRect(x: 0, y: 0, width: 250, height: 300),
            alignedWith: pickerFrame
        )

        XCTAssertEqual(frame, NSRect(x: 229, y: 272, width: 19, height: 22))
    }

    func testMacRemoteRefreshPropagatesMigrationAndReloadFailures() async {
        enum FixtureError: Error, Equatable { case migration, reload }
        var reloadAttempted = false
        do {
            try await MacRemoteRefreshHandler.run(
                migrateColors: { throw FixtureError.migration },
                reloadSnapshots: { reloadAttempted = true }
            )
            XCTFail("Expected migration failure")
        } catch {
            XCTAssertEqual(error as? FixtureError, .migration)
            XCTAssertFalse(reloadAttempted)
        }

        do {
            try await MacRemoteRefreshHandler.run(
                migrateColors: {},
                reloadSnapshots: { throw FixtureError.reload }
            )
            XCTFail("Expected reload failure")
        } catch {
            XCTAssertEqual(error as? FixtureError, .reload)
        }
    }

    func testMacSyncPresentationDistinguishesActivePausedAndAttention() {
        let active = SyncStatus(availability: .available, activity: .idle)
        XCTAssertEqual(MacSyncPresentation.state(
            status: active,
            transportState: .active,
            enabledByDefault: true,
            hasUnadoptedLocalWorkspace: false
        ), .active)
        XCTAssertEqual(MacSyncPresentation.state(
            status: active,
            transportState: .paused,
            enabledByDefault: true,
            hasUnadoptedLocalWorkspace: false
        ), .paused)

        let zoneReset = SyncStatus(
            availability: .zoneResetRequired,
            activity: .attentionNeeded,
            issue: .zoneReset
        )
        XCTAssertEqual(MacSyncPresentation.state(
            status: zoneReset,
            transportState: .paused,
            enabledByDefault: true,
            hasUnadoptedLocalWorkspace: false
        ), .attentionNeeded)
        XCTAssertEqual(
            MacSyncPresentation.symbol(for: .attentionNeeded),
            "exclamationmark.triangle.fill"
        )
        XCTAssertEqual(
            MacSyncPresentation.menuBarBadgeSymbol(for: .attentionNeeded),
            "exclamationmark.circle.fill"
        )
        XCTAssertNil(MacSyncPresentation.menuBarBadgeSymbol(for: .active))
        XCTAssertNil(MacSyncPresentation.menuBarBadgeSymbol(for: .paused))
        XCTAssertNil(MacSyncPresentation.menuBarBadgeSymbol(for: .disabled))
        let resetDetail = MacSyncPresentation.detail(
            status: zoneReset,
            state: .attentionNeeded,
            hasUnadoptedLocalWorkspace: false,
            canAdoptLocalWorkspace: false,
            isUsingNotesOnMacByChoice: false
        )
        XCTAssertTrue(resetDetail.contains("will not rebuild or upload"))

        let conflictDetail = MacSyncPresentation.detail(
            status: active,
            state: .attentionNeeded,
            hasUnadoptedLocalWorkspace: true,
            canAdoptLocalWorkspace: false,
            isUsingNotesOnMacByChoice: false
        )
        let localChoiceDetail = MacSyncPresentation.detail(
            status: .disabled,
            state: .disabled,
            hasUnadoptedLocalWorkspace: false,
            canAdoptLocalWorkspace: false,
            isUsingNotesOnMacByChoice: true
        )
        XCTAssertTrue(localChoiceDetail.contains("notes saved on this Mac"))
        XCTAssertTrue(localChoiceDetail.contains("iCloud are unchanged"))
        for detail in [resetDetail, conflictDetail, localChoiceDetail] {
            for jargon in ["workspace", "zone", "reseed", "CloudKit", "transport"] {
                XCTAssertFalse(detail.localizedCaseInsensitiveContains(jargon), detail)
            }
        }
    }

    func testMacRecoveryUIRequiresAdoptionConfirmationAndHasNoAutomaticResetHatch() throws {
        XCTAssertFalse(MacWorkspaceSelectionPolicy.usesAccountWorkspace(
            localNeedsAdoption: true,
            explicitChoice: nil
        ))
        XCTAssertTrue(MacWorkspaceSelectionPolicy.usesAccountWorkspace(
            localNeedsAdoption: false,
            explicitChoice: nil
        ))
        XCTAssertFalse(MacWorkspaceSelectionPolicy.usesAccountWorkspace(
            localNeedsAdoption: false,
            explicitChoice: .thisMac
        ))
        XCTAssertTrue(MacWorkspaceSelectionPolicy.usesAccountWorkspace(
            localNeedsAdoption: true,
            explicitChoice: .iCloud
        ))
        XCTAssertTrue(MacWorkspaceSelectionPolicy.canAdoptLocalWorkspace(
            localNeedsAdoption: true,
            accountHasContent: false
        ))
        XCTAssertFalse(MacWorkspaceSelectionPolicy.canAdoptLocalWorkspace(
            localNeedsAdoption: true,
            accountHasContent: true
        ))

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSource = try String(
            contentsOf: sourceURL.appendingPathComponent("Tildone/TildoneApp.swift"),
            encoding: .utf8
        )
        let storeSource = try String(
            contentsOf: sourceURL.appendingPathComponent("Tildone/MacSharedStore.swift"),
            encoding: .utf8
        )
        let desktopSource = try String(
            contentsOf: sourceURL.appendingPathComponent("Tildone/Views/Desktop.swift"),
            encoding: .utf8
        )
        let noteSource = try String(
            contentsOf: sourceURL.appendingPathComponent("Tildone/Views/Note.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(appSource.contains(".alert(\"Copy notes to iCloud?\""))
        XCTAssertTrue(appSource.contains("Review Options…"))
        XCTAssertTrue(appSource.contains("Combine Notes — Recommended"))
        XCTAssertTrue(appSource.contains("MacNoteResolutionOptions("))
        XCTAssertTrue(appSource.contains("RoundedRectangle(cornerRadius: 8"))
        XCTAssertTrue(appSource.contains("resolveNotesAfterConfirmation(action)"))
        XCTAssertFalse(appSource.contains(".sheet(isPresented: $showsResolutionOptions)"))
        XCTAssertTrue(appSource.contains(".id(ObjectIdentifier(store))"))
        XCTAssertTrue(appSource.contains("noteSyncIndicatorState: noteSyncIndicatorState"))
        XCTAssertTrue(appSource.contains("syncNeedsAttention: displayState == .attentionNeeded"))
        XCTAssertTrue(appSource.contains("publisher(for: .openSyncResolutionOptions)"))
        XCTAssertTrue(appSource.contains("These notes won’t appear on your iPhone or in iCloud. You can combine them later."))
        XCTAssertTrue(desktopSource.contains("guard noteSyncIndicatorState != .hidden else { return }"))
        XCTAssertTrue(desktopSource.contains("picker.frame.minX - indicatorSize.width - MacNoteTitlebarLayout.controlSpacing"))
        XCTAssertTrue(desktopSource.contains(".onChange(of: noteSyncIndicatorState)"))
        XCTAssertTrue(desktopSource.contains("setNoteSyncIndicatorState(state)"))
        XCTAssertTrue(noteSource.contains(".padding(.trailing, MacNoteTitlebarLayout.titleTrailingInset)"))
        XCTAssertTrue(storeSource.contains("revalidateAccount(workspaceID:"))
        XCTAssertTrue(storeSource.contains("didJustChooseNotesOnMac = true"))
        XCTAssertTrue(storeSource.contains("func dismissNotesOnMacNotice()"))
        XCTAssertTrue(appSource.contains("setAccessibilityValue(title)"))
        XCTAssertTrue(appSource.contains("button.image = Self.menuBarImage(for: state"))
        XCTAssertFalse(storeSource.contains("TILDONE_ALLOW_LOCAL_WORKSPACE_ADOPTION"))
        XCTAssertFalse(storeSource.contains("TILDONE_RESET_DEVELOPMENT_ACCOUNT_WORKSPACE"))
        XCTAssertFalse(storeSource.contains("resetDevelopmentAccountWorkspace"))
    }

    func testMacNoteLocationChoicePersistsPerAccountAndIgnoresMalformedValues() throws {
        let suiteName = "MacNoteLocationChoiceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let firstAccount = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondAccount = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let store = MacNoteLocationChoiceStore(defaults: defaults)

        XCTAssertNil(store.choice(for: firstAccount))
        XCTAssertNil(store.choice(for: secondAccount))
        store.set(.thisMac, for: firstAccount)

        let relaunchedStore = MacNoteLocationChoiceStore(defaults: defaults)
        XCTAssertEqual(relaunchedStore.choice(for: firstAccount), .thisMac)
        XCTAssertNil(relaunchedStore.choice(for: secondAccount))

        defaults.set(
            "unexpected",
            forKey: "noteLocationChoice.\(secondAccount.uuidString.lowercased())"
        )
        XCTAssertNil(relaunchedStore.choice(for: secondAccount))
    }

    func testCombineNotesPreservesLocalSourceAndQueuesCombinedAccountContent() async throws {
        let local = try TildoneRepository(
            descriptor: .inMemory(workspace: .localOnly),
            replicaID: ReplicaID(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!)
        )
        let account = try TildoneRepository(
            descriptor: .inMemory(workspace: .account(UUID())),
            replicaID: ReplicaID(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
        )
        let localNoteID = NoteID(UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!)
        let accountNoteID = NoteID(UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!)
        let localTaskID = TaskID(UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!)
        let createdAt = Date(timeIntervalSinceReferenceDate: 1_000)

        _ = try await local.createNote(id: localNoteID, createdAt: createdAt, title: "Local")
        _ = try await local.addTask(
            id: localTaskID,
            to: localNoteID,
            createdAt: createdAt,
            text: "Local task",
            orderToken: try OrderToken(rawValue: "h")
        )
        _ = try await account.createNote(
            id: accountNoteID,
            createdAt: createdAt,
            title: "iCloud"
        )
        let localNotesBefore = try await local.allSyncNotes()
        let localTasksBefore = try await local.allSyncTasks()

        let fingerprint = try await MacNoteResolutionService.combine(
            localRepository: local,
            accountRepository: account,
            at: createdAt.addingTimeInterval(1)
        )

        let localNotesAfter = try await local.allSyncNotes()
        let localTasksAfter = try await local.allSyncTasks()
        let localFingerprintAfter = try await MacNoteResolutionService.fingerprint(repository: local)
        let accountNotes = try await account.allSyncNotes()
        let accountTasks = try await account.allSyncTasks()
        let accountPending = try await account.pendingMutations()

        XCTAssertEqual(localNotesAfter, localNotesBefore)
        XCTAssertEqual(localTasksAfter, localTasksBefore)
        XCTAssertEqual(fingerprint, localFingerprintAfter)
        XCTAssertEqual(
            Set(accountNotes.map(\.id)),
            [localNoteID, accountNoteID]
        )
        XCTAssertEqual(accountTasks.map(\.id), [localTaskID])
        XCTAssertEqual(
            Set(accountPending.map(\.targetStableID)),
            [localNoteID.stringValue, accountNoteID.stringValue, localTaskID.stringValue]
        )
    }

    func testTrackedAppSchemesUseDeterministicDebugLaunchAndReleaseArchiveConfigurations() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for name in ["Tildone", "Tildone iOS"] {
            let schemeURL = repositoryRoot
                .appendingPathComponent("Tildone.xcodeproj/xcshareddata/xcschemes")
                .appendingPathComponent("\(name).xcscheme")
            let source = try String(contentsOf: schemeURL, encoding: .utf8)
            XCTAssertTrue(source.contains("<LaunchAction\n      buildConfiguration = \"Debug\""), name)
            XCTAssertTrue(source.contains("<ArchiveAction\n      buildConfiguration = \"Release\""), name)
            XCTAssertFalse(source.contains("language ="), name)
        }
    }

    func testCheckboxDoesNotRetainParentOwnedCompletionAsLocalState() {
        let storedPropertyNames = Set(
            Mirror(reflecting: Checkbox(checked: false)).children.compactMap(\.label)
        )

        XCTAssertTrue(
            storedPropertyNames.contains("checked"),
            "Completion must remain an ordinary parent-owned view input."
        )
        XCTAssertFalse(
            storedPropertyNames.contains("_checked"),
            "Duplicating completion in @State prevents remote parent updates from redrawing the checkbox."
        )
    }

    @MainActor
    func testPrimarySceneUsesSingleUniqueCoordinatorWindow() {
        let scene = TildonePrimaryScene { EmptyView() }
        let bodyType = String(reflecting: type(of: scene.body))

        XCTAssertTrue(
            bodyType.contains("SwiftUI.Window<"),
            "The process-wide note-window coordinator must use SwiftUI.Window."
        )
        XCTAssertFalse(
            bodyType.contains("SwiftUI.WindowGroup<"),
            "WindowGroup permits multiple coordinator instances on macOS."
        )
    }

    func testMacSharedStoreRoutesCRUDThroughDomainRepository() async throws {
        let repository = try TildoneRepository(
            descriptor: .inMemory(),
            replicaID: ReplicaID(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!),
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let store = await MainActor.run { MacSharedStore(repository: repository) }

        let note = try await store.createNote(createdAt: Date(timeIntervalSince1970: 100))
        try await store.renameNote(note.id, to: "Title")
        try await store.setColor(.purple, for: note.id)
        let last = try await store.addTask(to: note.id, text: "Last")
        let first = try await store.addTask(to: note.id, text: "First", insertingAt: 0)
        try await store.setTaskCompletion(first.id, completed: true)
        try await store.editTask(last.id, text: "Changed")

        let loadedSnapshot = await MainActor.run { store.note(note.id) }
        let snapshot = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(snapshot.title, "Title")
        XCTAssertEqual(snapshot.color, .purple)
        XCTAssertEqual(snapshot.tasks.map(\.text), ["First", "Changed"])
        XCTAssertEqual(snapshot.pendingTasks.map(\.id), [last.id])

        try await store.deleteTask(first.id)
        try await store.deleteTask(last.id)
        try await store.renameNote(note.id, to: nil)
        let loadedEmpty = await MainActor.run { store.note(note.id) }
        let empty = try XCTUnwrap(loadedEmpty)
        XCTAssertTrue(empty.isDeletable)
        try await store.deleteNote(note.id)
        let remaining = try await repository.visibleNotes()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testLegacyMacColorLookupPrefersPerNoteValueAndPreservesGlobalFallback() throws {
        let suiteName = "TildoneColorMigrationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let coloredNote = NoteID()
        let fallbackNote = NoteID()
        defaults.set(NoteColor.orange.legacyRawValue, forKey: NoteColor.storageKey)
        defaults.set(
            NoteColor.pink.legacyRawValue,
            forKey: NoteColor.storageKey(for: coloredNote)
        )

        XCTAssertEqual(NoteColor.legacyLocalColor(for: coloredNote, defaults: defaults), .pink)
        XCTAssertNil(NoteColor.legacyLocalColor(for: fallbackNote, defaults: defaults))
        XCTAssertEqual(NoteColor.current(from: defaults), .orange)
    }

    func testMacSharedStoreRemovesRestoredEmptyNotesButKeepsCompletedNotesForFade() async throws {
        let repository = try TildoneRepository(descriptor: .inMemory())
        let store = await MainActor.run { MacSharedStore(repository: repository) }
        let empty = try await store.createNote(createdAt: Date(timeIntervalSince1970: 100))
        let completed = try await store.createNote(createdAt: Date(timeIntervalSince1970: 200))
        let task = try await store.addTask(to: completed.id, text: "Complete me")
        try await store.setTaskCompletion(task.id, completed: true)

        try await store.prepareForPresentation()

        let snapshots = await MainActor.run { store.notes }
        XCTAssertNil(snapshots.first(where: { $0.id == empty.id }))
        let restoredCompletion = try XCTUnwrap(snapshots.first(where: { $0.id == completed.id }))
        XCTAssertTrue(restoredCompletion.isComplete)
        XCTAssertNotNil(restoredCompletion.completedAt)
    }

    func testCompletionFadeLifecycleResumesUsingPersistedCompletionDate() {
        let completedAt = Date(timeIntervalSince1970: 100)
        var lifecycle = CompletionFadeLifecycle()

        lifecycle.synchronize(completedAt: completedAt)

        XCTAssertTrue(lifecycle.isFading)
        XCTAssertTrue(lifecycle.showsCompletionOverlay)
        XCTAssertEqual(
            lifecycle.progress(at: Date(timeIntervalSince1970: 105), duration: 20),
            5
        )
        XCTAssertNil(lifecycle.beginDeletionIfReady(
            at: Date(timeIntervalSince1970: 119.9),
            duration: 20
        ))
        XCTAssertEqual(lifecycle.beginDeletionIfReady(
            at: Date(timeIntervalSince1970: 120),
            duration: 20
        ), completedAt)
        XCTAssertFalse(lifecycle.isFading)
        XCTAssertTrue(lifecycle.showsCompletionOverlay)
    }

    func testCompletionFadeCancellationOnlyAppliesToCurrentCompletionCycle() {
        let firstCompletion = Date(timeIntervalSince1970: 100)
        let secondCompletion = Date(timeIntervalSince1970: 200)
        var lifecycle = CompletionFadeLifecycle()

        lifecycle.synchronize(completedAt: firstCompletion)
        lifecycle.cancel()
        lifecycle.synchronize(completedAt: firstCompletion)

        XCTAssertEqual(lifecycle.phase, .cancelled(completedAt: firstCompletion))
        XCTAssertFalse(lifecycle.showsCompletionOverlay)

        lifecycle.synchronize(completedAt: nil)
        XCTAssertEqual(lifecycle.phase, .idle)

        lifecycle.synchronize(completedAt: secondCompletion)
        XCTAssertEqual(lifecycle.phase, .fading(completedAt: secondCompletion))
        XCTAssertTrue(lifecycle.showsCompletionOverlay)
    }

    func testCompletionFadeRestoresCancelledAutoDeletionState() {
        let completedAt = Date(timeIntervalSince1970: 100)
        var lifecycle = CompletionFadeLifecycle()

        lifecycle.synchronize(completedAt: completedAt, autoDeletionCancelled: true)

        XCTAssertEqual(lifecycle.phase, .cancelled(completedAt: completedAt))
        XCTAssertFalse(lifecycle.showsCompletionOverlay)
        XCTAssertNil(lifecycle.beginDeletionIfReady(
            at: Date(timeIntervalSince1970: 200),
            duration: 20
        ))
    }

    func testCompletionFadeProgressClampsAcrossSleepAndClockSkew() {
        var lifecycle = CompletionFadeLifecycle()
        lifecycle.synchronize(completedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(
            lifecycle.progress(at: Date(timeIntervalSince1970: 90), duration: 20),
            0
        )
        XCTAssertEqual(
            lifecycle.progress(at: Date(timeIntervalSince1970: 1_000), duration: 20),
            20
        )
    }

    func testMacSharedStoreReordersBeginningMiddleAndEndWithoutChangingTaskContent() async throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TildoneMacReorder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: baseDirectory)
        }
        let descriptor = PersistenceStoreDescriptor.persistent(
            baseDirectory: baseDirectory,
            workspace: .localOnly
        )
        let replica = ReplicaID(UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!)
        let noteID: NoteID
        let taskIDs: [TaskID]
        var expectedContent: [TaskID: TildoneDomain.Task] = [:]

        do {
            let repository = try TildoneRepository(
                descriptor: descriptor,
                replicaID: replica,
                now: { Date(timeIntervalSince1970: 4_000) }
            )
            let store = await MainActor.run { MacSharedStore(repository: repository) }
            let note = try await store.createNote(createdAt: Date(timeIntervalSince1970: 100))
            noteID = note.id

            let first = try await store.addTask(
                to: note.id, text: "First", createdAt: Date(timeIntervalSince1970: 101)
            )
            let second = try await store.addTask(
                to: note.id, text: "Second", createdAt: Date(timeIntervalSince1970: 102)
            )
            let third = try await store.addTask(
                to: note.id, text: "Third", createdAt: Date(timeIntervalSince1970: 103)
            )
            let fourth = try await store.addTask(
                to: note.id, text: "Fourth", createdAt: Date(timeIntervalSince1970: 104)
            )
            try await store.setTaskCompletion(second.id, completed: true)
            taskIDs = [first.id, second.id, third.id, fourth.id]
            expectedContent = Dictionary(
                uniqueKeysWithValues: try await repository.orderedTasks(in: note.id).map { ($0.id, $0) }
            )
            try await repository.acknowledgeMutations(
                ids: Set(try await repository.pendingMutations().map(\.id))
            )

            let movedToBeginning = try await store.moveTask(fourth.id, in: note.id, to: 0)
            let beginningIDs = await MainActor.run { store.note(note.id)?.tasks.map(\.id) }
            XCTAssertTrue(movedToBeginning)
            XCTAssertEqual(beginningIDs, [fourth.id, first.id, second.id, third.id])

            let movedToMiddle = try await store.moveTask(fourth.id, in: note.id, to: 3)
            let middleIDs = await MainActor.run { store.note(note.id)?.tasks.map(\.id) }
            XCTAssertTrue(movedToMiddle)
            XCTAssertEqual(middleIDs, [first.id, second.id, fourth.id, third.id])

            let movedToEnd = try await store.moveTask(first.id, in: note.id, to: 4)
            let endIDs = await MainActor.run { store.note(note.id)?.tasks.map(\.id) }
            XCTAssertTrue(movedToEnd)
            XCTAssertEqual(endIDs, [second.id, fourth.id, third.id, first.id])

            let pendingBeforeNoOp = try await repository.pendingMutations()
            let noOpMoved = try await store.moveTask(fourth.id, in: note.id, to: 1)
            let pendingAfterNoOp = try await repository.pendingMutations()
            XCTAssertFalse(noOpMoved)
            XCTAssertEqual(pendingAfterNoOp, pendingBeforeNoOp)

            let finalTasks = try await repository.orderedTasks(in: note.id)
            XCTAssertEqual(finalTasks.map(\.id), [second.id, fourth.id, third.id, first.id])
            XCTAssertEqual(Set(finalTasks.map(\.id)), Set(taskIDs))
            XCTAssertEqual(finalTasks.count, taskIDs.count)
            for task in finalTasks {
                let original = try XCTUnwrap(expectedContent[task.id])
                XCTAssertEqual(task.noteID, original.noteID)
                XCTAssertEqual(task.createdAt, original.createdAt)
                XCTAssertEqual(task.text, original.text)
                XCTAssertEqual(task.textVersion, original.textVersion)
                XCTAssertEqual(task.completion, original.completion)
                XCTAssertEqual(task.completionVersion, original.completionVersion)
                XCTAssertEqual(task.lifecycle, original.lifecycle)
                XCTAssertEqual(task.lifecycleVersion, original.lifecycleVersion)
            }
            XCTAssertEqual(
                finalTasks.first(where: { $0.id == second.id })?.orderToken,
                expectedContent[second.id]?.orderToken
            )
            XCTAssertEqual(
                finalTasks.first(where: { $0.id == third.id })?.orderToken,
                expectedContent[third.id]?.orderToken
            )

            let pending = try await repository.pendingMutations()
            XCTAssertEqual(pending.count, 3)
            XCTAssertEqual(Set(pending.map(\.targetKind)), [.note, .task])
            XCTAssertEqual(
                Set(pending.map(\.targetStableID)),
                [note.id.stringValue, first.id.stringValue, fourth.id.stringValue]
            )
        }

        let reopened = try TildoneRepository(descriptor: descriptor, replicaID: ReplicaID())
        let persisted = try await reopened.orderedTasks(in: noteID)
        XCTAssertEqual(persisted.map(\.id), [taskIDs[1], taskIDs[3], taskIDs[2], taskIDs[0]])
        XCTAssertEqual(Set(persisted.map(\.id)), Set(taskIDs))
        XCTAssertEqual(persisted.count, taskIDs.count)
        for task in persisted {
            let original = try XCTUnwrap(expectedContent[task.id])
            XCTAssertEqual(task.noteID, original.noteID)
            XCTAssertEqual(task.createdAt, original.createdAt)
            XCTAssertEqual(task.text, original.text)
            XCTAssertEqual(task.completion, original.completion)
            XCTAssertEqual(task.lifecycle, original.lifecycle)
        }
        let durablePending = try await reopened.pendingMutations()
        XCTAssertEqual(
            Set(durablePending.map(\.targetStableID)),
            [noteID.stringValue, taskIDs[0].stringValue, taskIDs[3].stringValue]
        )
    }

    func testMacTaskDragPayloadRejectsCrossNoteAndMalformedDrops() throws {
        let noteID = NoteID()
        let taskID = TaskID()
        let payload = MacTaskDragPayload(noteID: noteID, taskID: taskID)

        XCTAssertTrue(payload.isValid(for: noteID, taskIDs: [taskID]))
        XCTAssertFalse(payload.isValid(for: NoteID(), taskIDs: [taskID]))
        XCTAssertFalse(payload.isValid(for: noteID, taskIDs: [TaskID()]))
        XCTAssertThrowsError(try JSONDecoder().decode(
            MacTaskDragPayload.self,
            from: Data(#"{"noteID":"invalid","taskID":"invalid"}"#.utf8)
        ))
    }

    func testMacTaskRowsExposeDedicatedDragHandlesAndDropTargets() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tildone/Views/Note.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("TaskReorderHandle("))
        XCTAssertTrue(source.contains(".draggable(payload)"))
        XCTAssertTrue(source.contains("CodableRepresentation(contentType: .json)"))
        XCTAssertTrue(source.contains("TaskReorderPreview("))
        XCTAssertTrue(source.contains("Checkbox(checked: isCompleted)"))
        XCTAssertTrue(source.contains(
            "Text(taskText.isEmpty ? String(localized: \"Untitled task\") : taskText)"
        ))
        XCTAssertTrue(source.contains(".padding(.top, dropPlacement == .before"))
        XCTAssertTrue(source.contains(".padding(.bottom, dropPlacement == .after"))
        XCTAssertTrue(source.contains("? TaskReorderFeedback.expandedHeight"))
        XCTAssertTrue(source.contains("TaskReorderInsertionLine()"))
        XCTAssertTrue(source.contains(".onChange(of: feedbackResetToken)"))
        XCTAssertTrue(source.contains(".padding(.trailing, 8)"))
        XCTAssertFalse(source.contains(".stroke(Color.accentColor"))
        XCTAssertTrue(source.contains(".dropDestination(for: MacTaskDragPayload.self)"))
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Reorder task\")"))
    }

    /// Opt-in smoke test hosted by the signed development Mac app so the test
    /// inherits the real CloudKit entitlement. The normal suite is fully local.
    func testDevelopmentCloudKitRoundTripWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["TILDONE_RUN_DEVELOPMENT_CLOUDKIT_TESTS"] == "1" else {
            throw XCTSkip("Development CloudKit integration is explicitly opt-in")
        }
        let container = CKContainer(identifier: TildoneCloudSchema.containerIdentifier)
        guard try await container.accountStatus() == .available else {
            throw XCTSkip("A development iCloud account is required")
        }

        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneID: TildoneCloudSchema.zoneID)
        let zoneResults = try await database.modifyRecordZones(saving: [zone], deleting: [])
        _ = try zoneResults.saveResults[TildoneCloudSchema.zoneID]?.get()

        let timestamp = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let stamp = VersionStamp(logicalCounter: 1, replicaID: ReplicaID())
        let note = Note(
            id: NoteID(),
            createdAt: timestamp,
            title: "Stage 8 synthetic integration record",
            titleVersion: stamp,
            lifecycleVersion: stamp,
            lastMeaningfulEditAt: timestamp,
            lastMeaningfulEditVersion: stamp
        )
        let mapper = CloudKitRecordMapper()
        let record = mapper.record(from: .note(note))
        do {
            let saved = try await database.modifyRecords(
                saving: [record],
                deleting: [],
                savePolicy: .allKeys,
                atomically: false
            )
            _ = try saved.saveResults[record.recordID]?.get()
            let fetched = try await database.records(for: [record.recordID])
            let fetchedRecord = try XCTUnwrap(fetched[record.recordID]).get()
            XCTAssertEqual(try mapper.syncRecord(from: fetchedRecord), .note(note))
            _ = try await database.modifyRecords(saving: [], deleting: [record.recordID])
        } catch {
            _ = try? await database.modifyRecords(saving: [], deleting: [record.recordID])
            throw error
        }
    }
}
