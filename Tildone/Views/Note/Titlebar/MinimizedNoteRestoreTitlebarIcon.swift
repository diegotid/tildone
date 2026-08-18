//
//  MinimizedNoteRestoreTitlebarIcon.swift
//  Tildone
//

import SwiftUI

struct MinimizedNoteRestoreTitlebarIcon: View {
    let onRestore: () -> Void

    var body: some View {
        Image("MaximizeIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 10, height: 10)
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .offset(x: 2, y: -6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .ignoresSafeArea()
    }
}
