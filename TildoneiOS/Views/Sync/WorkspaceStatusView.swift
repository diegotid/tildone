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
        GeometryReader { geometry in
            ScrollView {
                ContentUnavailableView {
                    Label(
                        SyncStatusPresentation.title(for: status),
                        systemImage: SyncStatusPresentation.symbol(for: status)
                    )
                } description: {
                    Text(SyncStatusPresentation.detail(for: status) ?? String(localized: "Tildone cannot open your notes right now."))
                } actions: {
                    if status.availability == .temporarilyUnavailable {
                        Button("Try Again", action: retry)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }
}
