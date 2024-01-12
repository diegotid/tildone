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
    
    var appIconImage: Image? = {
        guard let image = NSImage(named: Id.appIcon) else {
            return nil
        }
        return Image(nsImage: image)
    }()
    
    var appVersionLabel: Text? = {
        guard let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return nil
        }
        return Text("Version \(version)")
    }()
    
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
                Button(foregroundList != nil ? Copy.commandDiscardNote : "Close about window") {
                    NotificationCenter.default.post(name: .close, object: nil)
                }
                .disabled(isCloseCommandDisabled)
                .keyboardShortcut("w")
            }
            CommandGroup(replacing: .toolbar) {
                Button(Copy.commandArrange) {
                    NotificationCenter.default.post(name: .arrange, object: nil)
                }
                .keyboardShortcut("a", modifiers: [.shift, .command])
            }
        }
        Window(Copy.commandAbout, id: Id.aboutWindow) {
            VStack {
                if appIconImage != nil {
                    appIconImage!
                        .resizable()
                        .frame(maxWidth: Frame.aboutIconSize, maxHeight: Frame.aboutIconSize)
                }
                Text(Copy.appName)
                    .font(.title)
                    .bold()
                    .padding(.bottom, 10)
                if appVersionLabel != nil {
                    appVersionLabel
                        .font(.subheadline)
                        .padding(.bottom, 10)
                }
                Text(Copy.contentRights)
                if let website = URL(string: Copy.websiteLink) {
                    Link(Copy.websiteName, destination: website)
                }
            }
            .padding()
            .frame(width: Frame.aboutWindowWidth, height: Frame.aboutWindowHeight)
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
    static let arrange = Notification.Name("arrange")
    static let visibility = Notification.Name("visibility")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}
