//
//  MinimizedNoteRestoreTitlebarControl.swift
//  Tildone
//

import AppKit
import SwiftUI

final class MinimizedNoteRestoreTitlebarControl: NSHostingView<MinimizedNoteRestoreTitlebarIcon> {
    private let onRestore: () -> Void

    required init(rootView: MinimizedNoteRestoreTitlebarIcon) {
        onRestore = rootView.onRestore
        super.init(rootView: rootView)
        toolTip = "Restore note"
        setAccessibilityElement(true)
        setAccessibilityLabel("Restore note")
        setAccessibilityRole(.button)
    }

    convenience init(onRestore: @escaping () -> Void) {
        self.init(rootView: MinimizedNoteRestoreTitlebarIcon(onRestore: onRestore))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onRestore()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func accessibilityPerformPress() -> Bool {
        onRestore()
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
