import AppKit

final class TaskSpellingMarksView: NSView {
    private let storage = NSTextStorage()
    private let manager = NSLayoutManager()
    private let container = NSTextContainer(size: NSSize(
        width: CGFloat.greatestFiniteMagnitude,
        height: CGFloat.greatestFiniteMagnitude
    ))

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(text: NSAttributedString, ranges: [NSRange]) {
        let drawingText = NSMutableAttributedString(attributedString: text)
        let fullRange = NSRange(location: 0, length: text.length)
        // Draw only AppKit's spelling indicators. Keep fonts for exact glyph
        // placement, but leave all content and user formatting to SwiftUI.
        for key in [NSAttributedString.Key.backgroundColor, .underlineStyle, .strikethroughStyle, .link, .paragraphStyle] {
            drawingText.removeAttribute(key, range: fullRange)
        }
        drawingText.addAttribute(.foregroundColor, value: NSColor.clear, range: fullRange)
        manager.removeTemporaryAttribute(.spellingState, forCharacterRange: NSRange(location: 0, length: storage.length))
        storage.setAttributedString(drawingText)
        for range in ranges where range.location >= 0 && NSMaxRange(range) <= storage.length {
            manager.addTemporaryAttribute(.spellingState, value: 1, forCharacterRange: range)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let glyphs = manager.glyphRange(for: container)
        let usedRect = manager.usedRect(for: container)
        let origin = NSPoint(x: -usedRect.minX, y: (bounds.height - usedRect.height) / 2 - usedRect.minY)
        manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
    }
}
