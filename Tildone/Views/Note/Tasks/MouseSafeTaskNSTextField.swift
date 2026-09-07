//
//  MouseSafeTaskNSTextField.swift
//  Tildone
//

import AppKit
import TildoneDomain

final class MouseSafeTaskNSTextField: NSTextField {
    var taskID: TaskID?
    var placesCaretAtStartOnFocus = false
    var cursorColor = NSColor.textColor
    var onEditorFocus: (() -> Void)?
    var hasPendingFocusRequest = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.applyPendingFocusRequest() }
    }

    func applyPendingFocusRequest() {
        guard hasPendingFocusRequest, let window else { return }
        hasPendingFocusRequest = false
        window.makeFirstResponder(self)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
    }

    override func layout() {
        super.layout()
        updateTruncationTooltip()
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder, placesCaretAtStartOnFocus {
            (currentEditor() as? NSTextView)?.selectedRange = NSRange(location: 0, length: 0)
        }
        return becameFirstResponder
    }

    func updateTruncationTooltip() {
        guard !stringValue.isEmpty else {
            toolTip = nil
            return
        }
        let availableWidth = cell?.titleRect(forBounds: bounds).width ?? bounds.width
        toolTip = attributedStringValue.size().width > availableWidth ? stringValue : nil
    }
}
