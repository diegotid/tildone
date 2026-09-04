//
//  MinimizedNoteRestoreTitlebarIcon.swift
//  Tildone
//

import SwiftUI

struct MinimizedNoteRestoreTitlebarIcon: View {
    let onRestore: () -> Void
    let foreground: Color

    var body: some View {
        Image("MaximizeIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 10, height: 10)
            .foregroundStyle(foreground)
            .offset(x: 2, y: -6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .ignoresSafeArea()
    }
}
