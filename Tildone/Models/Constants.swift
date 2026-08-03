//
//  Constants.swift
//  Tildone
//
//  Created by Diego Rivera on 25/4/21.
//

import SwiftUI

enum Id {
    static let appIcon: String = "AppIcon"
    static let bottomAnchor: String = "bottom"
    static let desktopWindow: String = "tildone-desktop-coordinator"
    static let aboutWindow: String = "about-tildone"
    static let updateWindow: String = "update-tildone"
}

enum Frame {
    static let aboutWindowWidth: CGFloat = 240
    static let aboutWindowHeight: CGFloat = 260
    static let aboutIconSize: CGFloat = 100
    static let menuBarHeight: Int = 20
}

enum Keyboard {
    static let tabKey: Int = 48
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
