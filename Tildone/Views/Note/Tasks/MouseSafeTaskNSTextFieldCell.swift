//
//  MouseSafeTaskNSTextFieldCell.swift
//  Tildone
//

import AppKit

final class MouseSafeTaskNSTextFieldCell: NSTextFieldCell {
    var verticallyCentersContent = false

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

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        var drawingFrame = cellFrame
        guard verticallyCentersContent, drawingFrame.width > 0 else {
            super.drawInterior(withFrame: cellFrame, in: controlView)
            return
        }
        let textHeight = attributedStringValue.boundingRect(
            with: NSSize(width: drawingFrame.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height
        if textHeight < drawingFrame.height {
            drawingFrame.origin.y += (drawingFrame.height - textHeight) / 2
            drawingFrame.size.height = ceil(textHeight) + 2
        }
        super.drawInterior(withFrame: drawingFrame, in: controlView)
    }
}
