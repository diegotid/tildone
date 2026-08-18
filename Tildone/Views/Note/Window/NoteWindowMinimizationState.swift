//
//  NoteWindowMinimizationState.swift
//  Tildone
//

import AppKit

struct NoteWindowMinimizationState: Equatable {
    struct Restoration: Equatable {
        let frame: NSRect
        let autosaveName: String
    }

    private(set) var restoration: Restoration?
    private(set) var isRestoring = false

    var isMinimized: Bool { restoration != nil && !isRestoring }

    mutating func beginMinimizing(from frame: NSRect, autosaveName: String) -> Bool {
        guard restoration == nil else { return false }
        restoration = Restoration(frame: frame, autosaveName: autosaveName)
        return true
    }

    mutating func beginRestoring() -> Restoration? {
        guard let restoration, !isRestoring else { return nil }
        isRestoring = true
        return restoration
    }

    mutating func finishRestoring() {
        guard isRestoring else { return }
        restoration = nil
        isRestoring = false
    }
}
