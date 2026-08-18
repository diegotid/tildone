//
//  MacNoteSyncTitlebarIcon.swift
//  Tildone
//

import SwiftUI

struct MacNoteSyncTitlebarIcon: View {
    let state: MacNoteSyncIndicatorState

    var body: some View {
        Image(systemName: state.symbolName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(state == .attentionNeeded
                ? Color(nsColor: .systemOrange)
                : Color(nsColor: .secondaryLabelColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .ignoresSafeArea()
    }
}
