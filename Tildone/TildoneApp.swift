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
                Button(Copy.commandAbout) {
                    openWindow(id: Id.aboutWindow)
                }
                Button(Copy.commandCheckUpdates) {
                    openWindow(id: Id.updateWindow)
                }
                Divider()
                SettingsLink {
                    Text(Copy.commandSettings)
                }
                .keyboardShortcut(",")
                Divider()
                Button(Copy.commandQuitApp) {
                    NSApplication.shared.terminate(self)
                }
                .keyboardShortcut("q")
            }
            CommandGroup(replacing: .newItem) {
                Button(Copy.commandNewNote) {
                    NotificationCenter.default.post(name: .new, object: nil)
                }
                .keyboardShortcut("n")
                Button(foregroundList != nil ? Copy.commandDiscardNote : Copy.commandCloseWindow) {
                    NotificationCenter.default.post(name: .close, object: nil)
                }
                .disabled(isCloseCommandDisabled)
                .keyboardShortcut("w")
            }
            CommandGroup(replacing: .textEditing) {
                Menu(Copy.commandCopy) {
                    Button(Copy.commandCopyTask) {
                        NotificationCenter.default.post(name: .copy, object: nil)
                    }
                    .keyboardShortcut("c")
                    Button(Copy.commandCopyList) {
                        foregroundList?.copy()
                    }
                    .keyboardShortcut("c", modifiers: [.shift, .command])
                }
            }
            CommandGroup(replacing: .toolbar) {
                Button(Copy.commandArrange) {
                    NotificationCenter.default.post(name: .arrange, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.shift, .command])
            }
        }
        Window(Copy.commandAbout, id: Id.aboutWindow) {
            About()
        }
        .windowResizability(.contentSize)
        .commandsRemoved()
        Window(Copy.commandCheckUpdates, id: Id.updateWindow) {
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
    static let arrange = Notification.Name("arrange")
    static let visibility = Notification.Name("visibility")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}
