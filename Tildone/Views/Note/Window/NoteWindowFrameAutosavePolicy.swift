//
//  NoteWindowFrameAutosavePolicy.swift
//  Tildone
//

import AppKit

/// Keeps the compact note presentation separate from the normal window frame
/// that AppKit persists between launches.
@MainActor
enum NoteWindowFrameAutosavePolicy {
    static let disabledName = ""

    @discardableResult
    static func suspend(for window: NSWindow) -> String {
        let autosaveName = window.frameAutosaveName
        guard !autosaveName.isEmpty else { return autosaveName }
        window.saveFrame(usingName: autosaveName)
        window.setFrameAutosaveName(disabledName)
        return autosaveName
    }

    static func resume(for window: NSWindow, using autosaveName: String) {
        guard !autosaveName.isEmpty else { return }
        window.saveFrame(usingName: autosaveName)
        window.setFrameAutosaveName(autosaveName)
    }
}
