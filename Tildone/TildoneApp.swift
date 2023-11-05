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
    @State private var window: NSWindow?
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([Task.self, Topic.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Note()
                .background(Color(nsColor: .noteBackground))
                .background(WindowAccessor(window: $window)).onChange(of: window) {
                    window?.level = .floating
                }
                .frame(minWidth: Layout.minNoteWidth,
                       idealWidth: Layout.defaultNoteWidth,
                       maxWidth: .infinity,
                       minHeight: Layout.minNoteHeight,
                       idealHeight: Layout.defaultNoteHeight,
                       maxHeight: .infinity,
                       alignment: .center)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
        .modelContainer(sharedModelContainer)
    }
}
