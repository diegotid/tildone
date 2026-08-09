//
//  SyncStatusPresentation.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import TildoneSync

enum SyncStatusPresentation {
    static func title(for status: SyncStatus) -> String {
        switch status.availability {
        case .disabled: String(localized: "Sync is disabled")
        case .available where status.activity == .paused: String(localized: "Sync is paused")
        case .available where status.activity == .syncing: String(localized: "Updating iCloud")
        case .available where status.activity == .offline: String(localized: "Working offline")
        case .available where status.activity == .attentionNeeded: String(localized: "iCloud needs attention")
        case .available: String(localized: "Connected to iCloud")
        case .noAccount: String(localized: "Sign in to iCloud")
        case .restricted: String(localized: "iCloud is restricted")
        case .temporarilyUnavailable: String(localized: "iCloud is unavailable")
        case .adoptionRequired: String(localized: "Your notes need attention")
        case .accountChanged: String(localized: "iCloud account changed")
        case .zoneResetRequired: String(localized: "Sync needs attention")
        case .incompatibleRemoteData: String(localized: "Update Tildone to continue")
        }
    }

    static func detail(for status: SyncStatus) -> String? {
        switch status.availability {
        case .disabled: String(localized: "Changes stay on this iPhone while iCloud sync is turned off.")
        case .available where status.activity == .paused: String(localized: "You can keep editing. Nothing will be sent to or downloaded from iCloud until you resume.")
        case .available where status.activity == .offline: String(localized: "You can keep editing. Changes will sync when iCloud is available.")
        case .available where status.activity == .attentionNeeded:
            switch status.issue {
            case .quotaExceeded: String(localized: "Your iCloud storage needs attention. You can keep editing.")
            case .permission: String(localized: "Tildone cannot access iCloud. Check iCloud access in Settings.")
            case .malformedRemoteRecord: String(localized: "Some notes from iCloud could not be read. You can keep editing.")
            case .futureSchema: String(localized: "The notes in iCloud were saved by a newer version of Tildone.")
            case .network: String(localized: "The network is unavailable. Local editing is still available.")
            case .service: String(localized: "iCloud is temporarily unavailable. Local editing is still available.")
            case .accountChanged: String(localized: "The iCloud account changed. Relaunch Tildone before continuing.")
            case .zoneReset: String(localized: "Tildone’s storage in iCloud needs attention before syncing can continue.")
            case .unknown, nil: String(localized: "Sync could not finish. You can keep editing; try again.")
            }
        case .available: nil
        case .noAccount: String(localized: "Sign in to iCloud in Settings to use your Tildone notes here.")
        case .restricted: String(localized: "This iPhone is not permitted to use iCloud for Tildone.")
        case .temporarilyUnavailable: String(localized: "Your notes stay safe on this iPhone. Try again when iCloud is available.")
        case .adoptionRequired: String(localized: "Notes saved only on this iPhone will not be uploaded automatically.")
        case .accountChanged: String(localized: "For privacy, notes from the previous account are no longer shown. Relaunch after changing accounts.")
        case .zoneResetRequired: String(localized: "Sync is paused because Tildone’s storage in iCloud needs attention. Your notes remain safe on this iPhone.")
        case .incompatibleRemoteData: String(localized: "The notes in iCloud were saved by a newer version of Tildone.")
        }
    }

    static func symbol(for status: SyncStatus) -> String {
        switch status.availability {
        case .available where status.activity == .syncing: "arrow.triangle.2.circlepath"
        case .available where status.activity == .paused: "pause.circle"
        case .available: "icloud"
        case .disabled: "icloud.slash"
        case .noAccount, .restricted: "person.crop.circle.badge.exclamationmark"
        case .temporarilyUnavailable: "wifi.exclamationmark"
        case .adoptionRequired, .accountChanged, .zoneResetRequired, .incompatibleRemoteData: "exclamationmark.triangle"
        }
    }
}
