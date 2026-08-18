//
//  MouseSafeTaskFieldEditor.swift
//  Tildone
//

import AppKit

final class MouseSafeTaskFieldEditor: NSTextView {
    private weak var observedClipView: NSClipView?
    private var clipViewObservers: [NSObjectProtocol] = []
    private var isRestoringTextGeometry = false
    private var enforcedInsertionPointColor = NSColor.textColor

    deinit {
        clipViewObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override var selectedTextAttributes: [NSAttributedString.Key: Any] {
        get { TaskTextSelectionStyle.withHighContrast(super.selectedTextAttributes) }
        set { super.selectedTextAttributes = TaskTextSelectionStyle.withHighContrast(newValue) }
    }

    override func drawInsertionPoint(
        in rect: NSRect,
        color: NSColor,
        turnedOn flag: Bool
    ) {
        super.drawInsertionPoint(
            in: rect,
            color: enforcedInsertionPointColor,
            turnedOn: flag
        )
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(
            ranges,
            affinity: affinity,
            stillSelecting: stillSelectingFlag
        )
        enforceSelectionContrast()
        enforceInsertionPointColor(enforcedInsertionPointColor)
        restoreFirstCharacterPosition()
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        super.scrollRangeToVisible(range)
        restoreFirstCharacterPosition()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        observeClipViewBounds()
        restoreFirstCharacterPosition()
    }

    func enforceSelectionContrast() {
        super.selectedTextAttributes = TaskTextSelectionStyle.withHighContrast(
            super.selectedTextAttributes
        )
    }

    func enforceInsertionPointColor(_ color: NSColor) {
        enforcedInsertionPointColor = color.withAlphaComponent(1)
        super.insertionPointColor = enforcedInsertionPointColor
    }

    private func observeClipViewBounds() {
        clipViewObservers.forEach(NotificationCenter.default.removeObserver)
        clipViewObservers.removeAll()
        guard let clipView = superview as? NSClipView else {
            observedClipView = nil
            return
        }
        observedClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        clipView.postsFrameChangedNotifications = true
        clipViewObservers = [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification].map {
            notificationName in
            NotificationCenter.default.addObserver(
                forName: notificationName,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.restoreFirstCharacterPosition()
            }
        }
    }

    private func restoreFirstCharacterPosition() {
        guard !isRestoringTextGeometry,
              let clipView = observedClipView ?? superview as? NSClipView else { return }
        let textWidth = (textStorage?.size().width ?? 0)
            + 2 * (textContainer?.lineFragmentPadding ?? 0)
        let isOverflowing = textWidth > clipView.bounds.width + 0.5
        let desiredInsetX = isOverflowing ? Self.overflowLeadingCompensation : 0
        let insetNeedsUpdate = abs(textContainerInset.width - desiredInsetX) > 0.001
        let restingOriginX = clipView.frame.minX
        let shouldAnchorLeadingEdge = !isOverflowing || clipView.bounds.origin.x <= 0.001
        let originNeedsUpdate = shouldAnchorLeadingEdge
            && abs(clipView.bounds.origin.x - restingOriginX) > 0.001
        guard insetNeedsUpdate || originNeedsUpdate else { return }

        isRestoringTextGeometry = true
        if insetNeedsUpdate {
            textContainerInset = NSSize(width: desiredInsetX, height: textContainerInset.height)
        }
        if originNeedsUpdate {
            clipView.setBoundsOrigin(NSPoint(x: restingOriginX, y: clipView.bounds.origin.y))
        }
        isRestoringTextGeometry = false
    }

    private static let overflowLeadingCompensation: CGFloat = 2
}
