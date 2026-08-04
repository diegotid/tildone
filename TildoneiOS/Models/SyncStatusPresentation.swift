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
        case .available where status.activity == .syncing: String(localized: "Updating iCloud")
        case .available where status.activity == .offline: String(localized: "Working offline")
        case .available where status.activity == .attentionNeeded: String(localized: "iCloud needs attention")
        case .available: String(localized: "Connected to iCloud")
        case .noAccount: String(localized: "Sign in to iCloud")
        case .restricted: String(localized: "iCloud is restricted")
        case .temporarilyUnavailable: String(localized: "iCloud is unavailable")
        case .adoptionRequired: String(localized: "Workspace needs attention")
        case .accountChanged: String(localized: "iCloud account changed")
        case .zoneResetRequired: String(localized: "Sync needs attention")
        case .incompatibleRemoteData: String(localized: "Update Tildone to continue")
        }
    }

    static func detail(for status: SyncStatus) -> String? {
        switch status.availability {
        case .disabled: String(localized: "Changes stay on this iPhone while development sync is disabled.")
        case .available where status.activity == .offline: String(localized: "You can keep editing. Changes will sync when iCloud is available.")
        case .available where status.activity == .attentionNeeded:
            switch status.issue {
            case .quotaExceeded: String(localized: "iCloud storage or service quota needs attention. Local editing is still available.")
            case .permission: String(localized: "Tildone cannot access iCloud. Check iCloud access in Settings.")
            case .malformedRemoteRecord: String(localized: "Some synchronized data could not be read. Local editing is still available.")
            case .futureSchema: String(localized: "Synced data was created by a newer version of Tildone.")
            case .network: String(localized: "The network is unavailable. Local editing is still available.")
            case .service: String(localized: "iCloud is temporarily unavailable. Local editing is still available.")
            case .accountChanged: String(localized: "The iCloud account changed. Relaunch Tildone before continuing.")
            case .zoneReset: String(localized: "The synchronized workspace needs attention before syncing can continue.")
            case .unknown, nil: String(localized: "Synchronization could not finish. Local editing is still available; try again.")
            }
        case .available: nil
        case .noAccount: String(localized: "Sign in to iCloud in Settings to use your Tildone notes here.")
        case .restricted: String(localized: "This iPhone is not permitted to use iCloud for Tildone.")
        case .temporarilyUnavailable: String(localized: "Your notes stay safe on this iPhone. Try again when iCloud is available.")
        case .adoptionRequired: String(localized: "This local workspace cannot be uploaded until its adoption policy is approved.")
        case .accountChanged: String(localized: "For privacy, notes from the previous account are no longer shown. Relaunch after changing accounts.")
        case .zoneResetRequired: String(localized: "Synchronization is paused until this workspace is reviewed.")
        case .incompatibleRemoteData: String(localized: "This workspace contains data from a newer version of Tildone.")
        }
    }

    static func symbol(for status: SyncStatus) -> String {
        switch status.availability {
        case .available where status.activity == .syncing: "arrow.triangle.2.circlepath"
        case .available: "icloud"
        case .disabled: "icloud.slash"
        case .noAccount, .restricted: "person.crop.circle.badge.exclamationmark"
        case .temporarilyUnavailable: "wifi.exclamationmark"
        case .adoptionRequired, .accountChanged, .zoneResetRequired, .incompatibleRemoteData: "exclamationmark.triangle"
        }
    }
}
