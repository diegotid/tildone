//
//  MacNoteSyncTitlebarControl.swift
//  Tildone
//

import AppKit
import SwiftUI

final class MacNoteSyncTitlebarControl: NSHostingView<MacNoteSyncTitlebarIcon> {
    private let state: MacNoteSyncIndicatorState

    required init(rootView: MacNoteSyncTitlebarIcon) {
        state = rootView.state
        super.init(rootView: rootView)
        toolTip = state.status
        setAccessibilityElement(true)
        setAccessibilityLabel(state.status)
        setAccessibilityHelp(state.accessibilityHelp)
        setAccessibilityRole(.button)
    }

    convenience init(state: MacNoteSyncIndicatorState) {
        self.init(rootView: MacNoteSyncTitlebarIcon(state: state))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        openOptions()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func accessibilityPerformPress() -> Bool {
        openOptions()
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    private func openOptions() {
        guard let actionNotification = state.actionNotification else { return }
        NotificationCenter.default.post(name: actionNotification, object: nil)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
