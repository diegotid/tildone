//
//  FocusFilterHelp.swift
//  Tildone
//

import AppKit
import SwiftUI

struct FocusFilterHelp: View {
    private let focusSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Focus-Settings.extension"
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Focus Filters", systemImage: "moon.stars.fill")
                .font(.title2.bold())
            Text("Focus Filters can automatically blur task text or let notes stay behind other windows while a Focus is active.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                FocusFilterHelpStep(number: 1, text: "Open System Settings and choose Focus.")
                FocusFilterHelpStep(number: 2, text: "Select the Focus you want to configure.")
                FocusFilterHelpStep(number: 3, text: "Under Focus Filters, click Add Filter, then choose Tildone.")
                FocusFilterHelpStep(number: 4, text: "Choose how Tildone should behave and click Add.")
            }
            Text("To change or remove the filter later, return to the same Focus settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let focusSettingsURL {
                HStack {
                    Spacer()
                    Button("Open Focus Settings") { NSWorkspace.shared.open(focusSettingsURL) }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
