//
//  Constants.swift
//  Tildone
//
//  Created by Diego Rivera on 25/4/21.
//

import SwiftUI
import TildoneDomain

enum Id {
    static let appIcon: String = "AppIcon"
    static let bottomAnchor: String = "bottom"
    static let desktopWindow: String = "tildone-desktop-coordinator"
    static let aboutWindow: String = "about-tildone"
    static let focusFilterHelpWindow: String = "focus-filter-help"
    static let syncStatusWindow: String = "sync-status"
    static let updateWindow: String = "update-tildone"
}

enum Frame {
    static let aboutWindowWidth: CGFloat = 240
    static let aboutWindowHeight: CGFloat = 260
    static let aboutIconSize: CGFloat = 100
}

enum Keyboard {
    static let tabKey: Int = 48
    static let returnKey: Int = 36
    static let arrowUp: Int = 126
    static let arrowDown: Int = 125
    static let delete: Int = 117
    static let backSpace: Int = 51
}

enum Timeout {
    static let noteFadeOutSeconds: TimeInterval = 20
}

enum AppAppearance {
    static let showDockIconStorageKey = "showDockIcon"
    static let moveCheckedTasksToEndStorageKey = "moveCheckedTasksToEnd"

    /// A new installation starts as a menu-bar app. Existing installations
    /// retain the Dock icon users already expect until they opt out.
    static func prepareDockIconPreference(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: showDockIconStorageKey) == nil else { return }
        guard isExistingInstallation(defaults: defaults) else { return }
        defaults.set(true, forKey: showDockIconStorageKey)
    }

    private static func isExistingInstallation(defaults: UserDefaults) -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let domain = defaults.persistentDomain(forName: bundleIdentifier) else {
            return false
        }

        let legacyPreferenceKeys = [
            FontSize.storageKey,
            TaskLineTruncation.storageKey,
            ArrangementCorner.storageKey,
            ArrangementAlignment.storageKey,
            ArrangementSpacing.cornerStorageKey,
            ArrangementSpacing.sideStorageKey,
            NoteColor.storageKey,
            NoteWindowBackground.opacityStorageKey,
            UpdateChecker.Local.knownVersionFlag
        ]

        return domain.keys.contains { key in
            legacyPreferenceKeys.contains(key) || key.hasPrefix("NSWindow Frame ")
        }
    }
}

/// Installation-local restoration data for the optional completed-task ordering.
/// It deliberately stays out of the shared task model and iCloud sync payload.
enum CompletedTaskOrderPreference {
    private static let originalOrderTokensStorageKey = "completedTaskOriginalOrderTokens"

    static func originalOrderToken(for taskID: TaskID) -> OrderToken? {
        guard let rawValue = originalOrderTokens()[taskID.stringValue] else { return nil }
        return try? OrderToken(rawValue: rawValue)
    }

    static func recordOriginalOrderToken(_ orderToken: OrderToken, for taskID: TaskID) {
        var tokens = originalOrderTokens()
        guard tokens[taskID.stringValue] == nil else { return }
        tokens[taskID.stringValue] = orderToken.rawValue
        UserDefaults.standard.set(tokens, forKey: originalOrderTokensStorageKey)
    }

    static func removeOriginalOrderToken(for taskID: TaskID) {
        var tokens = originalOrderTokens()
        tokens.removeValue(forKey: taskID.stringValue)
        UserDefaults.standard.set(tokens, forKey: originalOrderTokensStorageKey)
    }

    static func clearOriginalOrderTokens() {
        UserDefaults.standard.removeObject(forKey: originalOrderTokensStorageKey)
    }

    static func snapshot(for taskIDs: Set<TaskID>) -> [TaskID: OrderToken] {
        Dictionary(uniqueKeysWithValues: taskIDs.compactMap { taskID in
            originalOrderToken(for: taskID).map { (taskID, $0) }
        })
    }

    static func restore(_ snapshot: [TaskID: OrderToken], for taskIDs: Set<TaskID>) {
        for taskID in taskIDs { removeOriginalOrderToken(for: taskID) }
        for (taskID, orderToken) in snapshot {
            recordOriginalOrderToken(orderToken, for: taskID)
        }
    }

    private static func originalOrderTokens() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: originalOrderTokensStorageKey) as? [String: String] ?? [:]
    }
}
