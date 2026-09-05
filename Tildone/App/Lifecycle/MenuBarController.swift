//
//  MenuBarController.swift
//  Tildone
//

import AppKit
import Foundation
import TildoneDomain
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
        base.accessibilityDescription = accessibilityDescription
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
        image.accessibilityDescription = accessibilityDescription
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
        menu.minimumWidth = NoteColorFilterMenuView.preferredMenuWidth
        menu.addItem(item(String(localized: "About Tildone"), action: #selector(openAbout), symbolName: "info.circle"))
        menu.addItem(.separator())

        menu.addItem(item(String(localized: "New Note"), action: #selector(createNote), symbolName: "square.and.pencil"))

        let minimizeAll = item(String(localized: "Minimize All"), action: #selector(minimizeAll), keyEquivalent: "m", symbolName: "minus.square")
        minimizeAll.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(minimizeAll)

        let bringAllUp = item(String(localized: "Bring All Up"), action: #selector(bringAllUp), keyEquivalent: "u")
        bringAllUp.image = menuAssetImage(named: "MaximizeIcon")
        bringAllUp.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(bringAllUp)

        let lineUpNotes = item(String(localized: "Line Up Notes"), action: #selector(lineUpNotes), symbolName: "rectangle.3.group")
        menu.addItem(lineUpNotes)

        menu.addItem(.separator())
        let colorFilterHeader = NSMenuItem(title: String(localized: "Filter notes by color"), action: nil, keyEquivalent: "")
        colorFilterHeader.isEnabled = false
        menu.addItem(colorFilterHeader)
        let colorFilter = NSMenuItem()
        colorFilter.view = NoteColorFilterMenuView()
        menu.addItem(colorFilter)

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

    private func menuAssetImage(named name: String) -> NSImage? {
        guard let image = NSImage(named: NSImage.Name(name)) else {
            return nil
        }
        let menuImage = NSImage(size: NSSize(width: 14.5, height: 14.5), flipped: false) { rect in
            image.draw(in: rect.insetBy(dx: 3.4, dy: 3.2))
            return true
        }
        menuImage.isTemplate = true
        return menuImage
    }

    @objc private func createNote() { sendToActiveApp(.new) }
    @objc private func minimizeAll() { sendToActiveApp(.minimizeAll) }
    @objc private func bringAllUp() { sendToActiveApp(.bringAllUp) }
    @objc private func lineUpNotes() { sendToActiveApp(.arrange) }
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

private final class NoteColorFilterMenuView: NSView {
    static let preferredMenuWidth: CGFloat = 244

    private let discSize: CGFloat = 21.6
    private let spacing: CGFloat = 7
    private var hoveredIndex: Int?
    private var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.preferredMenuWidth, height: 38))
        autoresizingMask = [.width]
        toolTip = String(localized: "Choose which note colors are displayed")
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Self.preferredMenuWidth, height: 38)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let superview {
            frame.size.width = superview.bounds.width
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let selected = NoteColorDisplayFilter.selectedColors
        for (index, color) in NoteColor.allCases.enumerated() {
            let rect = discRect(at: index)
            let isSelected = selected.contains(color)
            let colorDisc = rect.insetBy(dx: 3.6, dy: 3.6)
            color.nsColor.setFill()
            NSBezierPath(ovalIn: colorDisc).fill()
            if isSelected {
                NSColor.controlAccentColor.setStroke()
                let path = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
                path.lineWidth = 2.875
                path.stroke()
            }
            if hoveredIndex == index {
                drawHoverSymbol(in: colorDisc, isSelected: isSelected)
            }
        }

    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let index = NoteColor.allCases.indices.first(where: { discRect(at: $0).insetBy(dx: -4, dy: -4).contains(point) }) {
            NoteColorDisplayFilter.toggle(NoteColor.allCases[index])
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoveredIndex(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoveredIndex(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard hoveredIndex != nil else { return }
        hoveredIndex = nil
        needsDisplay = true
    }

    override func resetCursorRects() {
        for index in NoteColor.allCases.indices { addCursorRect(discRect(at: index), cursor: .pointingHand) }
    }

    private func discRect(at index: Int) -> NSRect {
        let groupWidth = CGFloat(NoteColor.allCases.count) * discSize
            + CGFloat(NoteColor.allCases.count - 1) * spacing
        return NSRect(
            x: bounds.midX - groupWidth / 2 + CGFloat(index) * (discSize + spacing),
            y: bounds.midY - discSize / 2,
            width: discSize,
            height: discSize
        )
    }

    private func drawHoverSymbol(in rect: NSRect, isSelected: Bool) {
        NSColor.labelColor.setStroke()
        let inset = rect.width * 0.28
        let symbolRect = rect.insetBy(dx: inset, dy: inset)
        let symbol = NSBezierPath()
        symbol.lineWidth = 1.8
        symbol.lineCapStyle = .round
        symbol.move(to: NSPoint(x: symbolRect.minX, y: symbolRect.midY))
        symbol.line(to: NSPoint(x: symbolRect.maxX, y: symbolRect.midY))
        if !isSelected {
            symbol.move(to: NSPoint(x: symbolRect.midX, y: symbolRect.minY))
            symbol.line(to: NSPoint(x: symbolRect.midX, y: symbolRect.maxY))
        }
        symbol.stroke()
    }

    private func updateHoveredIndex(at point: NSPoint) {
        let newHoveredIndex = NoteColor.allCases.indices.first {
            discRect(at: $0).insetBy(dx: -4, dy: -4).contains(point)
        }
        guard hoveredIndex != newHoveredIndex else { return }
        hoveredIndex = newHoveredIndex
        needsDisplay = true
    }
}
