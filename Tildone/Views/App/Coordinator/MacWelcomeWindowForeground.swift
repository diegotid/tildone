import AppKit
import SwiftUI

/// Brings the welcome scene forward after SwiftUI has attached its window.
struct MacWelcomeWindowForeground: NSViewRepresentable {
    func makeNSView(context: Context) -> AttachmentView {
        AttachmentView()
    }

    func updateNSView(_ view: AttachmentView, context: Context) {}

    final class AttachmentView: NSView {
        private var hasPresented = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !hasPresented else { return }
            // Scene creation and launch-time note ordering must finish first.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window,
                      !self.hasPresented else { return }
                self.hasPresented = true
                NSApplication.shared.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
}
