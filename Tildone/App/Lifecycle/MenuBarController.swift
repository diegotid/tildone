//
//  MenuBarController.swift
//  Tildone
//

import AppKit
import Foundation
import TildoneSync

/// AppKit exposes the status button, which lets a new empty menu-bar-only
/// installation present its menu once without relying on private APIs.
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var hasPresentedInitialMenu = false
    private var syncHeaderItem: NSMenuItem?
    private var syncPendingItem: NSMenuItem?
    private var syncActionItem: NSMenuItem?

    func install() {
        guard let button = statusItem.button else { return }
        button.image = Self.menuBarImage(for: .active, accessibilityDescription: "Tildone")
        button.toolTip = "Tildone"
        button.setAccessibilityLabel("Tildone")
        button.setAccessibilityHelp(String(localized: "Open Tildone and review iCloud sync status"))
        statusItem.menu = makeMenu()
    }

    func updateSyncPresentation(
        status: SyncStatus,
        transportState: SyncTransportState,
        enabledByDefault: Bool,
        hasResolvedAccountWorkspace: Bool,
        isUsingAccountWorkspace: Bool,
        hasUnadoptedLocalWorkspace: Bool
    ) {
        let state = MacSyncPresentation.state(
            status: status,
            transportState: transportState,
            enabledByDefault: enabledByDefault,
            hasUnadoptedLocalWorkspace: hasUnadoptedLocalWorkspace
        )
        let title = MacSyncPresentation.title(for: state)
        syncHeaderItem?.title = title
        syncHeaderItem?.image = NSImage(
            systemSymbolName: MacSyncPresentation.symbol(for: state),
            accessibilityDescription: title
        )

        syncPendingItem?.isHidden = status.pendingMutationCount == 0
        syncPendingItem?.title = String(
            localized: "Changes waiting to sync: \(status.pendingMutationCount)"
        )

        let canControl = enabledByDefault && hasResolvedAccountWorkspace && isUsingAccountWorkspace
        syncActionItem?.isHidden = !canControl
        if transportState == .paused {
            syncActionItem?.title = String(localized: "Resume Sync")
            syncActionItem?.action = #selector(resumeSync)
            syncActionItem?.image = menuImage(named: "play.circle")
        } else {
            syncActionItem?.title = String(localized: "Pause Sync")
            syncActionItem?.action = #selector(pauseSync)
            syncActionItem?.image = menuImage(named: "pause.circle")
        }

        guard let button = statusItem.button else { return }
        button.image = Self.menuBarImage(for: state, accessibilityDescription: title)
        button.toolTip = title
        button.setAccessibilityValue(title)
    }

    static func menuBarImage(
        for state: MacSyncDisplayState,
        accessibilityDescription: String
    ) -> NSImage? {
        guard let source = NSImage(named: "MenuBarIcon"),
              let base = source.copy() as? NSImage else {
            return nil
        }
        base.isTemplate = true
        base.size = NSSize(width: 16, height: 16)
        guard let badgeName = MacSyncPresentation.menuBarBadgeSymbol(for: state),
              let badge = NSImage(
                systemSymbolName: badgeName,
                accessibilityDescription: accessibilityDescription
              )?.withSymbolConfiguration(.init(pointSize: 8, weight: .bold)) else {
            return base
        }

        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            base.draw(in: NSRect(x: 1, y: 1, width: 16, height: 16))
            badge.draw(in: NSRect(x: 10, y: 10, width: 8, height: 8))
            return true
        }
        image.isTemplate = true
        return image
    }

    func presentMenuForEmptyMenuBarOnlyWorkspace() {
        guard !hasPresentedInitialMenu,
              !UserDefaults.standard.bool(forKey: AppAppearance.showDockIconStorageKey) else {
            return
        }
        hasPresentedInitialMenu = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(String(localized: "About Tildone"), action: #selector(openAbout), symbolName: "info.circle"))
        menu.addItem(.separator())

        menu.addItem(item(String(localized: "New Note"), action: #selector(createNote), keyEquivalent: "n", symbolName: "square.and.pencil"))

        let minimizeAll = item(String(localized: "Minimize All"), action: #selector(minimizeAll), keyEquivalent: "m", symbolName: "minus.square")
        minimizeAll.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(minimizeAll)

        let bringAllUp = item(String(localized: "Bring All Up"), action: #selector(bringAllUp), keyEquivalent: "u", symbolName: "app.shadow")
        bringAllUp.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(bringAllUp)

        menu.addItem(.separator())
        let syncHeader = NSMenuItem(title: String(localized: "iCloud sync is disabled"), action: nil, keyEquivalent: "")
        syncHeader.isEnabled = false
        syncHeaderItem = syncHeader
        menu.addItem(syncHeader)
        let syncPending = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        syncPending.isEnabled = false
        syncPending.isHidden = true
        syncPendingItem = syncPending
        menu.addItem(syncPending)
        let syncAction = item(String(localized: "Pause Sync"), action: #selector(pauseSync), symbolName: "pause.circle")
        syncAction.isHidden = true
        syncActionItem = syncAction
        menu.addItem(syncAction)
        menu.addItem(item(String(localized: "Sync Status…"), action: #selector(openSyncStatus), symbolName: "arrow.trianglehead.2.clockwise.rotate.90.icloud"))

        menu.addItem(.separator())
        let settings = item(String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",", symbolName: "gearshape")
        settings.keyEquivalentModifierMask = .command
        menu.addItem(settings)
        menu.addItem(item(String(localized: "How to Use Focus Filters…"), action: #selector(openFocusFilterHelp), symbolName: "moon"))

        menu.addItem(.separator())
        let quit = item(String(localized: "Quit Tildone"), action: #selector(quit), keyEquivalent: "q", symbolName: "power")
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)
        return menu
    }

    private func item(
        _ title: String,
        action: Selector,
        keyEquivalent: String = "",
        symbolName: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.image = symbolName.flatMap(menuImage(named:))
        return item
    }

    private func menuImage(named symbolName: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    @objc private func createNote() { sendToActiveApp(.new) }
    @objc private func minimizeAll() { sendToActiveApp(.minimizeAll) }
    @objc private func bringAllUp() { sendToActiveApp(.bringAllUp) }
    @objc private func openSettings() { sendToActiveApp(.openSettings) }
    @objc private func openAbout() { sendToActiveApp(.openAbout) }
    @objc private func openFocusFilterHelp() { sendToActiveApp(.openFocusFilterHelp) }
    @objc private func openSyncStatus() { sendToActiveApp(.openSyncStatus) }
    @objc private func pauseSync() { sendToActiveApp(.pauseSync) }
    @objc private func resumeSync() { sendToActiveApp(.resumeSync) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    /// A status-item click doesn't activate its app. Defer SwiftUI scene work
    /// until AppKit has closed the tracking menu and Tildone is foregrounded.
    private func sendToActiveApp(_ name: Notification.Name) {
        NSApplication.shared.activate()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: name, object: nil)
        }
    }
}
