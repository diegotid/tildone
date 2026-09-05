//
//  AppNotifications.swift
//  Tildone
//

import Foundation
import TildoneDomain

extension Notification.Name {
    static let new = Notification.Name("new")
    static let close = Notification.Name("close")
    static let copy = Notification.Name("copy")
    static let paste = Notification.Name("paste")
    static let clean = Notification.Name("clean")
    static let arrange = Notification.Name("arrange")
    static let arrangeMinimized = Notification.Name("arrangeMinimized")
    static let minimizeAll = Notification.Name("minimizeAll")
    static let bringAllUp = Notification.Name("bringAllUp")
    static let visibility = Notification.Name("visibility")
    static let openSettings = Notification.Name("openSettings")
    static let openAbout = Notification.Name("openAbout")
    static let openFocusFilterHelp = Notification.Name("openFocusFilterHelp")
    static let openSyncStatus = Notification.Name("openSyncStatus")
    static let openSyncResolutionOptions = Notification.Name("openSyncResolutionOptions")
    static let pauseSync = Notification.Name("pauseSync")
    static let resumeSync = Notification.Name("resumeSync")
    static let syncNow = Notification.Name("syncNow")
    static let updateCompletedTaskOrdering = Notification.Name("updateCompletedTaskOrdering")
    static let updateCompletedTaskRetention = Notification.Name("updateCompletedTaskRetention")
    static let noteWindowOpacityChanged = Notification.Name("noteWindowOpacityChanged")
    static let noteWindowClickThroughCommandChanged = Notification.Name("noteWindowClickThroughCommandChanged")
    static let noteColorFilterChanged = Notification.Name("noteColorFilterChanged")
}

enum NoteColorDisplayFilter {
    private static let storageKey = "displayedNoteColors"

    static var selectedColors: Set<NoteColor> {
        let defaults = UserDefaults.standard
        guard let stored = defaults.array(forKey: storageKey) as? [String] else {
            return Set(NoteColor.allCases)
        }
        return Set(stored.compactMap(NoteColor.init(rawValue:)))
    }

    static func toggle(_ color: NoteColor) {
        var colors = selectedColors
        if colors.contains(color) {
            colors.remove(color)
        } else {
            colors.insert(color)
        }
        setSelectedColors(colors)
    }

    static func setSelectedColors(_ colors: Set<NoteColor>) {
        UserDefaults.standard.set(colors.map(\.rawValue), forKey: storageKey)
        NotificationCenter.default.post(name: .noteColorFilterChanged, object: colors)
    }

}
