//
//  TildoneApp.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import AppKit
import SwiftUI
import SwiftData

@main
struct TildoneApp: App {
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
            Desktop()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
        .modelContainer(sharedModelContainer)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainWindow = NSApp.windows[0]
        mainWindow.delegate = self
    }
        
    @objc func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.hide(nil)
        
        return false
    }
}
