//
//  NoteWindowButtonActionController.swift
//  Tildone
//

import AppKit

@MainActor
final class NoteWindowButtonActionController: NSObject {
    private var onMinimize: () -> Void = {}
    private var onClose: () -> Void = {}

    func update(
        window: NSWindow?,
        onMinimize: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onMinimize = onMinimize
        self.onClose = onClose
        attach(to: window)
    }

    func attach(to window: NSWindow?) {
        if let minimizeButton = window?.standardWindowButton(.miniaturizeButton) {
            minimizeButton.isEnabled = true
            minimizeButton.target = self
            minimizeButton.action = #selector(minimizeButtonClicked)
        }

        if let closeButton = window?.standardWindowButton(.closeButton) {
            closeButton.target = self
            closeButton.action = #selector(closeButtonClicked)
        }
    }

    func reset(window: NSWindow?) {
        if let minimizeButton = window?.standardWindowButton(.miniaturizeButton),
           minimizeButton.target === self {
            minimizeButton.target = nil
            minimizeButton.action = nil
        }

        if let closeButton = window?.standardWindowButton(.closeButton),
           closeButton.target === self {
            closeButton.target = nil
            closeButton.action = nil
        }

        onMinimize = {}
        onClose = {}
    }

    @objc func minimizeButtonClicked() {
        onMinimize()
    }

    @objc func closeButtonClicked() {
        onClose()
    }
}
