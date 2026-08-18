//
//  MouseSafeTaskNSTextField.swift
//  Tildone
//

import AppKit
import TildoneDomain

final class MouseSafeTaskNSTextField: NSTextField {
    var taskID: TaskID?
    var placesCaretAtStartOnFocus = false

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder, placesCaretAtStartOnFocus {
            (currentEditor() as? NSTextView)?.selectedRange = NSRange(location: 0, length: 0)
        }
        return becameFirstResponder
    }
}
