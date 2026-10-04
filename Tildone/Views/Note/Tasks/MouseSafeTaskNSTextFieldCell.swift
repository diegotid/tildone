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
        // Use AppKit's spelling marks and correction menu while editing titles,
        // tasks, and drafts. Spelling marks stay out of the saved rich text.
        editor.isContinuousSpellCheckingEnabled = TaskSpellChecking.isEnabled()
        // AppKit flushes pending text checks when focus moves. Its Data
        // Detectors scanner can wait on a lower-QoS thread during that flush.
        // Task links are already detected by our inactive text renderer.
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        return editor
    }()

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        TaskSpellChecking.apply(TaskSpellChecking.isEnabled(), to: taskFieldEditor)
        taskFieldEditor.enforceSelectionContrast()
        if let field = controlView as? MouseSafeTaskNSTextField {
            taskFieldEditor.enforceInsertionPointColor(field.cursorColor.withAlphaComponent(1))
            taskFieldEditor.onBecomeFirstResponder = { [weak field] in
                field?.onEditorFocus?()
            }
            taskFieldEditor.onPastedList = field.onPastedList
            taskFieldEditor.onPasteboardList = field.onPasteboardList
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
