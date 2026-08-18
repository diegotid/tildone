//
//  CoordinatorWindowVisibility.swift
//  Tildone
//

import AppKit
import SwiftUI

struct CoordinatorWindowVisibility: NSViewRepresentable {
    let isVisible: Bool

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
            if isVisible {
                window.makeKeyAndOrderFront(nil)
            } else {
                window.orderOut(nil)
                DispatchQueue.main.async { [weak window] in
                    window?.orderOut(nil)
                }
            }
        }
    }
}
