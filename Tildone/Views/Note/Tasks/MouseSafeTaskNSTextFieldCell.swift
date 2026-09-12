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
        guard verticallyCentersContent, cellFrame.width > 0 else {
            super.drawInterior(withFrame: cellFrame, in: controlView)
            return
        }
        super.drawInterior(withFrame: verticallyCenteredDrawingFrame(for: cellFrame), in: controlView)
    }

    func verticallyCenteredDrawingFrame(for cellFrame: NSRect) -> NSRect {
        var drawingFrame = cellFrame
        // NSTextFieldCell's renderer and NSAttributedString.boundingRect can
        // choose different wrap points for custom fonts. Measure through the
        // cell itself so the centered frame includes every rendered line.
        let contentHeight = ceil(cellSize(forBounds: cellFrame).height)
        let drawingHeight = min(cellFrame.height, contentHeight + 2)
        guard drawingHeight < cellFrame.height else { return drawingFrame }
        drawingFrame.origin.y += (cellFrame.height - drawingHeight) / 2
        drawingFrame.size.height = drawingHeight
        return drawingFrame
    }
}
