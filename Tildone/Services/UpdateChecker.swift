//
//  UpdateChecker.swift
//  Tildone
//
//  Created by Diego Rivera on 12/1/24.
//

import Foundation
import StoreKit

struct UpdateChecker {
    
    /// Update notices are installation-local presentation, not shared user
    /// content. The Stage 7 shared repository deliberately has no system-note
    /// model, so this check never creates a legacy `TodoList`.
    static func hasNewRelease() async -> Bool {
        if UserDefaults.standard.string(forKey: Local.pendingVersionFlag) != nil {
            return true
        }
        do {
            let app = try await AppTransaction.shared
            if case .verified(let installed) = app {
                let known: String? = UserDefaults.standard.string(forKey: Local.knownVersionFlag)
                let isKnown: Bool = installed.appVersion == known
                let isUpdated: Bool = installed.appVersion != installed.originalAppVersion
                if isUpdated && !isKnown {
                    UserDefaults.standard.setValue(installed.appVersion, forKey: Local.knownVersionFlag)
                    UserDefaults.standard.setValue(installed.appVersion, forKey: Local.pendingVersionFlag)
                    return true
                }
            }
            return false
        } catch {
            debugPrint(error.localizedDescription)
            return false
        }
    }

    static var pendingVersion: String? {
        UserDefaults.standard.string(forKey: Local.pendingVersionFlag)
    }

    static func dismissPendingReleaseNote() {
        UserDefaults.standard.removeObject(forKey: Local.pendingVersionFlag)
    }
}

extension UpdateChecker {
    enum Local {
        static let knownVersionFlag: String = "knownAppVersion"
        static let pendingVersionFlag: String = "pendingReleaseNoteVersion"
    }
    enum Remote {
        static let releaseNotesURL = URL(string: "http://cuatro.studio/tildone/release")!
    }
}
