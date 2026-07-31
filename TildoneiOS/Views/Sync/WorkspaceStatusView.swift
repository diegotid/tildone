//
//  WorkspaceStatusView.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import SwiftUI
import TildoneSync

struct WorkspaceStatusView: View {
    let status: SyncStatus
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                SyncStatusPresentation.title(for: status),
                systemImage: SyncStatusPresentation.symbol(for: status)
            )
        } description: {
            Text(SyncStatusPresentation.detail(for: status) ?? "Tildone cannot open a workspace right now.")
        } actions: {
            if status.availability == .temporarilyUnavailable {
                Button("Try Again", action: retry)
            }
        }
        .padding()
    }
}
