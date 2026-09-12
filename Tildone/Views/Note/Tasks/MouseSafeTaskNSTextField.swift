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
    var wrapsContent = false
    var verticallyCentersContent = false {
        didSet {
            if oldValue != verticallyCentersContent {
                invalidateIntrinsicContentSize()
            }
        }
    }
    private var pendingFocusAttempts = 0
    private var isVerifyingFocus = false
    private var lastLayoutWidth: CGFloat = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.applyPendingFocusRequest() }
    }

    func applyPendingFocusRequest() {
        guard hasPendingFocusRequest, !isVerifyingFocus, let window else { return }
        if window.makeFirstResponder(self) {
            isVerifyingFocus = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak window] in
                guard let self else { return }
                self.isVerifyingFocus = false
                if let window,
                   window.firstResponder === self.currentEditor() {
                    self.hasPendingFocusRequest = false
                    self.pendingFocusAttempts = 0
                } else {
                    self.retryPendingFocusRequest()
                }
            }
        } else if pendingFocusAttempts < 8 {
            retryPendingFocusRequest()
        } else {
            hasPendingFocusRequest = false
            pendingFocusAttempts = 0
        }
    }

    private func retryPendingFocusRequest() {
        guard pendingFocusAttempts < 8 else {
            hasPendingFocusRequest = false
            pendingFocusAttempts = 0
            return
        }
        pendingFocusAttempts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.applyPendingFocusRequest()
        }
    }

    override var intrinsicContentSize: NSSize {
        if verticallyCentersContent {
            // A single-memo editor is a full-canvas control. Advertising the
            // measured text height lets SwiftUI collapse the native view to a
            // line-fragment estimate, which can omit a borderline wrapped
            // line and clip it at the view boundary.
            return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }
        if wrapsContent, bounds.width > 0 {
            let height = attributedStringValue.boundingRect(
                with: NSSize(width: bounds.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).height
            return NSSize(width: NSView.noIntrinsicMetric, height: ceil(height))
        }
        return NSSize(width: NSView.noIntrinsicMetric, height: super.intrinsicContentSize.height)
    }

    override func layout() {
        super.layout()
        if wrapsContent, abs(bounds.width - lastLayoutWidth) > 0.5 {
            lastLayoutWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
        if let editor = currentEditor() as? MouseSafeTaskFieldEditor {
            editor.verticallyCentersContent = verticallyCentersContent
            editor.refreshTextGeometry()
        }
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
