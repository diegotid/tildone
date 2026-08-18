//
//  MouseSafeTaskNSTextFieldCell.swift
//  Tildone
//

import AppKit

final class MouseSafeTaskNSTextFieldCell: NSTextFieldCell {
    private lazy var taskFieldEditor: MouseSafeTaskFieldEditor = {
        let editor = MouseSafeTaskFieldEditor()
        editor.isFieldEditor = true
        editor.isRichText = false
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        taskFieldEditor.enforceSelectionContrast()
        if let textColor = (controlView as? NSTextField)?.textColor {
            taskFieldEditor.enforceInsertionPointColor(textColor)
        }
        return taskFieldEditor
    }
}
