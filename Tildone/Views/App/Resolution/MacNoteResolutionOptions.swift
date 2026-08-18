//
//  MacNoteResolutionOptions.swift
//  Tildone
//

import SwiftUI

struct MacNoteResolutionOptions: View {
    @ObservedObject var bootstrapper: MacSharedStoreBootstrapper
    let onClose: () -> Void
    @State private var pendingAction: MacNoteResolutionAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let pendingAction {
                confirmation(for: pendingAction)
            } else {
                Text("Choose which notes Tildone should use")
                    .font(.title2.bold())
                Text("Your notes on this Mac and in iCloud will remain saved whichever option you choose.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                resolutionOption(
                    title: String(localized: "Combine Notes — Recommended"),
                    detail: String(localized: "Add the notes from this Mac to the notes in iCloud, then use the combined set."),
                    action: .combine
                )
                resolutionOption(
                    title: String(localized: "Use iCloud Notes"),
                    detail: String(localized: "Show the notes already in iCloud. The notes on this Mac stay saved."),
                    action: .useICloud
                )
                resolutionOption(
                    title: String(localized: "Use Notes on This Mac"),
                    detail: String(localized: "Keep showing the notes saved on this Mac. The notes in iCloud stay unchanged."),
                    action: .useThisMac
                )

                HStack {
                    Spacer()
                    Button("Decide Later", action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }

    private func resolutionOption(
        title: String,
        detail: String,
        action: MacNoteResolutionAction
    ) -> some View {
        Button {
            pendingAction = action
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(MacNoteResolutionOptionButtonStyle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func confirmation(for action: MacNoteResolutionAction) -> some View {
        Text(confirmationTitle(for: action))
            .font(.title2.bold())
        Text(confirmationMessage(for: action))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        HStack {
            Spacer()
            Button("Cancel") { pendingAction = nil }
                .keyboardShortcut(.cancelAction)
            Button(confirmationButtonTitle(for: action)) {
                bootstrapper.resolveNotesAfterConfirmation(action)
                pendingAction = nil
                onClose()
            }
            .keyboardShortcut(.defaultAction)
        }
        .disabled(bootstrapper.isTransportActionInProgress)
    }

    private func confirmationTitle(for action: MacNoteResolutionAction) -> String {
        switch action {
        case .combine: String(localized: "Combine notes from this Mac and iCloud?")
        case .useThisMac: String(localized: "Use the notes on this Mac?")
        case .useICloud: String(localized: "Use the notes in iCloud?")
        }
    }

    private func confirmationButtonTitle(for action: MacNoteResolutionAction) -> String {
        switch action {
        case .combine: String(localized: "Combine Notes")
        case .useThisMac: String(localized: "Use This Mac")
        case .useICloud: String(localized: "Use iCloud")
        }
    }

    private func confirmationMessage(for action: MacNoteResolutionAction) -> String {
        switch action {
        case .combine:
            String(localized: "Tildone will add the notes from this Mac to iCloud. If the same note exists in both places, Tildone will combine it the same way it handles edits made on two devices. The notes saved on this Mac will remain available.")
        case .useThisMac:
            String(localized: "Tildone will keep showing the notes saved on this Mac. The notes in iCloud will not be changed, and you can switch later.")
        case .useICloud:
            String(localized: "Tildone will show the notes in iCloud. The notes saved on this Mac will not be changed, and you can switch back later.")
        }
    }
}
