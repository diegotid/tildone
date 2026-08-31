//
//  AppDelegate.swift
//  Tildone
//

import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    private var isCoordinatorWindowVisible = false
    private var coordinatorWindowObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        CoordinatorWindowVisibility.discardSavedFrame()
        NSWindow.allowsAutomaticWindowTabbing = false
        AppAppearance.prepareDockIconPreference()
        applyDockIconVisibility()
        GlobalApplicationHotKey.lineUp.start()
        GlobalApplicationHotKey.newNote.start()
        MenuBarController.shared.install()
        coordinatorWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.hideCoordinatorWindowIfNeeded(notification)
        }
    }

    deinit {
        if let coordinatorWindowObserver {
            NotificationCenter.default.removeObserver(coordinatorWindowObserver)
        }
    }

    func setCoordinatorWindowVisible(_ isVisible: Bool) {
        isCoordinatorWindowVisible = isVisible
        guard isVisible else { return }
        coordinatorWindow()?.makeKeyAndOrderFront(nil)
    }

    func applyDockIconVisibility() {
        let shouldShowDockIcon = UserDefaults.standard.bool(forKey: AppAppearance.showDockIconStorageKey)
        NSApplication.shared.setActivationPolicy(shouldShowDockIcon ? .regular : .accessory)
    }

    private func hideCoordinatorWindowIfNeeded(_ notification: Notification) {
        guard !isCoordinatorWindowVisible,
              let window = notification.object as? NSWindow,
              isCoordinatorWindow(window) else {
            return
        }
        window.orderOut(nil)
    }

    private func coordinatorWindow() -> NSWindow? {
        NSApplication.shared.windows.first(where: isCoordinatorWindow)
    }

    private func isCoordinatorWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == Id.desktopWindow || window.title == "Tildone"
    }
}
