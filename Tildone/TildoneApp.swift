//
//  TildoneApp.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import SwiftUI
import TildoneDomain
import TildoneSync

@main
struct TildoneApp: App {
    @State private var foregroundNoteID: NoteID?
    @StateObject private var sharedStoreBootstrapper = MacSharedStoreBootstrapper()
    @Environment(\.openWindow) var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var isCloseCommandDisabled: Bool {
        if let noteID = foregroundNoteID, let note = sharedStoreBootstrapper.store?.note(noteID) {
            !note.isDeletable
        } else {
            false
        }
    }

    var body: some Scene {
        TildonePrimaryScene {
            Group {
                if let store = sharedStoreBootstrapper.store {
                    Desktop(store: store, foregroundNoteID: $foregroundNoteID)
                } else if sharedStoreBootstrapper.error != nil {
                    VStack(spacing: 12) {
                        Text("Tildone could not open your notes.").font(.headline)
                        Text("Your existing notes have not been changed. Tildone needs your help before it can open them.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                } else {
                    ProgressView()
                        .onAppear { sharedStoreBootstrapper.start() }
                }
            }
            .onAppear { updateMenuBarSyncPresentation() }
            .onChange(of: sharedStoreBootstrapper.syncStatus) { _, _ in
                updateMenuBarSyncPresentation()
            }
            .onChange(of: sharedStoreBootstrapper.transportState) { _, _ in
                updateMenuBarSyncPresentation()
            }
            .onChange(of: sharedStoreBootstrapper.hasUnadoptedLocalWorkspace) { _, _ in
                updateMenuBarSyncPresentation()
            }
            .onChange(of: sharedStoreBootstrapper.hasResolvedAccountWorkspace) { _, _ in
                updateMenuBarSyncPresentation()
            }
            .onChange(of: sharedStoreBootstrapper.isUsingAccountWorkspace) { _, _ in
                updateMenuBarSyncPresentation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pauseSync)) { _ in
                sharedStoreBootstrapper.pauseTransport()
            }
            .onReceive(NotificationCenter.default.publisher(for: .resumeSync)) { _ in
                sharedStoreBootstrapper.resumeTransport()
            }
            .onReceive(NotificationCenter.default.publisher(for: .syncNow)) { _ in
                sharedStoreBootstrapper.syncNow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSyncStatus)) { _ in
                openWindow(id: Id.syncStatusWindow)
            }
        }
        .environment(\.license, .free)
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
        .commandsRemoved()
        .commandsReplaced {
            CommandGroup(replacing: .appInfo) {
                Button("About Tildone") {
                    openWindow(id: Id.aboutWindow)
                }
                SettingsLink {
                    Text("Settings...")
                }
                .keyboardShortcut(",")
                Button("Quit Tildone") {
                    NSApplication.shared.terminate(self)
                }
                .keyboardShortcut("q")
            }
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    NotificationCenter.default.post(name: .new, object: nil)
                }
                .keyboardShortcut("n")
                Button(foregroundNoteID != nil ? "Discard Empty Note" : "Close window") {
                    NotificationCenter.default.post(name: .close, object: nil)
                }
                .disabled(isCloseCommandDisabled)
                .keyboardShortcut("w")
            }
            CommandGroup(replacing: .textEditing) {
                Menu("Copy") {
                    Button("Copy task text") {
                        NotificationCenter.default.post(name: .copy, object: nil)
                    }
                    .keyboardShortcut("c")
                    Button("Copy whole task list") {
                        if let note = foregroundNoteID.flatMap({ sharedStoreBootstrapper.store?.note($0) }) {
                            let items = note.tasks.map { "<li>\($0.text)</li>" }.joined()
                            let title = note.title.map { "<strong>\($0)</strong>" } ?? ""
                            Copier.copy("\(title)<ul>\(items)</ul>", forType: .html)
                        }
                    }
                    .keyboardShortcut("c", modifiers: [.shift, .command])
                }
                Button("Paste") {
                    NotificationCenter.default.post(name: .paste, object: nil)
                }
                .keyboardShortcut("v")
            }
            CommandGroup(replacing: .toolbar) {
                Button("Minimize All") {
                    NotificationCenter.default.post(name: .minimizeAll, object: nil)
                }
                .keyboardShortcut("m", modifiers: [.shift, .command])
                Button("Bring All Up") {
                    NotificationCenter.default.post(name: .bringAllUp, object: nil)
                }
                .keyboardShortcut("u", modifiers: [.shift, .command])
                Divider()
                Button("Arrange Notes") {
                    NotificationCenter.default.post(name: .arrange, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.shift, .command])
            }
        }
        Window("About Tildone.window", id: Id.aboutWindow) {
            About()
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
        Window("Focus Filters", id: Id.focusFilterHelpWindow) {
            FocusFilterHelp()
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
        Window("iCloud Sync", id: Id.syncStatusWindow) {
            MacSyncStatusView(bootstrapper: sharedStoreBootstrapper)
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
        Settings {
            SettingsForm()
        }
        .commandsRemoved()
    }

    private func updateMenuBarSyncPresentation() {
        MenuBarController.shared.updateSyncPresentation(
            status: sharedStoreBootstrapper.syncStatus,
            transportState: sharedStoreBootstrapper.transportState,
            enabledByDefault: MacSharedStoreBootstrapper.transportEnabledByDefault,
            hasResolvedAccountWorkspace: sharedStoreBootstrapper.hasResolvedAccountWorkspace,
            isUsingAccountWorkspace: sharedStoreBootstrapper.isUsingAccountWorkspace,
            hasUnadoptedLocalWorkspace: sharedStoreBootstrapper.hasUnadoptedLocalWorkspace
        )
    }
}

private struct FocusFilterHelp: View {
    private let focusSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Focus-Settings.extension"
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Focus Filters", systemImage: "moon.stars.fill")
                .font(.title2.bold())
            Text("Focus Filters can automatically blur task text or let notes stay behind other windows while a Focus is active.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                FocusFilterHelpStep(number: 1, text: "Open System Settings and choose Focus.")
                FocusFilterHelpStep(number: 2, text: "Select the Focus you want to configure.")
                FocusFilterHelpStep(number: 3, text: "Under Focus Filters, click Add Filter, then choose Tildone.")
                FocusFilterHelpStep(number: 4, text: "Choose how Tildone should behave and click Add.")
            }
            Text("To change or remove the filter later, return to the same Focus settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let focusSettingsURL {
                HStack {
                    Spacer()
                    Button("Open Focus Settings") { NSWorkspace.shared.open(focusSettingsURL) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FocusFilterHelpStep: View {
    let number: Int
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(text)
        }
    }
}

enum MacSyncDisplayState: Equatable {
    case active
    case paused
    case attentionNeeded
    case disabled
}

enum MacSyncPresentation {
    static func state(
        status: SyncStatus,
        transportState: SyncTransportState,
        enabledByDefault: Bool,
        hasUnadoptedLocalWorkspace: Bool
    ) -> MacSyncDisplayState {
        if hasUnadoptedLocalWorkspace || status.activity == .attentionNeeded || [
            .noAccount,
            .restricted,
            .temporarilyUnavailable,
            .adoptionRequired,
            .accountChanged,
            .zoneResetRequired,
            .incompatibleRemoteData
        ].contains(status.availability) {
            return .attentionNeeded
        }
        guard enabledByDefault, status.availability != .disabled else { return .disabled }
        return transportState == .paused || status.activity == .paused ? .paused : .active
    }

    static func title(for state: MacSyncDisplayState) -> String {
        switch state {
        case .active: String(localized: "iCloud sync is active")
        case .paused: String(localized: "iCloud sync is paused")
        case .attentionNeeded: String(localized: "iCloud sync needs attention")
        case .disabled: String(localized: "iCloud sync is disabled")
        }
    }

    static func symbol(for state: MacSyncDisplayState) -> String {
        switch state {
        case .active: "icloud"
        case .paused: "pause.circle"
        case .attentionNeeded: "exclamationmark.triangle.fill"
        case .disabled: "icloud.slash"
        }
    }

    static func detail(
        status: SyncStatus,
        state: MacSyncDisplayState,
        hasUnadoptedLocalWorkspace: Bool,
        canAdoptLocalWorkspace: Bool,
        adoptionCompletedAwaitingRelaunch: Bool
    ) -> String {
        if adoptionCompletedAwaitingRelaunch {
            return String(localized: "Your notes on this Mac were copied to iCloud. Reopen Tildone to use the iCloud copy. The originals remain saved on this Mac.")
        }
        if hasUnadoptedLocalWorkspace {
            return canAdoptLocalWorkspace
                ? String(localized: "Your notes remain on this Mac. You can choose to copy them to iCloud. Nothing will be deleted.")
                : String(localized: "Your notes remain safe on this Mac. There are also notes in iCloud, so Tildone will not combine or replace either set automatically.")
        }
        switch status.availability {
        case .zoneResetRequired:
            return String(localized: "Tildone’s storage in iCloud is missing or was reset. Sync has stopped, but your notes and unsent changes are safe. Tildone will not rebuild or upload them again without your permission.")
        case .incompatibleRemoteData:
            return String(localized: "The notes in iCloud were saved by a newer version of Tildone. You can keep editing on this Mac, and Tildone will not replace the iCloud notes.")
        case .accountChanged:
            return String(localized: "The iCloud account changed. Tildone stopped syncing the previous account’s notes to keep them separate.")
        case .noAccount:
            return String(localized: "Sign in to iCloud with the account you want to use, then reopen Tildone. Notes saved on this Mac will not be uploaded automatically.")
        case .restricted:
            return String(localized: "Tildone cannot use iCloud with this account. You can keep editing on this Mac.")
        case .temporarilyUnavailable:
            return String(localized: "iCloud is temporarily unavailable. You can keep editing, and your unsent changes remain safe.")
        default:
            break
        }
        if status.activity == .attentionNeeded {
            return String(localized: "Sync could not finish. You can keep editing, and your unsent changes remain safe.")
        }
        switch state {
        case .active:
            return String(localized: "Tildone sends and receives your changes through iCloud.")
        case .paused:
            return String(localized: "You can keep editing. Nothing will be sent to or downloaded from iCloud until you resume.")
        case .attentionNeeded:
            return String(localized: "Tildone needs your help with iCloud. It has not deleted or replaced any notes.")
        case .disabled:
            return String(localized: "iCloud sync is turned off in this version of Tildone. Your notes stay where they are.")
        }
    }
}

private struct MacSyncStatusView: View {
    @ObservedObject var bootstrapper: MacSharedStoreBootstrapper
    @State private var confirmsAdoption = false

    private var displayState: MacSyncDisplayState {
        MacSyncPresentation.state(
            status: bootstrapper.syncStatus,
            transportState: bootstrapper.transportState,
            enabledByDefault: MacSharedStoreBootstrapper.transportEnabledByDefault,
            hasUnadoptedLocalWorkspace: bootstrapper.hasUnadoptedLocalWorkspace
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                MacSyncPresentation.title(for: displayState),
                systemImage: MacSyncPresentation.symbol(for: displayState)
            )
            .font(.title2.bold())

            Text(MacSyncPresentation.detail(
                status: bootstrapper.syncStatus,
                state: displayState,
                hasUnadoptedLocalWorkspace: bootstrapper.hasUnadoptedLocalWorkspace,
                canAdoptLocalWorkspace: bootstrapper.canAdoptLocalWorkspace,
                adoptionCompletedAwaitingRelaunch: bootstrapper.adoptionCompletedAwaitingRelaunch
            ))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if bootstrapper.syncStatus.pendingMutationCount > 0 {
                Text("Changes waiting to sync: \(bootstrapper.syncStatus.pendingMutationCount)")
                    .font(.callout.monospacedDigit())
                    .accessibilityLabel("Changes waiting to sync: \(bootstrapper.syncStatus.pendingMutationCount)")
            }

            if bootstrapper.isTransportActionInProgress { ProgressView() }

            HStack {
                if bootstrapper.canAdoptLocalWorkspace {
                    Button("Copy Notes to iCloud…") { confirmsAdoption = true }
                }
                Spacer()
                if bootstrapper.canControlTransport {
                    if bootstrapper.transportState == .paused {
                        Button("Resume Sync") { bootstrapper.resumeTransport() }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Sync Now") { bootstrapper.syncNow() }
                        Button("Pause Sync") { bootstrapper.pauseTransport() }
                    }
                }
            }
            .disabled(bootstrapper.isTransportActionInProgress)
        }
        .padding(24)
        .frame(width: 430)
        .fixedSize(horizontal: false, vertical: true)
        .alert("Copy notes to iCloud?", isPresented: $confirmsAdoption) {
            Button("Cancel", role: .cancel) {}
            Button("Copy Notes") { bootstrapper.adoptLocalWorkspaceAfterConfirmation() }
        } message: {
            Text("Tildone will copy the notes saved on this Mac to iCloud. This is available because there are no Tildone notes in iCloud. The originals will remain on this Mac, and nothing will be deleted.")
        }
    }
}

/// The primary scene hosts the one process-wide coordinator that owns every
/// manually managed note window.
struct TildonePrimaryScene<Content: View>: Scene {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some Scene {
        Window("Tildone", id: Id.desktopWindow) { content }
    }
}

extension Notification.Name {
    static let new = Notification.Name("new")
    static let close = Notification.Name("close")
    static let copy = Notification.Name("copy")
    static let paste = Notification.Name("paste")
    static let clean = Notification.Name("clean")
    static let arrange = Notification.Name("arrange")
    static let arrangeMinimized = Notification.Name("arrangeMinimized")
    static let minimizeAll = Notification.Name("minimizeAll")
    static let bringAllUp = Notification.Name("bringAllUp")
    static let visibility = Notification.Name("visibility")
    static let openSettings = Notification.Name("openSettings")
    static let openAbout = Notification.Name("openAbout")
    static let openFocusFilterHelp = Notification.Name("openFocusFilterHelp")
    static let openSyncStatus = Notification.Name("openSyncStatus")
    static let pauseSync = Notification.Name("pauseSync")
    static let resumeSync = Notification.Name("resumeSync")
    static let syncNow = Notification.Name("syncNow")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        AppAppearance.prepareDockIconPreference()
        applyDockIconVisibility()
        MenuBarController.shared.install()
    }

    func applyDockIconVisibility() {
        let shouldShowDockIcon = UserDefaults.standard.bool(forKey: AppAppearance.showDockIconStorageKey)
        NSApplication.shared.setActivationPolicy(shouldShowDockIcon ? .regular : .accessory)
    }
}

/// AppKit exposes the status button, which lets a new empty menu-bar-only
/// installation present its menu once without relying on private APIs.
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var hasPresentedInitialMenu = false
    private var syncHeaderItem: NSMenuItem?
    private var syncPendingItem: NSMenuItem?
    private var syncActionItem: NSMenuItem?

    func install() {
        guard let button = statusItem.button else { return }
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        button.image = image
        button.toolTip = "Tildone"
        button.setAccessibilityLabel("Tildone")
        button.setAccessibilityHelp(String(localized: "Open Tildone and review iCloud sync status"))
        statusItem.menu = makeMenu()
    }

    func updateSyncPresentation(
        status: SyncStatus,
        transportState: SyncTransportState,
        enabledByDefault: Bool,
        hasResolvedAccountWorkspace: Bool,
        isUsingAccountWorkspace: Bool,
        hasUnadoptedLocalWorkspace: Bool
    ) {
        let state = MacSyncPresentation.state(
            status: status,
            transportState: transportState,
            enabledByDefault: enabledByDefault,
            hasUnadoptedLocalWorkspace: hasUnadoptedLocalWorkspace
        )
        let title = MacSyncPresentation.title(for: state)
        syncHeaderItem?.title = title
        syncHeaderItem?.image = NSImage(
            systemSymbolName: MacSyncPresentation.symbol(for: state),
            accessibilityDescription: title
        )

        syncPendingItem?.isHidden = status.pendingMutationCount == 0
        syncPendingItem?.title = String(
            localized: "Changes waiting to sync: \(status.pendingMutationCount)"
        )

        let canControl = enabledByDefault && hasResolvedAccountWorkspace && isUsingAccountWorkspace
        syncActionItem?.isHidden = !canControl
        if transportState == .paused {
            syncActionItem?.title = String(localized: "Resume Sync")
            syncActionItem?.action = #selector(resumeSync)
        } else {
            syncActionItem?.title = String(localized: "Pause Sync")
            syncActionItem?.action = #selector(pauseSync)
        }

        guard let button = statusItem.button else { return }
        let image = state == .active
            ? NSImage(named: "MenuBarIcon")
            : NSImage(
                systemSymbolName: MacSyncPresentation.symbol(for: state),
                accessibilityDescription: title
            )
        image?.isTemplate = true
        image?.size = NSSize(width: 16, height: 16)
        button.image = image
        button.toolTip = title
        button.setAccessibilityValue(title)
    }

    func presentMenuForEmptyMenuBarOnlyWorkspace() {
        guard !hasPresentedInitialMenu,
              !UserDefaults.standard.bool(forKey: AppAppearance.showDockIconStorageKey) else {
            return
        }
        hasPresentedInitialMenu = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("About Tildone", action: #selector(openAbout)))
        menu.addItem(.separator())

        menu.addItem(item("New Note", action: #selector(createNote), keyEquivalent: "n"))

        let showAllNotes = item("Show All Notes", action: #selector(showAllNotes), keyEquivalent: "u")
        showAllNotes.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(showAllNotes)

        menu.addItem(.separator())
        let syncHeader = NSMenuItem(title: String(localized: "iCloud sync is disabled"), action: nil, keyEquivalent: "")
        syncHeader.isEnabled = false
        syncHeaderItem = syncHeader
        menu.addItem(syncHeader)
        let syncPending = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        syncPending.isEnabled = false
        syncPending.isHidden = true
        syncPendingItem = syncPending
        menu.addItem(syncPending)
        let syncAction = item(String(localized: "Pause Sync"), action: #selector(pauseSync))
        syncAction.isHidden = true
        syncActionItem = syncAction
        menu.addItem(syncAction)
        menu.addItem(item(String(localized: "Sync Status…"), action: #selector(openSyncStatus)))

        menu.addItem(.separator())
        let settings = item("Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = .command
        menu.addItem(settings)
        menu.addItem(item(String(localized: "How to Use Focus Filters…"), action: #selector(openFocusFilterHelp)))

        menu.addItem(.separator())
        let quit = item("Quit Tildone", action: #selector(quit), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
        return menu
    }

    private func item(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func createNote() { sendToActiveApp(.new) }
    @objc private func showAllNotes() { sendToActiveApp(.bringAllUp) }
    @objc private func openSettings() { sendToActiveApp(.openSettings) }
    @objc private func openAbout() { sendToActiveApp(.openAbout) }
    @objc private func openFocusFilterHelp() { sendToActiveApp(.openFocusFilterHelp) }
    @objc private func openSyncStatus() { sendToActiveApp(.openSyncStatus) }
    @objc private func pauseSync() { sendToActiveApp(.pauseSync) }
    @objc private func resumeSync() { sendToActiveApp(.resumeSync) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    /// A status-item click doesn't activate its app. Defer SwiftUI scene work
    /// until AppKit has closed the tracking menu and Tildone is foregrounded.
    private func sendToActiveApp(_ name: Notification.Name) {
        NSApplication.shared.activate()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }
}
