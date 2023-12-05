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
        .commands {
            CommandMenu("Note") {
                Button("New") {
                    NotificationCenter.default.post(name: .new, object: nil)
                }
                .keyboardShortcut(KeyEquivalent("n"), modifiers: .command)
                Button("Close (and remove)") {
                    NotificationCenter.default.post(name: .close, object: nil)
                }
                .disabled(!(foregroundList?.isDeletable ?? false))
                .keyboardShortcut(KeyEquivalent("w"), modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let new = Notification.Name("new")
    static let close = Notification.Name("close")
}
