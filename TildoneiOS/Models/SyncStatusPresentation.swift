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
        case .disabled: "Sync is disabled"
        case .available where status.activity == .syncing: "Updating iCloud"
        case .available where status.activity == .offline: "Working offline"
        case .available where status.activity == .attentionNeeded: "iCloud needs attention"
        case .available: "iCloud is ready"
        case .noAccount: "Sign in to iCloud"
        case .restricted: "iCloud is restricted"
        case .temporarilyUnavailable: "iCloud is unavailable"
        case .adoptionRequired: "Workspace needs attention"
        case .accountChanged: "iCloud account changed"
        case .zoneResetRequired: "Sync needs attention"
        case .incompatibleRemoteData: "Update Tildone to continue"
        }
    }

    static func detail(for status: SyncStatus) -> String? {
        switch status.availability {
        case .disabled: "Changes stay on this iPhone while development sync is disabled."
        case .available where status.activity == .offline: "You can keep editing. Changes will sync when iCloud is available."
        case .available where status.activity == .attentionNeeded:
            switch status.issue {
            case .quotaExceeded: "iCloud storage or service quota needs attention. Local editing is still available."
            case .permission: "Tildone cannot access iCloud. Check iCloud access in Settings."
            case .malformedRemoteRecord: "Some synchronized data could not be read. Local editing is still available."
            case .futureSchema: "Synced data was created by a newer version of Tildone."
            case .network: "The network is unavailable. Local editing is still available."
            case .service: "iCloud is temporarily unavailable. Local editing is still available."
            case .accountChanged: "The iCloud account changed. Relaunch Tildone before continuing."
            case .zoneReset: "The synchronized workspace needs attention before syncing can continue."
            case .unknown, nil: "Synchronization could not finish. Local editing is still available; try again."
            }
        case .available: nil
        case .noAccount: "Sign in to iCloud in Settings to use your Tildone notes here."
        case .restricted: "This iPhone is not permitted to use iCloud for Tildone."
        case .temporarilyUnavailable: "Your notes stay safe on this iPhone. Try again when iCloud is available."
        case .adoptionRequired: "This local workspace cannot be uploaded until its adoption policy is approved."
        case .accountChanged: "For privacy, notes from the previous account are no longer shown. Relaunch after changing accounts."
        case .zoneResetRequired: "Synchronization is paused until this workspace is reviewed."
        case .incompatibleRemoteData: "This workspace contains data from a newer version of Tildone."
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
