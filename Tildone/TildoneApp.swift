//
//  TildoneApp.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import SwiftUI
import SwiftData

enum Commercial {
    case Free
    case Premium
}

@main
struct TildoneApp: App {
    @State var foregroundList: TodoList?
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
                Button(Copy.quitAppCommand) {
                    NSApplication.shared.terminate(self)
                }
                .keyboardShortcut("q")
            }
            CommandGroup(replacing: .toolbar) {
                Button(Copy.newNoteCommand) {
                    NotificationCenter.default.post(name: .new, object: nil)
                }
                .keyboardShortcut("n")
                Button(Copy.discardNoteCommand) {
                    NotificationCenter.default.post(name: .close, object: nil)
                }
                .disabled(!(foregroundList?.isDeletable ?? false))
                .keyboardShortcut("w")
            }
        }
    }
}

extension Notification.Name {
    static let new = Notification.Name("new")
    static let close = Notification.Name("close")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}
