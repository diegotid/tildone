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
        
        let contentView = Note()
        
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
}

/// Avoid focus ring on every text field all over the app
extension NSTextField {
    
    open override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
}
