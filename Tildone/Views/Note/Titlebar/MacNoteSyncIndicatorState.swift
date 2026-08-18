//
//  MacNoteSyncIndicatorState.swift
//  Tildone
//

import Foundation

enum MacNoteSyncIndicatorState: Equatable {
    case hidden
    case onlyOnThisMac
    case attentionNeeded

    static func resolve(
        isUsingNotesOnMacByChoice: Bool,
        syncNeedsAttention: Bool
    ) -> MacNoteSyncIndicatorState {
        if syncNeedsAttention { return .attentionNeeded }
        return isUsingNotesOnMacByChoice ? .onlyOnThisMac : .hidden
    }

    var symbolName: String {
        switch self {
        case .hidden: "icloud"
        case .onlyOnThisMac: "icloud.slash"
        case .attentionNeeded: "exclamationmark.icloud"
        }
    }

    var status: String {
        switch self {
        case .hidden: ""
        case .onlyOnThisMac:
            String(localized: "Only on this Mac — not syncing with iPhone or iCloud.")
        case .attentionNeeded:
            String(localized: "Not syncing with iCloud right now. Your notes are safe on this Mac.")
        }
    }

    var accessibilityHelp: String {
        switch self {
        case .hidden: ""
        case .onlyOnThisMac: String(localized: "Review Options…")
        case .attentionNeeded: String(localized: "Sync Status…")
        }
    }

    var actionNotification: Notification.Name? {
        switch self {
        case .hidden: nil
        case .onlyOnThisMac: .openSyncResolutionOptions
        case .attentionNeeded: .openSyncStatus
        }
    }
}
