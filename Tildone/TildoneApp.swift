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
    @State private var showsSyncResolutionOptions = false
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

    private var noteSyncIndicatorState: MacNoteSyncIndicatorState {
        let displayState = MacSyncPresentation.state(
            status: sharedStoreBootstrapper.syncStatus,
            transportState: sharedStoreBootstrapper.transportState,
            enabledByDefault: MacSharedStoreBootstrapper.transportEnabledByDefault,
            hasUnadoptedLocalWorkspace: sharedStoreBootstrapper.hasUnadoptedLocalWorkspace
        )
        return MacNoteSyncIndicatorState.resolve(
            isUsingNotesOnMacByChoice: sharedStoreBootstrapper.isUsingNotesOnMacByChoice,
            syncNeedsAttention: displayState == .attentionNeeded
        )
    }

    var body: some Scene {
        TildonePrimaryScene(isVisible: sharedStoreBootstrapper.error != nil) {
            Group {
                if let store = sharedStoreBootstrapper.store {
                    Desktop(
                        store: store,
                        noteSyncIndicatorState: noteSyncIndicatorState,
                        foregroundNoteID: $foregroundNoteID
                    )
                        .id(ObjectIdentifier(store))
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
            .onAppear {
                appDelegate.setCoordinatorWindowVisible(
                    sharedStoreBootstrapper.error != nil
                )
            }
            .onChange(of: sharedStoreBootstrapper.error != nil) { _, isVisible in
                appDelegate.setCoordinatorWindowVisible(isVisible)
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
                showsSyncResolutionOptions = false
                openWindow(id: Id.syncStatusWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSyncResolutionOptions)) { _ in
                showsSyncResolutionOptions = true
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
            MacSyncStatusView(
                bootstrapper: sharedStoreBootstrapper,
                showsResolutionOptions: $showsSyncResolutionOptions
            )
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

    static func menuBarBadgeSymbol(for state: MacSyncDisplayState) -> String? {
        state == .attentionNeeded ? "exclamationmark.circle.fill" : nil
    }

    static func detail(
        status: SyncStatus,
        state: MacSyncDisplayState,
        hasUnadoptedLocalWorkspace: Bool,
        canAdoptLocalWorkspace: Bool,
        isUsingNotesOnMacByChoice: Bool
    ) -> String {
        if hasUnadoptedLocalWorkspace {
            return canAdoptLocalWorkspace
                ? String(localized: "Your notes remain on this Mac. You can choose to copy them to iCloud. Nothing will be deleted.")
                : String(localized: "Your notes remain safe on this Mac. There are also notes in iCloud, so Tildone will not combine or replace either set automatically.")
        }
        if isUsingNotesOnMacByChoice {
            return String(localized: "Tildone is using the notes saved on this Mac. Notes in iCloud are unchanged, and you can switch at any time.")
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
    @Binding var showsResolutionOptions: Bool
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
        Group {
            if showsResolutionOptions {
                MacNoteResolutionOptions(
                    bootstrapper: bootstrapper,
                    onClose: { showsResolutionOptions = false }
                )
            } else {
                statusContent
            }
        }
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .alert("Copy notes to iCloud?", isPresented: $confirmsAdoption) {
            Button("Cancel", role: .cancel) {}
            Button("Copy Notes") {
                bootstrapper.resolveNotesAfterConfirmation(.combine, requiresEmptyAccount: true)
            }
        } message: {
            Text("Tildone will copy the notes saved on this Mac to iCloud. This is available because there are no Tildone notes in iCloud. The originals will remain on this Mac, and nothing will be deleted.")
        }
    }

    private var statusContent: some View {
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
                isUsingNotesOnMacByChoice: bootstrapper.isUsingNotesOnMacByChoice
            ))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if bootstrapper.syncStatus.pendingMutationCount > 0 {
                Text("Changes waiting to sync: \(bootstrapper.syncStatus.pendingMutationCount)")
                    .font(.callout.monospacedDigit())
                    .accessibilityLabel("Changes waiting to sync: \(bootstrapper.syncStatus.pendingMutationCount)")
            }

            if bootstrapper.isTransportActionInProgress { ProgressView() }

            if bootstrapper.resolutionActionFailed {
                Text("Tildone could not finish that change. Nothing was deleted. Please try again.")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if bootstrapper.didJustChooseNotesOnMac {
                VStack(alignment: .leading, spacing: 10) {
                    Text("These notes won’t appear on your iPhone or in iCloud. You can combine them later.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("OK") { bootstrapper.dismissNotesOnMacNotice() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .font(.callout)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                }
            }

            if bootstrapper.hasNotesOnMacAndICloud {
                Button(
                    bootstrapper.hasUnadoptedLocalWorkspace
                        ? "Review Options…"
                        : "Change Which Notes Tildone Uses…"
                ) {
                    showsResolutionOptions = true
                }
            }

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
    }
}

private struct MacNoteResolutionOptions: View {
    @ObservedObject var bootstrapper: MacSharedStoreBootstrapper
    let onClose: () -> Void
    @State private var pendingAction: MacNoteResolutionAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let pendingAction {
                confirmation(for: pendingAction)
            } else {
                Text("Choose which notes Tildone should use")
                    .font(.title2.bold())
                Text("Your notes on this Mac and in iCloud will remain saved whichever option you choose.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                resolutionOption(
                    title: String(localized: "Combine Notes — Recommended"),
                    detail: String(localized: "Add the notes from this Mac to the notes in iCloud, then use the combined set."),
                    action: .combine
                )
                resolutionOption(
                    title: String(localized: "Use iCloud Notes"),
                    detail: String(localized: "Show the notes already in iCloud. The notes on this Mac stay saved."),
                    action: .useICloud
                )
                resolutionOption(
                    title: String(localized: "Use Notes on This Mac"),
                    detail: String(localized: "Keep showing the notes saved on this Mac. The notes in iCloud stay unchanged."),
                    action: .useThisMac
                )

                HStack {
                    Spacer()
                    Button("Decide Later", action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    private func resolutionOption(
        title: String,
        detail: String,
        action: MacNoteResolutionAction
    ) -> some View {
        Button {
            pendingAction = action
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MacNoteResolutionOptionButtonStyle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func confirmation(for action: MacNoteResolutionAction) -> some View {
        Text(confirmationTitle(for: action))
            .font(.title2.bold())
        Text(confirmationMessage(for: action))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        HStack {
            Spacer()
            Button("Cancel") { pendingAction = nil }
                .keyboardShortcut(.cancelAction)
            Button(confirmationButtonTitle(for: action)) {
                bootstrapper.resolveNotesAfterConfirmation(action)
                pendingAction = nil
                onClose()
            }
            .keyboardShortcut(.defaultAction)
        }
        .disabled(bootstrapper.isTransportActionInProgress)
    }

    private func confirmationTitle(for action: MacNoteResolutionAction) -> String {
        switch action {
        case .combine: String(localized: "Combine notes from this Mac and iCloud?")
        case .useThisMac: String(localized: "Use the notes on this Mac?")
        case .useICloud: String(localized: "Use the notes in iCloud?")
        }
    }

    private func confirmationButtonTitle(for action: MacNoteResolutionAction) -> String {
        switch action {
        case .combine: String(localized: "Combine Notes")
        case .useThisMac: String(localized: "Use This Mac")
        case .useICloud: String(localized: "Use iCloud")
        }
    }

    private func confirmationMessage(for action: MacNoteResolutionAction) -> String {
        switch action {
        case .combine:
            String(localized: "Tildone will add the notes from this Mac to iCloud. If the same note exists in both places, Tildone will combine it the same way it handles edits made on two devices. The notes saved on this Mac will remain available.")
        case .useThisMac:
            String(localized: "Tildone will keep showing the notes saved on this Mac. The notes in iCloud will not be changed, and you can switch later.")
        case .useICloud:
            String(localized: "Tildone will show the notes in iCloud. The notes saved on this Mac will not be changed, and you can switch back later.")
        }
    }
}

private struct MacNoteResolutionOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed
                        ? Color.accentColor.opacity(0.12)
                        : Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The primary scene hosts the one process-wide coordinator that owns every
/// manually managed note window.
struct TildonePrimaryScene<Content: View>: Scene {
    private let isVisible: Bool
    private let content: Content

    init(isVisible: Bool = false, @ViewBuilder content: () -> Content) {
        self.isVisible = isVisible
        self.content = content()
    }

    var body: some Scene {
        Window("Tildone", id: Id.desktopWindow) {
            content
                .background(CoordinatorWindowVisibility(isVisible: isVisible))
        }
    }
}

private struct CoordinatorWindowVisibility: NSViewRepresentable {
    let isVisible: Bool

    func makeNSView(context: Context) -> CoordinatorView {
        CoordinatorView(isVisible: isVisible)
    }

    func updateNSView(_ view: CoordinatorView, context: Context) {
        view.isVisible = isVisible
    }

    final class CoordinatorView: NSView {
        var isVisible: Bool {
            didSet { updateWindowVisibility() }
        }

        init(isVisible: Bool) {
            self.isVisible = isVisible
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateWindowVisibility()
        }

        private func updateWindowVisibility() {
            guard let window else { return }
            if isVisible {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderOut(nil)
                DispatchQueue.main.async { [weak window] in
                    window?.orderOut(nil)
                }
            }
        }
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
    static let openSyncResolutionOptions = Notification.Name("openSyncResolutionOptions")
    static let pauseSync = Notification.Name("pauseSync")
    static let resumeSync = Notification.Name("resumeSync")
    static let syncNow = Notification.Name("syncNow")
    static let updateCompletedTaskOrdering = Notification.Name("updateCompletedTaskOrdering")
    static let noteWindowOpacityChanged = Notification.Name("noteWindowOpacityChanged")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var isCoordinatorWindowVisible = false
    private var coordinatorWindowObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        AppAppearance.prepareDockIconPreference()
        applyDockIconVisibility()
        MenuBarController.shared.install()
        coordinatorWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.hideCoordinatorWindowIfNeeded(notification)
        }
    }

    deinit {
        if let coordinatorWindowObserver {
            NotificationCenter.default.removeObserver(coordinatorWindowObserver)
        }
    }

    func setCoordinatorWindowVisible(_ isVisible: Bool) {
        isCoordinatorWindowVisible = isVisible
        guard isVisible else { return }
        coordinatorWindow()?.makeKeyAndOrderFront(nil)
    }

    func applyDockIconVisibility() {
        let shouldShowDockIcon = UserDefaults.standard.bool(forKey: AppAppearance.showDockIconStorageKey)
        NSApplication.shared.setActivationPolicy(shouldShowDockIcon ? .regular : .accessory)
    }

    private func hideCoordinatorWindowIfNeeded(_ notification: Notification) {
        guard !isCoordinatorWindowVisible,
              let window = notification.object as? NSWindow,
              isCoordinatorWindow(window) else {
            return
        }
        window.orderOut(nil)
    }

    private func coordinatorWindow() -> NSWindow? {
        NSApplication.shared.windows.first(where: isCoordinatorWindow)
    }

    private func isCoordinatorWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == Id.desktopWindow || window.title == "Tildone"
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
        button.image = Self.menuBarImage(for: .active, accessibilityDescription: "Tildone")
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
            syncActionItem?.image = menuImage(named: "play.circle")
        } else {
            syncActionItem?.title = String(localized: "Pause Sync")
            syncActionItem?.action = #selector(pauseSync)
            syncActionItem?.image = menuImage(named: "pause.circle")
        }

        guard let button = statusItem.button else { return }
        button.image = Self.menuBarImage(for: state, accessibilityDescription: title)
        button.toolTip = title
        button.setAccessibilityValue(title)
    }

    static func menuBarImage(
        for state: MacSyncDisplayState,
        accessibilityDescription: String
    ) -> NSImage? {
        guard let source = NSImage(named: "MenuBarIcon"),
              let base = source.copy() as? NSImage else {
            return nil
        }
        base.isTemplate = true
        base.size = NSSize(width: 16, height: 16)
        guard let badgeName = MacSyncPresentation.menuBarBadgeSymbol(for: state),
              let badge = NSImage(
                systemSymbolName: badgeName,
                accessibilityDescription: accessibilityDescription
              )?.withSymbolConfiguration(.init(pointSize: 8, weight: .bold)) else {
            return base
        }

        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            base.draw(in: NSRect(x: 1, y: 1, width: 16, height: 16))
            badge.draw(in: NSRect(x: 10, y: 10, width: 8, height: 8))
            return true
        }
        image.isTemplate = true
        return image
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
        menu.addItem(item(String(localized: "About Tildone"), action: #selector(openAbout), symbolName: "info.circle"))
        menu.addItem(.separator())

        menu.addItem(item(String(localized: "New Note"), action: #selector(createNote), keyEquivalent: "n", symbolName: "square.and.pencil"))

        let minimizeAll = item(String(localized: "Minimize All"), action: #selector(minimizeAll), keyEquivalent: "m", symbolName: "minus.square")
        minimizeAll.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(minimizeAll)

        let bringAllUp = item(String(localized: "Bring All Up"), action: #selector(bringAllUp), keyEquivalent: "u", symbolName: "app.shadow")
        bringAllUp.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(bringAllUp)

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
        let syncAction = item(String(localized: "Pause Sync"), action: #selector(pauseSync), symbolName: "pause.circle")
        syncAction.isHidden = true
        syncActionItem = syncAction
        menu.addItem(syncAction)
        menu.addItem(item(String(localized: "Sync Status…"), action: #selector(openSyncStatus), symbolName: "arrow.trianglehead.2.clockwise.rotate.90.icloud"))

        menu.addItem(.separator())
        let settings = item(String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",", symbolName: "gearshape")
        settings.keyEquivalentModifierMask = .command
        menu.addItem(settings)
        menu.addItem(item(String(localized: "How to Use Focus Filters…"), action: #selector(openFocusFilterHelp), symbolName: "moon"))

        menu.addItem(.separator())
        let quit = item(String(localized: "Quit Tildone"), action: #selector(quit), keyEquivalent: "q", symbolName: "power")
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
        return menu
    }

    private func item(
        _ title: String,
        action: Selector,
        keyEquivalent: String = "",
        symbolName: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.image = symbolName.flatMap(menuImage(named:))
        return item
    }

    private func menuImage(named symbolName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func createNote() { sendToActiveApp(.new) }
    @objc private func minimizeAll() { sendToActiveApp(.minimizeAll) }
    @objc private func bringAllUp() { sendToActiveApp(.bringAllUp) }
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
