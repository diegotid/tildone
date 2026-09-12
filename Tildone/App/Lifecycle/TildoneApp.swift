//
//  TildoneApp.swift
//  Tildone
//

import AppKit
import SwiftUI
import TildoneDomain
import TildoneSync

@main
struct TildoneApp: App {
    @State private var foregroundNoteID: NoteID?
    @State private var showsSyncResolutionOptions = false
    @State private var undoErrorMessage: String?
    @StateObject private var sharedStoreBootstrapper = MacSharedStoreBootstrapper()
    @Environment(\.openWindow) var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        SingleMemoTypography.registerBundledFonts()
    }

    var isCloseCommandDisabled: Bool {
        if let noteID = foregroundNoteID, let note = sharedStoreBootstrapper.store?.note(noteID) {
            !note.isDeletable
        } else {
            false
        }
    }

    var closeCommandTitle: LocalizedStringKey {
        guard let noteID = foregroundNoteID,
              let note = sharedStoreBootstrapper.store?.note(noteID),
              note.isEmpty else {
            return "Close Window"
        }
        return "Discard Empty Note"
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
            .onAppear { updateMenuBarCopyPresentation() }
            .onChange(of: foregroundNoteID) { _, _ in
                updateMenuBarCopyPresentation()
            }
            .onChange(of: foregroundNoteTitle) { _, _ in
                updateMenuBarCopyPresentation()
            }
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
            .onReceive(NotificationCenter.default.publisher(for: .copyNoteContents)) { _ in
                copyForegroundNoteContents()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSyncStatus)) { _ in
                showsSyncResolutionOptions = false
                openWindow(id: Id.syncStatusWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSyncResolutionOptions)) { _ in
                showsSyncResolutionOptions = true
                openWindow(id: Id.syncStatusWindow)
            }
            .alert("Couldn’t undo this change", isPresented: Binding(
                get: { undoErrorMessage != nil },
                set: { if !$0 { undoErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { undoErrorMessage = nil }
            } message: {
                Text(undoErrorMessage ?? "")
            }
        }
        .environment(\.license, .free)
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                if let store = sharedStoreBootstrapper.store {
                    MacUndoMenuButton(store: store) { _ in
                        undoErrorMessage = String(localized: "The change could not be undone. Your notes were not otherwise changed.")
                    }
                } else {
                    Button("Undo") {}
                        .disabled(true)
                        .keyboardShortcut("z", modifiers: .command)
                }
                Button("Redo") {}
                    .disabled(true)
                    .keyboardShortcut("z", modifiers: [.shift, .command])
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Tildone") {
                    openWindow(id: Id.aboutWindow)
                }
            }
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Settings…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Note") {
                    NotificationCenter.default.post(name: .new, object: nil)
                }
                .keyboardShortcut("n")
                Button(closeCommandTitle) {
                    NotificationCenter.default.post(name: .close, object: nil)
                }
                .disabled(isCloseCommandDisabled)
                .keyboardShortcut("w")
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Cut") {
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("x")
                Button("Copy") {
                    if !NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) {
                        NotificationCenter.default.post(name: .copy, object: nil)
                    }
                }
                .keyboardShortcut("c")
                Button("Copy Note Contents") {
                    copyForegroundNoteContents()
                }
                .disabled(foregroundNoteID == nil)
                .keyboardShortcut("c", modifiers: [.shift, .command])
                Button("Paste") {
                    if !NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) {
                        NotificationCenter.default.post(name: .paste, object: nil)
                    }
                }
                .keyboardShortcut("v")
                Button("Select All") {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("a")
            }
            MacTaskTextFormatCommands(isEnabled: foregroundNoteID != nil)
            CommandGroup(after: .toolbar) {
                Menu("Visible Note Colors") {
                    ForEach(NoteColor.allCases) { color in
                        Toggle(color.localizedLabel, isOn: noteColorVisibilityBinding(for: color))
                    }
                }
            }
            CommandGroup(before: .windowArrangement) {
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
            CommandGroup(replacing: .windowList) {}
            TildoneHelpCommands(
                openKeyboardShortcuts: { openWindow(id: Id.keyboardShortcutsWindow) },
                openScrollGesturesHelp: { openWindow(id: Id.scrollGesturesHelpWindow) },
                openFocusFilterHelp: { openWindow(id: Id.focusFilterHelpWindow) }
            )
        }
        Window("About Tildone.window", id: Id.aboutWindow) {
            About()
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
        Window("Font Attributions", id: Id.fontAttributionsWindow) {
            NavigationStack {
                FontAttributionsView()
            }
            .frame(width: 520, height: 520)
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
        Window("Focus Filters", id: Id.focusFilterHelpWindow) {
            FocusFilterHelp()
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
        KeyboardShortcutsScene()
        ScrollGesturesHelpScene()
        Window("iCloud Sync", id: Id.syncStatusWindow) {
            MacSyncStatusView(
                bootstrapper: sharedStoreBootstrapper,
                showsResolutionOptions: $showsSyncResolutionOptions
            )
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
        Settings {
            SettingsForm(store: sharedStoreBootstrapper.store)
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

    private var foregroundNoteTitle: String? {
        foregroundNoteID.flatMap { sharedStoreBootstrapper.store?.note($0)?.title }
    }

    private func updateMenuBarCopyPresentation() {
        MenuBarController.shared.updateCopyNotePresentation(
            noteTitle: foregroundNoteTitle,
            hasActiveNote: foregroundNoteID != nil
        )
    }

    private func noteColorVisibilityBinding(for color: NoteColor) -> Binding<Bool> {
        Binding(
            get: { NoteColorDisplayFilter.selectedColors.contains(color) },
            set: { isVisible in
                var selectedColors = NoteColorDisplayFilter.selectedColors
                if isVisible {
                    selectedColors.insert(color)
                } else {
                    selectedColors.remove(color)
                }
                NoteColorDisplayFilter.setSelectedColors(selectedColors)
            }
        )
    }

    private func copyForegroundNoteContents() {
        guard let note = foregroundNoteID.flatMap({ sharedStoreBootstrapper.store?.note($0) }) else {
            return
        }
        Copier.copyNoteContents(title: note.title, tasks: note.tasks)
    }
}

private struct TildoneHelpCommands: Commands {
    let openKeyboardShortcuts: () -> Void
    let openScrollGesturesHelp: () -> Void
    let openFocusFilterHelp: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts…", action: openKeyboardShortcuts)
                .keyboardShortcut("/", modifiers: .command)
            Button("Scroll Gestures…", action: openScrollGesturesHelp)
            Divider()
            Button("How to Use Focus Filters…", action: openFocusFilterHelp)
        }
    }
}

private struct ScrollGesturesHelpScene: Scene {
    var body: some Scene {
        Window("Scroll Gestures", id: Id.scrollGesturesHelpWindow) {
            ScrollGesturesHelp()
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}

private struct KeyboardShortcutsScene: Scene {
    var body: some Scene {
        Window("Keyboard Shortcuts", id: Id.keyboardShortcutsWindow) {
            KeyboardShortcutsHelp()
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
    }
}
