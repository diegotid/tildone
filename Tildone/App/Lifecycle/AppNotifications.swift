//
//  AppNotifications.swift
//  Tildone
//

import Foundation

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
    static let noteWindowOpacityChanged = Notification.Name("noteWindowOpacityChanged")
    static let noteWindowClickThroughCommandChanged = Notification.Name("noteWindowClickThroughCommandChanged")
}
