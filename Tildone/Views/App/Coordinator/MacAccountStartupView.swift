import AppKit
import SwiftUI

struct MacAccountStartupView: View {
    let state: MacSharedStoreBootstrapper.StartupAccountState
    let onRetry: () -> Void
    var onQuit: () -> Void = { NSApplication.shared.terminate(nil) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if state == .unresolved {
                Text("Couldn’t check your iCloud account")
                    .font(.headline)
                Text("Your notes remain saved. Please check your connection and try again.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Checking your iCloud account…")
                    Text("Checking your iCloud account…").font(.headline)
                }
                Text("Apple’s account check is taking longer than usual. Your notes remain saved while Tildone waits.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Quit Tildone", action: onQuit)
                Spacer()
                Button("Try Again", action: onRetry)
                    .disabled(state == .checking)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
