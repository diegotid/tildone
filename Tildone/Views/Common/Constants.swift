//
//  Constants.swift
//  Tildone
//
//  Created by Diego Rivera on 25/4/21.
//

import SwiftUI

enum Id {
    static let appIcon: String = "AppIcon"
    static let bottomAnchor: String = "bottom"
    static let aboutWindow: String = "about-tildone"
    static let updateWindow: String = "update-tildone"
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
