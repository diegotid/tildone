//
//  NoteWindowManualPosition.swift
//  Tildone
//

import AppKit
import TildoneDomain

enum NoteWindowManualPosition {
    private static let originStorageKeyPrefix = "noteUserDraggedPosition."
    private static let wheelPositionStorageKeyPrefix = "noteCornerWheelPosition."

    static func storedOrigin(
        for noteID: NoteID,
        defaults: UserDefaults = .standard
    ) -> NSPoint? {
        guard let values = defaults.array(forKey: originStorageKey(for: noteID)) as? [NSNumber],
              values.count == 2 else {
            return nil
        }
        let x = CGFloat(values[0].doubleValue)
        let y = CGFloat(values[1].doubleValue)
        guard x.isFinite, y.isFinite else { return nil }
        return NSPoint(x: x, y: y)
    }

    static func ensureStoredOrigin(
        _ origin: NSPoint,
        for noteID: NoteID,
        defaults: UserDefaults = .standard
    ) {
        guard storedOrigin(for: noteID, defaults: defaults) == nil else { return }
        setOrigin(origin, for: noteID, defaults: defaults)
    }

    static func recordDraggedOrigin(
        _ origin: NSPoint,
        for noteID: NoteID,
        defaults: UserDefaults = .standard
    ) {
        setOrigin(origin, for: noteID, defaults: defaults)
        setIsWheelPosition(false, for: noteID, defaults: defaults)
    }

    static func shouldRecordDrag(pressedMouseButtons: Int = NSEvent.pressedMouseButtons) -> Bool {
        pressedMouseButtons & 1 == 1
    }

    static func isWheelPosition(
        for noteID: NoteID,
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: wheelPositionStorageKey(for: noteID))
    }

    static func setIsWheelPosition(
        _ isWheelPosition: Bool,
        for noteID: NoteID,
        defaults: UserDefaults = .standard
    ) {
        let key = wheelPositionStorageKey(for: noteID)
        guard defaults.object(forKey: key) as? Bool != isWheelPosition else { return }
        defaults.set(isWheelPosition, forKey: key)
    }

    private static func setOrigin(
        _ origin: NSPoint,
        for noteID: NoteID,
        defaults: UserDefaults
    ) {
        guard origin.x.isFinite, origin.y.isFinite else { return }
        defaults.set([Double(origin.x), Double(origin.y)], forKey: originStorageKey(for: noteID))
    }

    private static func originStorageKey(for noteID: NoteID) -> String {
        originStorageKeyPrefix + noteID.stringValue
    }

    private static func wheelPositionStorageKey(for noteID: NoteID) -> String {
        wheelPositionStorageKeyPrefix + noteID.stringValue
    }
}
