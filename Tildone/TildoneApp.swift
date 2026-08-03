//
//  TildoneApp.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import SwiftUI
import TildoneDomain

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
                        Text("Your existing notes have not been changed. Tildone needs attention before it can open this workspace.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                } else {
                    ProgressView()
                        .onAppear { sharedStoreBootstrapper.start() }
                }
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
        Settings {
            SettingsForm()
        }
        .commandsRemoved()
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

    func install() {
        guard let button = statusItem.button else { return }
        let image = NSImage(named: "MenuBarIcon")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Tildone"
        statusItem.menu = makeMenu()
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
