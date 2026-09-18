//
//  MouseSafeTaskFieldEditor.swift
//  Tildone
//

import AppKit
import QuartzCore

final class MouseSafeTaskFieldEditor: NSTextView {
    var onBecomeFirstResponder: (() -> Void)?
    var verticallyCentersContent = false {
        didSet { updateEmptyInsertionPoint() }
    }
    var emptyInsertionPointFont: NSFont? {
        didSet { updateEmptyInsertionPoint() }
    }
    var onPastedList: ((NSAttributedString) -> Bool)?
    private weak var observedClipView: NSClipView?
    private var clipViewObservers: [NSObjectProtocol] = []
    private var isRestoringTextGeometry = false
    private var hasPendingWrappedGeometryRefresh = false
    private var enforcedInsertionPointColor = NSColor.textColor
    private lazy var emptyInsertionPointView: NSView = {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.cornerRadius = 1
        view.isHidden = true
        return view
    }()

    private var usesEmptyInsertionPoint: Bool {
        verticallyCentersContent && string.isEmpty && emptyInsertionPointFont != nil
    }

    override var shouldDrawInsertionPoint: Bool {
        usesEmptyInsertionPoint ? false : super.shouldDrawInsertionPoint
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            enforceInsertionPointColor(enforcedInsertionPointColor)
            updateEmptyInsertionPoint()
            onBecomeFirstResponder?()
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        updateEmptyInsertionPoint()
        return didResignFirstResponder
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        var fallback: NSAttributedString?
        for type in [NSPasteboard.PasteboardType.rtf, .html] {
            guard let data = pasteboard.data(forType: type),
                  let attributed = try? NSAttributedString(
                      data: data,
                      options: [.documentType: documentType(for: type)],
                      documentAttributes: nil
                  ) else { continue }
            if onPastedList?(attributed) == true { return }
            if fallback == nil { fallback = attributed }
        }
        if let fallback {
            insertText(fallback, replacementRange: selectedRange())
            return
        }
        if let text = pasteboard.string(forType: .string),
           onPastedList?(NSAttributedString(string: text)) == true {
            return
        }
        super.paste(sender)
    }

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

    override func layout() {
        super.layout()
        updateEmptyInsertionPoint()
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
        updateEmptyInsertionPoint()
    }

    func refreshTextGeometry() {
        restoreFirstCharacterPosition()
        guard verticallyCentersContent, !hasPendingWrappedGeometryRefresh else { return }
        // AppKit initially installs its shared field editor with a single-line
        // glyph layout. The wrapping geometry settles later in this run-loop
        // turn, so recenter once more using the final line fragments.
        hasPendingWrappedGeometryRefresh = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasPendingWrappedGeometryRefresh = false
            self.restoreFirstCharacterPosition()
        }
    }

    func refreshEmptyInsertionPoint() {
        updateEmptyInsertionPoint()
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
        let textHeight: CGFloat
        if let textContainer, let layoutManager {
            layoutManager.ensureLayout(for: textContainer)
            textHeight = layoutManager.usedRect(for: textContainer).height
        } else {
            textHeight = textStorage?.size().height ?? 0
        }
        let isOverflowing = textWidth > clipView.bounds.width + 0.5
        let isVerticallyOverflowing = textHeight > clipView.bounds.height + 0.5
        let desiredInsetX = isOverflowing ? Self.overflowLeadingCompensation : 0
        let insetNeedsUpdate = abs(textContainerInset.width - desiredInsetX) > 0.001
        let restingOriginX = clipView.frame.minX
        let shouldAnchorLeadingEdge = !isOverflowing || clipView.bounds.origin.x <= 0.001
        let originNeedsUpdate = shouldAnchorLeadingEdge
            && abs(clipView.bounds.origin.x - restingOriginX) > 0.001
        let verticalOriginNeedsUpdate = !isVerticallyOverflowing
            && abs(clipView.bounds.origin.y) > 0.001
        let desiredInsetY = verticallyCentersContent
            ? max(0, (clipView.bounds.height - textHeight) / 2)
            : textContainerInset.height
        let verticalInsetNeedsUpdate = abs(textContainerInset.height - desiredInsetY) > 0.5
        guard insetNeedsUpdate || originNeedsUpdate || verticalOriginNeedsUpdate
                || verticalInsetNeedsUpdate else { return }

        isRestoringTextGeometry = true
        if insetNeedsUpdate {
            textContainerInset = NSSize(width: desiredInsetX, height: textContainerInset.height)
        }
        if verticalInsetNeedsUpdate {
            textContainerInset = NSSize(width: textContainerInset.width, height: desiredInsetY)
        }
        if originNeedsUpdate {
            clipView.setBoundsOrigin(NSPoint(x: restingOriginX, y: clipView.bounds.origin.y))
        }
        if verticalOriginNeedsUpdate {
            clipView.setBoundsOrigin(NSPoint(x: clipView.bounds.origin.x, y: 0))
        }
        isRestoringTextGeometry = false
        updateEmptyInsertionPoint()
    }

    private func updateEmptyInsertionPoint() {
        guard usesEmptyInsertionPoint,
              window?.firstResponder === self,
              let emptyInsertionPointFont,
              !visibleRect.isEmpty else {
            emptyInsertionPointView.isHidden = true
            emptyInsertionPointView.layer?.removeAnimation(forKey: Self.emptyCaretBlinkAnimationKey)
            return
        }

        if emptyInsertionPointView.superview !== self {
            addSubview(emptyInsertionPointView, positioned: .above, relativeTo: nil)
        }
        let fontHeight = layoutManager?.defaultLineHeight(for: emptyInsertionPointFont)
            ?? (emptyInsertionPointFont.ascender - emptyInsertionPointFont.descender
                + emptyInsertionPointFont.leading)
        let height = min(ceil(fontHeight), visibleRect.height)
        emptyInsertionPointView.frame = NSRect(
            x: floor(visibleRect.midX - 1),
            y: floor(visibleRect.midY - height / 2),
            width: 2,
            height: height
        )
        emptyInsertionPointView.layer?.backgroundColor = enforcedInsertionPointColor.cgColor
        emptyInsertionPointView.isHidden = false
        guard emptyInsertionPointView.layer?.animation(forKey: Self.emptyCaretBlinkAnimationKey) == nil else {
            return
        }
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1
        blink.toValue = 0
        blink.duration = 0.5
        blink.autoreverses = true
        blink.repeatCount = .infinity
        blink.timingFunction = CAMediaTimingFunction(name: .linear)
        emptyInsertionPointView.layer?.add(blink, forKey: Self.emptyCaretBlinkAnimationKey)
    }

    private static let overflowLeadingCompensation: CGFloat = 2
    private static let emptyCaretBlinkAnimationKey = "TildoneEmptyMemoCaretBlink"

    private func documentType(
        for pasteboardType: NSPasteboard.PasteboardType
    ) -> NSAttributedString.DocumentType {
        pasteboardType == .rtf ? .rtf : .html
    }
}
