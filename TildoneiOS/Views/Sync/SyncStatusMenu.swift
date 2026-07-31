//
//  SyncStatusMenu.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import SwiftUI
import TildoneSync

struct SyncStatusMenu: View {
    let status: SyncStatus
    let syncNow: () -> Void

    var body: some View {
        Menu {
            Text(SyncStatusPresentation.title(for: status))
            if let detail = SyncStatusPresentation.detail(for: status) { Text(detail) }
            if status.pendingMutationCount > 0 { Text("\(status.pendingMutationCount) local changes waiting") }
            if status.availability == .available {
                Divider()
                Button("Sync Now", systemImage: "arrow.triangle.2.circlepath", action: syncNow)
            }
        } label: {
            Image(systemName: SyncStatusPresentation.symbol(for: status))
                .accessibilityLabel(SyncStatusPresentation.title(for: status))
        }
    }
}
