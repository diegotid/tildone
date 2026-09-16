import AppKit
import SwiftUI

/// Bridges note state into a separate host owned by the window's content root.
/// The scroll view can compress or scroll without moving the titlebar host.
struct MacNoteStickyTitlebar<Content: View>: NSViewRepresentable {
    let content: Content

    func makeNSView(context: Context) -> AttachmentView {
        AttachmentView(content: content)
    }

    func updateNSView(_ nsView: AttachmentView, context: Context) {
        nsView.host.rootView = content
    }

    static func dismantleNSView(_ nsView: AttachmentView, coordinator: Void) {
        nsView.host.removeFromSuperview()
    }

    final class AttachmentView: NSView {
        let host: HeaderHostingView

        init(content: Content) {
            host = HeaderHostingView(rootView: content)
            super.init(frame: .zero)
            host.sizingOptions = []
            // AppKit supplies the titlebar rectangle. Applying its safe area
            // again inside SwiftUI would push content out of that rectangle.
            host.safeAreaRegions = []
            host.identifier = NSUserInterfaceItemIdentifier("noteStickyTitlebar")
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            host.removeFromSuperview()
            // During NSWindow.contentView assignment, descendants receive this
            // callback before the window exposes its new content root.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window,
                      self.host.superview == nil else { return }
                window.setNoteStickyTitlebarView(self.host)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    final class HeaderHostingView: NSHostingView<Content> {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
