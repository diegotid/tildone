//
//  Constants.swift
//  Tildone
//
//  Created by Diego Rivera on 25/4/21.
//

import SwiftUI
import Foundation

enum Copy {
    static let appName: String = "Tildone"
    static let aboutCommand: String = "About Tildone"
    static let quitAppCommand: String = "Quit Tildene"
    static let contentRights: String = "© 2023 Diego Rivera"
    static let websiteLink: String = "http://cuatro.studio"
    static let websiteName: String = "cuatro.studio"
    static let newNoteCommand: String = "New note"
    static let discardNoteCommand: String = "Discard empty note"
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
    static let arrangedNotesMargin: Int = 40
    static let arrangedNotesSpacing: Int = 20
}

enum Keyboard {
    static let tabKey: Int = 48
    static let arrowUp: Int = 126
    static let arrowDown: Int = 125
}

enum Timeout {
    static let noteFadeOutSeconds: Float = 20
}
