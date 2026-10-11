import CloudKit
import SwiftUI
import XCTest
import TildoneDomain
import TildonePersistence
import TildoneSync
@testable import Tildone

@MainActor
final class SyncProductQualificationTests: XCTestCase {
    func testConfirmedLocationChoicesRetainBothStoresAcrossReopen() async throws {
        XCTAssertFalse(MacSharedStoreBootstrapper.transportEnabledByDefault)
        for action in [MacNoteResolutionAction.useThisMac, .useICloud, .combine] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("LocationFixture-\(UUID())")
            let suite = "LocationFixture.\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer {
                defaults.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: root)
            }
            let accountID = UUID()
            let localDescriptor = PersistenceStoreDescriptor.persistent(baseDirectory: root, workspace: .localOnly)
            let accountDescriptor = PersistenceStoreDescriptor.persistent(baseDirectory: root, workspace: .account(accountID))
            var local: TildoneRepository? = try TildoneRepository(descriptor: localDescriptor)
            var account: TildoneRepository? = try TildoneRepository(descriptor: accountDescriptor)
            let localNote = try await local!.createNote(id: NoteID(), createdAt: Date(), title: "Synthetic Mac source")
            _ = try await local!.addTask(id: TaskID(), to: localNote.id, createdAt: Date(), text: "Retain Mac text", orderToken: OrderToken.between(nil, nil))
            let cloudNote = try await account!.createNote(id: NoteID(), createdAt: Date(), title: "Synthetic account source")
            _ = try await account!.addTask(id: TaskID(), to: cloudNote.id, createdAt: Date(), text: "Retain account text", orderToken: OrderToken.between(nil, nil))
            let removed = try await local!.addTask(id: TaskID(), to: localNote.id, createdAt: Date(), text: "Synthetic tombstone", orderToken: OrderToken(rawValue: "z"))
            try await local!.deleteTask(id: removed.id)
            let sourceFingerprint = try await MacNoteResolutionService.fingerprint(repository: local!)
            let sourceOutbox = try await local!.pendingMutations(includeSuperseded: true)
            let accountFingerprint = try await MacNoteResolutionService.fingerprint(repository: account!)
            let accountOutbox = try await account!.pendingMutations(includeSuperseded: true)
            var model: MacSharedStoreBootstrapper? = try await .isolatedPresentation(
                localRepository: local!, accountRepository: account!, workspaceID: accountID,
                defaults: defaults, status: SyncStatus(availability: .adoptionRequired, activity: .attentionNeeded)
            )
            XCTAssertTrue(model!.hasUnadoptedLocalWorkspace)
            XCTAssertFalse(model!.isUsingAccountWorkspace)
            model!.resolveNotesAfterConfirmation(action)
            for _ in 0..<200 where model!.isTransportActionInProgress {
                try await Swift.Task.sleep(for: .milliseconds(10))
            }
            XCTAssertFalse(model!.isTransportActionInProgress)
            XCTAssertFalse(model!.resolutionActionFailed)
            XCTAssertFalse(model!.canControlTransport)
            let choice = action == .useThisMac ? MacNoteLocationChoice.thisMac : .iCloud
            XCTAssertEqual(MacNoteLocationChoiceStore(defaults: defaults).choice(for: accountID), choice)
            XCTAssertEqual(model!.isUsingAccountWorkspace, action != .useThisMac)
            model = nil
            local = nil
            account = nil
            let reopenedLocal = try TildoneRepository(descriptor: localDescriptor)
            let reopenedAccount = try TildoneRepository(descriptor: accountDescriptor)
            let fingerprintAfter = try await MacNoteResolutionService.fingerprint(repository: reopenedLocal)
            let outboxAfter = try await reopenedLocal.pendingMutations(includeSuperseded: true)
            XCTAssertEqual(fingerprintAfter, sourceFingerprint)
            XCTAssertEqual(outboxAfter, sourceOutbox)
            if action == .combine {
                let notes = try await reopenedAccount.allSyncNotes()
                let tasks = try await reopenedAccount.allSyncTasks()
                XCTAssertEqual(Set(notes.map(\.id)), [localNote.id, cloudNote.id])
                XCTAssertTrue(tasks.contains { $0.id == removed.id && $0.lifecycle == .deleted })
            } else {
                let fingerprint = try await MacNoteResolutionService.fingerprint(repository: reopenedAccount)
                let outbox = try await reopenedAccount.pendingMutations(includeSuperseded: true)
                XCTAssertEqual(fingerprint, accountFingerprint)
                XCTAssertEqual(outbox, accountOutbox)
            }
            let relaunched = try await MacSharedStoreBootstrapper.isolatedPresentation(
                localRepository: reopenedLocal, accountRepository: reopenedAccount, workspaceID: accountID,
                defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), status: .disabled
            )
            XCTAssertEqual(relaunched.isUsingAccountWorkspace, action != .useThisMac)
            XCTAssertEqual(relaunched.isUsingNotesOnMacByChoice, action == .useThisMac)
            XCTAssertFalse(relaunched.hasUnadoptedLocalWorkspace)
        }
    }

    func testRecoveryAndLocationViewsRenderInBothAppearancesAndLargerBodyText() async throws {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        if let expected = ProcessInfo.processInfo.environment["TILDONE_EXPECTED_PRODUCT_LANGUAGE"] {
            XCTAssertEqual(language, expected, "The hosted app must actually use the requested localization")
            if expected != "en" {
                XCTAssertNotEqual(MacSyncPresentation.title(for: .attentionNeeded), "iCloud sync needs attention")
            }
        }
        let suite = "RecoveryRender.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let accountID = UUID()
        MacNoteLocationChoiceStore(defaults: defaults).set(.iCloud, for: accountID)
        let local = try TildoneRepository(descriptor: .inMemory())
        let account = try TildoneRepository(descriptor: .inMemory(workspace: .account(accountID)))
        let note = try await local.createNote(id: NoteID(), createdAt: Date(), title: "Synthetic presentation only")
        _ = try await local.addTask(id: TaskID(), to: note.id, createdAt: Date(), text: "Retained source", orderToken: OrderToken.between(nil, nil))
        let other = try await account.createNote(id: NoteID(), createdAt: Date(), title: "Synthetic account presentation")
        _ = try await account.addTask(id: TaskID(), to: other.id, createdAt: Date(), text: "Retained account", orderToken: OrderToken.between(nil, nil))
        let sourceFingerprint = try await MacNoteResolutionService.fingerprint(repository: local)
        for appearance in [ColorScheme.light, .dark] {
            for larger in [false, true] {
                for availability in [SyncAvailability.zoneResetRequired, .incompatibleRemoteData] {
                    let model = try await MacSharedStoreBootstrapper.isolatedPresentation(
                        localRepository: local, accountRepository: account, workspaceID: accountID,
                        defaults: defaults,
                        status: SyncStatus(availability: availability, activity: .attentionNeeded, pendingMutationCount: 123)
                    )
                    XCTAssertFalse(model.canControlTransport)
                    try render(
                        MacSyncStatusView(bootstrapper: model, showsResolutionOptions: .constant(false)),
                        name: "\(availability.rawValue)-\(language)-\(appearance)-\(larger)",
                        appearance: appearance, larger: larger
                    )
                }
                let model = try await MacSharedStoreBootstrapper.isolatedPresentation(
                    localRepository: local, accountRepository: account, workspaceID: accountID,
                    defaults: defaults, status: .disabled
                )
                try render(MacSyncStatusView(bootstrapper: model, showsResolutionOptions: .constant(true)),
                           name: "choices-\(language)-\(appearance)-\(larger)", appearance: appearance, larger: larger)
                for action in [MacNoteResolutionAction.combine, .useICloud, .useThisMac] {
                    try render(
                        MacNoteResolutionOptions(isolatedConfirmation: action, bootstrapper: model).padding(24).frame(width: 480),
                        name: "confirmation-\(action)-\(language)-\(appearance)-\(larger)", appearance: appearance, larger: larger
                    )
                }
            }
        }
        let after = try await MacNoteResolutionService.fingerprint(repository: local)
        XCTAssertEqual(sourceFingerprint, after, "Presentation alone cannot mutate the source")
        print("SyncProductRender language=\(language) images=24")
    }

    func testPrivacyAboutUsesNativeLinkRendering() async throws {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        if let expected = ProcessInfo.processInfo.environment["TILDONE_EXPECTED_PRODUCT_LANGUAGE"] {
            XCTAssertEqual(language, expected)
        }
        let previousKey = NSApp.keyWindow
        defer { previousKey?.makeKey() }
        for appearance in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: About().environment(\.colorScheme, appearance))
            let window = NSWindow(
                contentRect: NSRect(x: -10000, y: -10000, width: Frame.aboutWindowWidth, height: Frame.aboutWindowHeight),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
            window.contentView = host
            window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            host.layoutSubtreeIfNeeded()
            try await Swift.Task.sleep(for: .milliseconds(100))
            host.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "privacy-about-native-\(language)-\(appearance)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func render<V: View>(
        _ view: V, name: String, appearance: ColorScheme, larger: Bool, width: CGFloat = 480
    ) throws {
        let renderer = ImageRenderer(content: view
            .environment(\.colorScheme, appearance)
            .environment(\.font, .system(size: larger ? 22 : 13))
            .background(appearance == .dark ? Color(nsColor: .black) : .white))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, width, accuracy: 1)
        XCTAssertLessThanOrEqual(image.size.height, 760, "Must fit a normal Mac display")
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
