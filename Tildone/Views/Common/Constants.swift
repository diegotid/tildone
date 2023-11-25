//
//  Constants.swift
//  Tildone
//
//  Created by Diego Rivera on 25/4/21.
//

import SwiftUI
import Foundation

enum Copy {
    static let newTaskPlaceholder: String = "New task"
    static let listTopicPlaceholder: String = "Topic"
    static let noteFadingOutDisplay: String = "Fading out..."
    static let cancel: String = "Cancel"
}

enum Keyboard {
    static let tabKey: Int = 48
    static let backspaceKey = KeyEquivalent("\u{7F}")
}

enum Timeout {
    static let noteFadeOutSeconds: Float = 20
}
