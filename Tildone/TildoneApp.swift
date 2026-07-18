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
        WindowGroup {
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
        Settings {
            SettingsForm()
        }
        .commandsRemoved()
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
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}
