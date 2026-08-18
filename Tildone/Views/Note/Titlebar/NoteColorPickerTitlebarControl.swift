//
//  NoteColorPickerTitlebarControl.swift
//  Tildone
//

import AppKit
import SwiftUI
import TildoneDomain

final class NoteColorPickerTitlebarControl: NSHostingView<NoteColorPickerTitlebarIcon> {
    private let store: MacSharedStore
    private let noteID: NoteID
    private let popover = NSPopover()

    required init(rootView: NoteColorPickerTitlebarIcon) {
        store = rootView.store
        noteID = rootView.noteID
        super.init(rootView: rootView)
        toolTip = "Note color"
        setAccessibilityLabel("Note color")
        setAccessibilityRole(.button)
        popover.behavior = .transient
    }

    convenience init(store: MacSharedStore, noteID: NoteID) {
        self.init(rootView: NoteColorPickerTitlebarIcon(store: store, noteID: noteID))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        togglePopover()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func accessibilityPerformPress() -> Bool {
        togglePopover()
        return true
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        let controller = NSViewController()
        let paletteView = NSHostingView(
            rootView: NoteColorPickerTitlebarPalette(store: store, noteID: noteID) { [weak self] in
                self?.popover.performClose(nil)
            }
            .fixedSize()
        )
        let paletteSize = NSSize(width: 126, height: 80)
        paletteView.frame = NSRect(origin: .zero, size: paletteSize)
        controller.view = paletteView
        popover.contentViewController = controller
        popover.contentSize = paletteSize

        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
