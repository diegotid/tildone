//
//  MacLocalAdoptionStateStore.swift
//  Tildone
//

import Foundation

struct MacLocalAdoptionStateStore {
    private static let keyPrefix = "localWorkspaceAdoptionFingerprint."

    let defaults: UserDefaults

    func fingerprint(for workspaceID: UUID) -> String? {
        defaults.string(forKey: Self.keyPrefix + workspaceID.uuidString.lowercased())
    }

    func setFingerprint(_ fingerprint: String, for workspaceID: UUID) {
        defaults.set(fingerprint, forKey: Self.keyPrefix + workspaceID.uuidString.lowercased())
    }
}
