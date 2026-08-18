//
//  MacSyncStatusView.swift
//  Tildone
//

import SwiftUI
import TildoneSync

struct MacSyncStatusView: View {
    @ObservedObject var bootstrapper: MacSharedStoreBootstrapper
    @Binding var showsResolutionOptions: Bool
    @State private var confirmsAdoption = false

    private var displayState: MacSyncDisplayState {
        MacSyncPresentation.state(
            status: bootstrapper.syncStatus,
            transportState: bootstrapper.transportState,
            enabledByDefault: MacSharedStoreBootstrapper.transportEnabledByDefault,
            hasUnadoptedLocalWorkspace: bootstrapper.hasUnadoptedLocalWorkspace
        )
    }

    var body: some View {
        Group {
            if showsResolutionOptions {
                MacNoteResolutionOptions(
                    bootstrapper: bootstrapper,
                    onClose: { showsResolutionOptions = false }
                )
            } else {
                statusContent
            }
        }
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .alert("Copy notes to iCloud?", isPresented: $confirmsAdoption) {
            Button("Cancel", role: .cancel) {}
            Button("Copy Notes") {
                bootstrapper.resolveNotesAfterConfirmation(.combine, requiresEmptyAccount: true)
            }
        } message: {
            Text("Tildone will copy the notes saved on this Mac to iCloud. This is available because there are no Tildone notes in iCloud. The originals will remain on this Mac, and nothing will be deleted.")
        }
    }

    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                MacSyncPresentation.title(for: displayState),
                systemImage: MacSyncPresentation.symbol(for: displayState)
            )
            .font(.title2.bold())

            Text(MacSyncPresentation.detail(
                status: bootstrapper.syncStatus,
                state: displayState,
                hasUnadoptedLocalWorkspace: bootstrapper.hasUnadoptedLocalWorkspace,
                canAdoptLocalWorkspace: bootstrapper.canAdoptLocalWorkspace,
                isUsingNotesOnMacByChoice: bootstrapper.isUsingNotesOnMacByChoice
            ))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if bootstrapper.syncStatus.pendingMutationCount > 0 {
                Text("Changes waiting to sync: \(bootstrapper.syncStatus.pendingMutationCount)")
                    .font(.callout.monospacedDigit())
                    .accessibilityLabel("Changes waiting to sync: \(bootstrapper.syncStatus.pendingMutationCount)")
            }

            if bootstrapper.isTransportActionInProgress { ProgressView() }

            if bootstrapper.resolutionActionFailed {
                Text("Tildone could not finish that change. Nothing was deleted. Please try again.")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if bootstrapper.didJustChooseNotesOnMac {
                VStack(alignment: .leading, spacing: 10) {
                    Text("These notes won’t appear on your iPhone or in iCloud. You can combine them later.")
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("OK") { bootstrapper.dismissNotesOnMacNotice() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .font(.callout)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                }
            }

            if bootstrapper.hasNotesOnMacAndICloud {
                Button(
                    bootstrapper.hasUnadoptedLocalWorkspace
                        ? "Review Options…"
                        : "Change Which Notes Tildone Uses…"
                ) {
                    showsResolutionOptions = true
                }
            }

            HStack {
                if bootstrapper.canAdoptLocalWorkspace {
                    Button("Copy Notes to iCloud…") { confirmsAdoption = true }
                }
                Spacer()
                if bootstrapper.canControlTransport {
                    if bootstrapper.transportState == .paused {
                        Button("Resume Sync") { bootstrapper.resumeTransport() }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Sync Now") { bootstrapper.syncNow() }
                        Button("Pause Sync") { bootstrapper.pauseTransport() }
                    }
                }
            }
            .disabled(bootstrapper.isTransportActionInProgress)
        }
    }
}
