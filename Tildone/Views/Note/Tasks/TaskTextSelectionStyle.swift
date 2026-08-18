//
//  TaskTextSelectionStyle.swift
//  Tildone
//

import AppKit

enum TaskTextSelectionStyle {
    static func apply(to editor: NSTextView) {
        editor.selectedTextAttributes = withHighContrast(editor.selectedTextAttributes)
    }

    static func withHighContrast(
        _ attributes: [NSAttributedString.Key: Any]
    ) -> [NSAttributedString.Key: Any] {
        var attributes = attributes
        attributes[.foregroundColor] = NSColor.black
        attributes[.backgroundColor] = NSColor.selectedTextBackgroundColor
        return attributes
    }
}
