//
//  MouseSafeTaskNSTextFieldCell.swift
//  Tildone
//

import AppKit

final class MouseSafeTaskNSTextFieldCell: NSTextFieldCell {
    private lazy var taskFieldEditor: MouseSafeTaskFieldEditor = {
        let editor = MouseSafeTaskFieldEditor()
        editor.isFieldEditor = true
        editor.isRichText = true
        editor.importsGraphics = false
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        taskFieldEditor.enforceSelectionContrast()
        if let field = controlView as? MouseSafeTaskNSTextField {
            taskFieldEditor.enforceInsertionPointColor(field.cursorColor.withAlphaComponent(1))
            taskFieldEditor.onBecomeFirstResponder = { [weak field] in
                field?.onEditorFocus?()
            }
        }
        return taskFieldEditor
    }
}
