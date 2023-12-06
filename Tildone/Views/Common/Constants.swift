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
    static let contentRights: String = "Diego Rivera @ Cuatro Studio"
    static let newNoteCommand: String = "New note"
    static let discardNoteCommand: String = "Close and discard empty note"
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
}

enum Keyboard {
    static let tabKey: Int = 48
    static let arrowUp: Int = 126
    static let arrowDown: Int = 125
}

enum Timeout {
    static let noteFadeOutSeconds: Float = 20
}
