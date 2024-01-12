//
//  Constants.swift
//  Tildone
//
//  Created by Diego Rivera on 25/4/21.
//

import SwiftUI

enum Copy {
    static let appName: String = "Tildone"
    static let commandAbout: String = "About \(Copy.appName)"
    static let commandArrange: String = "Arrange Notes"
    static let commandSettings: String = "Settings..."
    static let commandQuitApp: String = "Quit Tildene"
    static let commandNewNote: String = "New Note"
    static let commandDiscardNote: String = "Discard Empty Note"
    static let settingsSectionGeneral: String = "General"
    static let settingsSectionAppearance: String = "Appearance"
    static let settingsSectionAppearanceSingle: String = "Single line with ellipsis"
    static let settingsSectionAppearanceMultiple: String = "Multiline"
    static let settingsArrangementDescription: String = "How to arrange your notes\n(when menu command used or ⇧⌘A pressed):"
    static let settingsArrangementCornerLabel: String = "Corner of the screen"
    static let settingsArrangementCornerTopLeft: String = "Top left corner"
    static let settingsArrangementCornerTopRight: String = "Top right corner"
    static let settingsArrangementCornerBottomRight: String = "Bottom right corner"
    static let settingsArrangementCornerBottomLeft: String = "Bottom left corner"
    static let settingsArrangementAlignmentHorizontal: String = "Horizontal"
    static let settingsArrangementAlignmentVertical: String = "Vertical"
    static let settingsArrangementSpacingMinimum: String = "Minimum spacing"
    static let settingsArrangementSpacingMedium: String = "Medium spacing"
    static let settingsArrangementSpacingMaximum: String = "Maximum spacing"
    static let settingsArrangementMarginMinimum: String = "Minimum margin"
    static let settingsArrangementMarginMedium: String = "Medium margin"
    static let settingsArrangementMarginMaximum: String = "Maximum margin"
    static let settingsOpenOnLoginLabel: String = "Open at login"
    static let contentRights: String = "© 2023 Diego Rivera"
    static let websiteLink: String = "http://cuatro.studio"
    static let websiteName: String = "cuatro.studio"
    static let taskPlaceholder: String = "Task"
    static let desktopPlaceholder: String = "Desktop"
    static let newTaskPlaceholder: String = "New task"
    static let listTopicPlaceholder: String = "Topic"
    static let noteFadingOutDisplay: String = "Fading out..."
    static let noteDone: String = "Done!"
    static let cancel: String = "Cancel"
}

enum Id {
    static let appIcon: String = "AppIcon"
    static let aboutWindow: String = "about-tildone"
    static let bottomAnchor: String = "bottom"
}

enum Frame {
    static let aboutWindowWidth: CGFloat = 240
    static let aboutWindowHeight: CGFloat = 260
    static let aboutIconSize: CGFloat = 100
    static let menuBarHeight: Int = 20
}

enum Keyboard {
    static let tabKey: Int = 48
    static let arrowUp: Int = 126
    static let arrowDown: Int = 125
}

enum Timeout {
    static let noteFadeOutSeconds: Float = 20
}
