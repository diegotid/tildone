//
//  MinimizedNoteRestoreTitlebarIcon.swift
//  Tildone
//

import SwiftUI

struct MinimizedNoteRestoreTitlebarIcon: View {
    let onRestore: () -> Void

    var body: some View {
        Image(systemName: "app.shadow")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            .scaleEffect(x: -1, y: 1)
            .offset(y: -3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .ignoresSafeArea()
    }
}
