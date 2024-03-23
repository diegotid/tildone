//
//  TildoneApp.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import SwiftUI
import SwiftData

@main
struct TildoneApp: App {
    @State var foregroundList: TodoList?
    @Environment(\.openWindow) var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Todo.self, TodoList.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var isCloseCommandDisabled: Bool {
        if let list = self.foregroundList {
            !list.isDeletable
        } else {
            false
        }
    }

    var body: some Scene {
        WindowGroup {
            Desktop(foregroundList: $foregroundList)
        }
        .environment(\.license, .free)
        .modelContainer(sharedModelContainer)
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
        .commandsRemoved()
        .commandsReplaced {
            CommandGroup(replacing: .appInfo) {
                Button("About Tildone") {
                    openWindow(id: Id.aboutWindow)
                }
                Button("Check for Updates...") {
                    openWindow(id: Id.updateWindow)
                }
                Divider()
                SettingsLink {
                    Text("Settings...")
                }
                .keyboardShortcut(",")
                Divider()
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
                Button(foregroundList != nil ? "Discard Empty Note" : "Close window") {
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
                        foregroundList?.copy()
                    }
                    .keyboardShortcut("c", modifiers: [.shift, .command])
                }
                Button("Paste") {
                    NotificationCenter.default.post(name: .paste, object: nil)
                }
                .keyboardShortcut("v")
            }
            CommandGroup(replacing: .toolbar) {
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
        Window("Check for Updates.window", id: Id.updateWindow) {
            Updates()
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
    static let visibility = Notification.Name("visibility")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}
