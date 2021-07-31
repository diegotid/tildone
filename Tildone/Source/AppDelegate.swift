//
//  AppDelegate.swift
//  Tildone
//
//  Created by Diego on 24/4/21.
//

import Cocoa
import SwiftUI

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        let context = persistentContainer.viewContext
        let contentView = Note().environment(\.managedObjectContext, context)
        
        let windowLayout = NSRect(x: 0,
                                  y: 0,
                                  width: Layout.defaultNoteWidth,
                                  height: Layout.defaultNoteHeight)
        window = NSWindow(contentRect: windowLayout,
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .borderless],
                          backing: .buffered,
                          defer: false)
        window.level = .floating
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName(Literals.mainWindowName)
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        window.backgroundColor = .noteBackground
    }

    // MARK: - Core Data stack

    lazy var persistentContainer: NSPersistentCloudKitContainer = {

        let container = NSPersistentCloudKitContainer(name: "Tildone")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            
            if let error = error {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                fatalError("Unresolved error \(error)")
            }
        })
        
        return container
    }()
}

// MARK: - Overall settings

/// Avoid focus ring on every text field all over the app
extension NSTextField {
    
    open override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
}
