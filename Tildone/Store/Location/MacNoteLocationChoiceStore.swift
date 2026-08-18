//
//  MacNoteLocationChoiceStore.swift
//  Tildone
//

import Foundation

struct MacNoteLocationChoiceStore {
    private static let keyPrefix = "noteLocationChoice."

    let defaults: UserDefaults

    func choice(for workspaceID: UUID) -> MacNoteLocationChoice? {
        guard let rawValue = defaults.string(
            forKey: Self.keyPrefix + workspaceID.uuidString.lowercased()
        ) else { return nil }
        return MacNoteLocationChoice(rawValue: rawValue)
    }

    func set(_ choice: MacNoteLocationChoice, for workspaceID: UUID) {
        defaults.set(choice.rawValue, forKey: Self.keyPrefix + workspaceID.uuidString.lowercased())
    }
}
