//
//  WindowAccessor.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    let note: Note
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> WindowAccessorAttachmentView {
        let view = WindowAccessorAttachmentView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: WindowAccessorAttachmentView, context: Context) {
        configure(nsView)
    }

    static func dismantleNSView(
        _ nsView: WindowAccessorAttachmentView,
        coordinator: Void
    ) {
        nsView.reset()
    }

    private func configure(_ view: WindowAccessorAttachmentView) {
        let windowBinding = $window
        view.onWindowChange = { attachedWindow in
            guard windowBinding.wrappedValue !== attachedWindow else { return }
            DispatchQueue.main.async {
                windowBinding.wrappedValue = attachedWindow
            }
        }
        view.update(
            onMinimize: { note.handleMinimize() },
            onClose: { note.handleClose() }
        )
    }
}
