//
//  CoordinatorWindowVisibility.swift
//  Tildone
//

import AppKit
import SwiftUI

struct CoordinatorWindowVisibility: NSViewRepresentable {
    let isVisible: Bool

    static func discardSavedFrame() {
        NSWindow.removeFrame(usingName: Id.desktopWindow)
    }

    static func disableRestoration(for window: NSWindow) {
        window.isRestorable = false
        window.setFrameAutosaveName("")
    }

    func makeNSView(context: Context) -> CoordinatorView {
        CoordinatorView(isVisible: isVisible)
    }

    func updateNSView(_ view: CoordinatorView, context: Context) {
        view.isVisible = isVisible
    }

    final class CoordinatorView: NSView {
        var isVisible: Bool {
            didSet { updateWindowVisibility() }
        }

        init(isVisible: Bool) {
            self.isVisible = isVisible
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateWindowVisibility()
        }

        private func updateWindowVisibility() {
            guard let window else { return }
            CoordinatorWindowVisibility.disableRestoration(for: window)
            // SwiftUI can order the scene front after this view attaches. Make
            // the coordinator invisible before that happens, including its chrome.
            window.alphaValue = isVisible ? 1 : 0
            window.ignoresMouseEvents = !isVisible
            if isVisible {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderOut(nil)
                DispatchQueue.main.async { [weak self, weak window] in
                    guard let self, !self.isVisible, self.window === window else { return }
                    window?.orderOut(nil)
                }
            }
        }
    }
}
