//
//  NoteWindowMinimizationState.swift
//  Tildone
//

import AppKit
import TildoneDomain

struct NoteWindowMinimizationState: Equatable {
    struct Restoration: Equatable {
        let frame: NSRect
        let autosaveName: String
    }

    private(set) var restoration: Restoration?
    private(set) var isRestoring = false

    var isMinimized: Bool { restoration != nil && !isRestoring }

    // Window presentation is installation-local and never part of note sync.
    static func savedIsMinimized(for noteID: NoteID, defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: "noteIsMinimized.\(noteID.stringValue)")
    }

    static func saveMinimized(
        _ minimized: Bool, for noteID: NoteID,
        compactFrame: NSRect? = nil, defaults: UserDefaults = .standard
    ) {
        let key = "noteIsMinimized.\(noteID.stringValue)"
        if minimized {
            defaults.set(true, forKey: key)
            if let compactFrame { saveCompactFrame(compactFrame, for: noteID, defaults: defaults) }
        } else {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: "noteCompactFrame.\(noteID.stringValue)")
        }
    }

    static func saveCompactFrame(_ frame: NSRect, for noteID: NoteID, defaults: UserDefaults = .standard) {
        guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
              frame.width > 0, frame.height > 0 else { return }
        defaults.set(
            [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)],
            forKey: "noteCompactFrame.\(noteID.stringValue)"
        )
    }

    static func savedCompactFrame(for noteID: NoteID, defaults: UserDefaults = .standard) -> NSRect? {
        guard let values = defaults.array(forKey: "noteCompactFrame.\(noteID.stringValue)") as? [NSNumber],
              values.count == 4 else { return nil }
        let components = values.map { CGFloat($0.doubleValue) }
        guard components.allSatisfy(\.isFinite), components[2] > 0, components[3] > 0 else { return nil }
        return NSRect(x: components[0], y: components[1], width: components[2], height: components[3])
    }

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
