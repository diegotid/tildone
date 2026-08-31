//
//  TildoneApp.swift
//  Tildone
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
                Button("Line Up Notes") {
                    NotificationCenter.default.post(name: .arrange, object: nil)
                }
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
        .windowResizability(.contentSize)
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
