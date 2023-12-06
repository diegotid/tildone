//
//  Constants.swift
//  Tildone
//
//  Created by Diego Rivera on 25/4/21.
//

import SwiftUI
import Foundation

enum Copy {
    static let quitAppCommand: String = "Quit Tildene"
    static let newNoteCommand: String = "New note"
    static let discardNoteCommand: String = "Close and discard empty note"
    static let newTaskPlaceholder: String = "New task"
    static let listTopicPlaceholder: String = "Topic"
    static let noteFadingOutDisplay: String = "Fading out..."
    static let noteDone: String = "Done!"
    static let cancel: String = "Cancel"
}

enum ViewLayout {
    static let bottomAnchor: String = "bottom"
}

enum Keyboard {
    static let tabKey: Int = 48
    static let arrowUp: Int = 126
    static let arrowDown: Int = 125
}

enum Timeout {
    static let noteFadeOutSeconds: Float = 20
}
