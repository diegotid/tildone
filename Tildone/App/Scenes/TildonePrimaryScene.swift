//
//  TildonePrimaryScene.swift
//  Tildone
//

import AppKit
import SwiftUI

/// The primary scene hosts the one process-wide coordinator that owns every
/// manually managed note window.
struct TildonePrimaryScene<Content: View>: Scene {
    private let isVisible: Bool
    private let content: Content

    init(isVisible: Bool = false, @ViewBuilder content: () -> Content) {
        self.isVisible = isVisible
        self.content = content()
    }

    var body: some Scene {
        Window("Tildone", id: Id.desktopWindow) {
            content
                .background(CoordinatorWindowVisibility(isVisible: isVisible))
        }
    }
}
