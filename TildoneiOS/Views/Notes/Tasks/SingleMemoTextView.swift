import UIKit

/// SwiftUI supplies the keyboard-safe viewport; TextKit fits and centers its contents.
final class SingleMemoTextView: UITextView {
    var fitsSingleMemo = false
    private var isFitting = false
    private var fittedText: NSAttributedString?
    private var fittedSize = CGSize.zero
    private var fittedCategory: UIContentSizeCategory?
    private var fittedFontName: String?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard fitsSingleMemo, !isFitting, markedTextRange == nil,
              bounds.width > 0, bounds.height > 0 else { return }
        if fittedSize == bounds.size, fittedCategory == traitCollection.preferredContentSizeCategory,
           fittedText == attributedText,
           fittedFontName == (typingAttributes[.font] as? UIFont)?.fontName { return }
        isFitting = true
        defer { isFitting = false }

        let metrics = UIFontMetrics(forTextStyle: .body)
        var low = metrics.scaledValue(for: 18, compatibleWith: traitCollection)
        var high = metrics.scaledValue(for: 76, compatibleWith: traitCollection)
        let availableHeight = max(1, bounds.height - 16)
        let source = attributedText ?? NSAttributedString(string: "")
        let baseFont = (typingAttributes[.font] as? UIFont) ?? font ?? .systemFont(ofSize: 18)
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: bounds.width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = textContainer.lineFragmentPadding
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)

        func resized(_ size: CGFloat) -> NSAttributedString {
            let result = NSMutableAttributedString(attributedString: source)
            source.enumerateAttribute(.font, in: NSRange(location: 0, length: source.length)) { value, range, _ in
                result.addAttribute(.font, value: (value as? UIFont ?? baseFont).withSize(size), range: range)
            }
            return result
        }

        func height(at size: CGFloat) -> CGFloat {
            if source.length == 0 { return baseFont.withSize(size).lineHeight }
            storage.setAttributedString(resized(size))
            manager.ensureLayout(for: container)
            return ceil(max(manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY))
        }

        for _ in 0..<9 {
            let candidate = (low + high) / 2
            if height(at: candidate) <= availableHeight { low = candidate } else { high = candidate }
        }
        let contentHeight = height(at: low)
        let selection = selectedRange
        // Mutate only presentation attributes, preserving rich text and the active caret.
        let fitted = resized(low)
        textStorage.beginEditing()
        fitted.enumerateAttribute(.font, in: NSRange(location: 0, length: fitted.length)) { value, range, _ in
            if let value { textStorage.addAttribute(.font, value: value, range: range) }
        }
        textStorage.endEditing()
        selectedRange = selection
        var typing = typingAttributes
        typing[.font] = (typing[.font] as? UIFont ?? baseFont).withSize(low)
        typingAttributes = typing
        let inset = max(8, (bounds.height - contentHeight) / 2)
        textContainerInset = UIEdgeInsets(top: inset, left: 0, bottom: 8, right: 0)
        isScrollEnabled = contentHeight > availableHeight
        if !isScrollEnabled { contentOffset = .zero }
        fittedText = NSAttributedString(attributedString: attributedText)
        fittedFontName = (typingAttributes[.font] as? UIFont)?.fontName
        fittedSize = bounds.size
        fittedCategory = traitCollection.preferredContentSizeCategory
    }
}
