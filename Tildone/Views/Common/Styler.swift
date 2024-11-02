//
//  Styler.swift
//  Tildone
//
//  Created by Diego Rivera on 25/4/21.
//

import SwiftUI

extension NSColor {
    static let noteBackground = #colorLiteral(red: 1, green: 0.9411764706, blue: 0.6274509804, alpha: 1)
    static let systemNoteBackground = #colorLiteral(red: 0.7331673503, green: 0.9972032905, blue: 0.7244514823, alpha: 1)
    static let checkboxBorder = #colorLiteral(red: 0.5338419676, green: 0.5067609549, blue: 0.3392150104, alpha: 1)
    static let primaryFontColor = #colorLiteral(red: 0.2549019754, green: 0.2745098174, blue: 0.3019607961, alpha: 1)
    static let checkboxOffFill = #colorLiteral(red: 0.9999960065, green: 1, blue: 1, alpha: 0.5)
}

enum Layout {
    static let checkboxSize: CGFloat = 14
    static let checkboxCheckSize: CGFloat = 8
    static let minNoteWidth: CGFloat = 180
    static let minNoteHeight: CGFloat = 240
    static let minimizedNoteWidth: CGFloat = 80
    static let minimizedNoteHeight: CGFloat = 50
    static let defaultNoteWidth: CGFloat = 250
    static let defaultNoteHeight: CGFloat = 300
    static let defaultNoteXPosition: CGFloat = 50
    static let defaultNoteYPosition: CGFloat = 90
}

extension NSWindow {
    func setNoteStyle(isSystem: Bool = false) {
        self.level = .floating
        self.makeKeyAndOrderFront(nil)
        self.titlebarAppearsTransparent = true
        self.isReleasedWhenClosed = false
        self.makeKeyAndOrderFront(nil)
        self.standardWindowButton(.closeButton)?.style()
        self.standardWindowButton(.miniaturizeButton)?.style()
        self.standardWindowButton(.zoomButton)?.style()
        self.standardWindowButton(.zoomButton)?.isEnabled = false
        self.backgroundColor = isSystem ? .systemNoteBackground : .noteBackground
        self.isOpaque = false
    }
}

extension NSButton {
    func style() {
        let frame = NSRect(x: 1, y: 2, width: 12, height: 12)
        let overlay = NSView(frame: frame)
        overlay.wantsLayer = true
        overlay.layer?.cornerRadius = frame.width / 2
        overlay.layer?.backgroundColor = NSColor.checkboxBorder.withAlphaComponent(0.2).cgColor
        self.addSubview(overlay)
    }
}

extension NSTextField {
    open override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
}

extension String {
    func capitalizingFirstLetter() -> String {
        return prefix(1).capitalized + dropFirst()
    }

    mutating func capitalizeFirstLetter() {
        self = self.capitalizingFirstLetter()
    }
}
