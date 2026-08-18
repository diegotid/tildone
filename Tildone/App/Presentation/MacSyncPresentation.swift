//
//  MacSyncPresentation.swift
//  Tildone
//

import Foundation
import TildoneSync

enum MacSyncPresentation {
    static func state(
        status: SyncStatus,
        transportState: SyncTransportState,
        enabledByDefault: Bool,
        hasUnadoptedLocalWorkspace: Bool
    ) -> MacSyncDisplayState {
        if hasUnadoptedLocalWorkspace || status.activity == .attentionNeeded || [
            .noAccount,
            .restricted,
            .temporarilyUnavailable,
            .adoptionRequired,
            .accountChanged,
            .zoneResetRequired,
            .incompatibleRemoteData
        ].contains(status.availability) {
            return .attentionNeeded
        }
        guard enabledByDefault, status.availability != .disabled else { return .disabled }
        return transportState == .paused || status.activity == .paused ? .paused : .active
    }

    static func title(for state: MacSyncDisplayState) -> String {
        switch state {
        case .active: String(localized: "iCloud sync is active")
        case .paused: String(localized: "iCloud sync is paused")
        case .attentionNeeded: String(localized: "iCloud sync needs attention")
        case .disabled: String(localized: "iCloud sync is disabled")
        }
    }

    static func symbol(for state: MacSyncDisplayState) -> String {
        switch state {
        case .active: "icloud"
        case .paused: "pause.circle"
        case .attentionNeeded: "exclamationmark.triangle.fill"
        case .disabled: "icloud.slash"
        }
    }

    static func menuBarBadgeSymbol(for state: MacSyncDisplayState) -> String? {
        state == .attentionNeeded ? "exclamationmark.circle.fill" : nil
    }

    static func detail(
        status: SyncStatus,
        state: MacSyncDisplayState,
        hasUnadoptedLocalWorkspace: Bool,
        canAdoptLocalWorkspace: Bool,
        isUsingNotesOnMacByChoice: Bool
    ) -> String {
        if hasUnadoptedLocalWorkspace {
            return canAdoptLocalWorkspace
                ? String(localized: "Your notes remain on this Mac. You can choose to copy them to iCloud. Nothing will be deleted.")
                : String(localized: "Your notes remain safe on this Mac. There are also notes in iCloud, so Tildone will not combine or replace either set automatically.")
        }
        if isUsingNotesOnMacByChoice {
            return String(localized: "Tildone is using the notes saved on this Mac. Notes in iCloud are unchanged, and you can switch at any time.")
        }
        switch status.availability {
        case .zoneResetRequired:
            return String(localized: "Tildone’s storage in iCloud is missing or was reset. Sync has stopped, but your notes and unsent changes are safe. Tildone will not rebuild or upload them again without your permission.")
        case .incompatibleRemoteData:
            return String(localized: "The notes in iCloud were saved by a newer version of Tildone. You can keep editing on this Mac, and Tildone will not replace the iCloud notes.")
        case .accountChanged:
            return String(localized: "The iCloud account changed. Tildone stopped syncing the previous account’s notes to keep them separate.")
        case .noAccount:
            return String(localized: "Sign in to iCloud with the account you want to use, then reopen Tildone. Notes saved on this Mac will not be uploaded automatically.")
        case .restricted:
            return String(localized: "Tildone cannot use iCloud with this account. You can keep editing on this Mac.")
        case .temporarilyUnavailable:
            return String(localized: "iCloud is temporarily unavailable. You can keep editing, and your unsent changes remain safe.")
        default:
            break
        }
        if status.activity == .attentionNeeded {
            return String(localized: "Sync could not finish. You can keep editing, and your unsent changes remain safe.")
        }
        switch state {
        case .active:
            return String(localized: "Tildone sends and receives your changes through iCloud.")
        case .paused:
            return String(localized: "You can keep editing. Nothing will be sent to or downloaded from iCloud until you resume.")
        case .attentionNeeded:
            return String(localized: "Tildone needs your help with iCloud. It has not deleted or replaced any notes.")
        case .disabled:
            return String(localized: "iCloud sync is turned off in this version of Tildone. Your notes stay where they are.")
        }
    }
}
