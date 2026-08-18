//
//  WindowAccessorAttachmentView.swift
//  Tildone
//

import AppKit

@MainActor
final class WindowAccessorAttachmentView: NSView {
    private let actionController = NoteWindowButtonActionController()

    var onWindowChange: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        actionController.attach(to: window)
        if let window {
            onWindowChange?(window)
        }
    }

    func update(
        onMinimize: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        actionController.update(
            window: window,
            onMinimize: onMinimize,
            onClose: onClose
        )
    }

    func reset() {
        actionController.reset(window: window)
        onWindowChange = nil
    }
}
