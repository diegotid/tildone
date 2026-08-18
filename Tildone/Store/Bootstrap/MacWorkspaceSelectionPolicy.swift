//
//  MacWorkspaceSelectionPolicy.swift
//  Tildone
//

import Foundation

enum MacWorkspaceSelectionPolicy {
    /// An unadopted local workspace remains active even when the account
    /// workspace already contains data. A workspace-mode change follows only
    /// an explicit, eligible adoption confirmation.
    static func usesAccountWorkspace(
        localNeedsAdoption: Bool,
        explicitChoice: MacNoteLocationChoice?
    ) -> Bool {
        switch explicitChoice {
        case .thisMac: false
        case .iCloud: true
        case nil: !localNeedsAdoption
        }
    }

    static func canAdoptLocalWorkspace(
        localNeedsAdoption: Bool,
        accountHasContent: Bool
    ) -> Bool {
        localNeedsAdoption && !accountHasContent
    }
}
