//
//  RichTaskTextEditor.swift
//  Tildone
//
import SwiftUI
import TildoneDomain
import UIKit

extension Notification.Name {
    static let formatTaskText = Notification.Name("formatTaskText")
}

struct RichTaskTextEditor: UIViewRepresentable {
    private static let rowHeight: CGFloat = 33

    @Binding var richText: RichText
    let modelRichText: RichText
    let taskID: TaskID
    var focusedTask: FocusState<TaskID?>.Binding
    let isCompleted: Bool
    let onCommit: (RichText) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.isEditable = true
        view.isSelectable = true
        view.allowsEditingTextAttributes = true
        let lineHeight = UIFont.preferredFont(forTextStyle: .body).lineHeight
        let verticalInset = max(0, (Self.rowHeight - lineHeight) / 2)
        view.textContainerInset = UIEdgeInsets(
            top: verticalInset,
            left: 0,
            bottom: verticalInset,
            right: 0
        )
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.maximumNumberOfLines = 1
        view.textContainer.lineBreakMode = .byTruncatingTail
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.returnKeyType = .done
        view.autocapitalizationType = .sentences
        view.adjustsFontForContentSizeCategory = true
        view.accessibilityLabel = String(localized: "Task")
        context.coordinator.view = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.view = view
        if !view.isFirstResponder {
            view.attributedText = Self.attributedString(from: richText, completed: isCompleted)
        }
        if focusedTask.wrappedValue == taskID {
            if !view.isFirstResponder { view.becomeFirstResponder() }
        } else if view.isFirstResponder {
            view.resignFirstResponder()
        }
        view.alpha = isCompleted ? 0.6 : 1
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private static weak var formattingTarget: Coordinator?

        var parent: RichTaskTextEditor
        weak var view: UITextView?
        private var lastSelection = NSRange(location: 0, length: 0)
        private var lastCommittedRichText: RichText?
        private var hasLocalEdits = false
        private var formatObserver: NSObjectProtocol?

        init(parent: RichTaskTextEditor) {
            self.parent = parent
            super.init()
            formatObserver = NotificationCenter.default.addObserver(
                forName: .formatTaskText,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let format = notification.object as? RichTextFormat else { return }
                self?.apply(format)
            }
        }

        deinit {
            if Self.formattingTarget === self { Self.formattingTarget = nil }
            if let formatObserver { NotificationCenter.default.removeObserver(formatObserver) }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            Self.formattingTarget = self
            parent.focusedTask.wrappedValue = parent.taskID
            lastSelection = textView.selectedRange
            hasLocalEdits = false
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if hasLocalEdits {
                let finalRichText = RichTaskTextEditor.richText(from: textView.attributedText)
                parent.richText = finalRichText
                if finalRichText != lastCommittedRichText {
                    parent.onCommit(finalRichText)
                    lastCommittedRichText = finalRichText
                }
            } else {
                // A remote style can arrive while this row still owns the
                // caret. Leaving that untouched editor must reveal the newer
                // model value instead of writing its stale attributes back.
                parent.richText = parent.modelRichText
                textView.attributedText = RichTaskTextEditor.attributedString(
                    from: parent.modelRichText,
                    completed: parent.isCompleted
                )
            }
            hasLocalEdits = false
            if parent.focusedTask.wrappedValue == parent.taskID {
                parent.focusedTask.wrappedValue = nil
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            hasLocalEdits = true
            parent.richText = RichTaskTextEditor.richText(from: textView.attributedText)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.isFirstResponder else { return }
            Self.formattingTarget = self
            lastSelection = textView.selectedRange
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard text == "\n" else { return true }
            textView.resignFirstResponder()
            return false
        }

        private func apply(_ format: RichTextFormat) {
            guard let view,
                  Self.formattingTarget === self else { return }
            let selection = Self.validSelection(
                view.isFirstResponder ? view.selectedRange : lastSelection,
                textLength: view.attributedText.length
            )
            let current = RichTaskTextEditor.richText(from: view.attributedText)
            let formatted = current.applying(
                format,
                to: RichTextRange(location: selection.location, length: selection.length)
            )
            guard formatted != current else { return }
            view.attributedText = RichTaskTextEditor.attributedString(
                from: formatted,
                completed: parent.isCompleted
            )
            view.selectedRange = selection
            lastSelection = selection
            parent.richText = formatted
            parent.onCommit(formatted)
            lastCommittedRichText = formatted
            hasLocalEdits = false
            parent.focusedTask.wrappedValue = parent.taskID
            DispatchQueue.main.async { [weak view] in
                guard let view, !view.isFirstResponder else { return }
                view.becomeFirstResponder()
                view.selectedRange = selection
            }
        }

        private static func validSelection(_ selection: NSRange, textLength: Int) -> NSRange {
            let location = selection.location == NSNotFound
                ? textLength
                : min(max(0, selection.location), textLength)
            return NSRange(
                location: location,
                length: min(max(0, selection.length), textLength - location)
            )
        }
    }

    static func displayText(
        from richText: RichText,
        baseColor: UIColor = .label,
        detectLinks: Bool = true,
        shortenLinks: Bool = false
    ) -> AttributedString {
        let result = NSMutableAttributedString(
            attributedString: attributedString(from: richText, baseColor: baseColor)
        )
        if detectLinks,
           let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let matches = detector.matches(
                in: result.string,
                range: NSRange(location: 0, length: result.length)
            ).compactMap { match -> (NSTextCheckingResult, URL, String)? in
                guard let url = match.url,
                      let scheme = url.scheme?.lowercased(),
                      ["http", "https"].contains(scheme),
                      let host = url.host,
                      !host.isEmpty else { return nil }
                let displayHost = host.lowercased().hasPrefix("www.")
                    ? String(host.dropFirst(4))
                    : host
                return (match, url, displayHost)
            }
            for (match, url, displayHost) in matches.reversed() {
                if shortenLinks {
                    var attributes = result.attributes(
                        at: match.range.location,
                        effectiveRange: nil
                    )
                    attributes[.link] = url
                    attributes[.foregroundColor] = UIColor.tintColor
                    result.replaceCharacters(
                        in: match.range,
                        with: NSAttributedString(string: displayHost, attributes: attributes)
                    )
                } else {
                    result.addAttributes(
                        [.link: url, .foregroundColor: UIColor.tintColor],
                        range: match.range
                    )
                }
            }
        }
        return (try? AttributedString(result, including: \.uiKit))
            ?? AttributedString(richText.text)
    }

    private static func attributedString(
        from richText: RichText,
        completed: Bool = false,
        baseColor: UIColor = .label
    ) -> NSAttributedString {
        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        let result = NSMutableAttributedString(
            string: richText.text,
            attributes: [.font: baseFont, .foregroundColor: baseColor]
        )
        for span in richText.spans {
            let range = NSRange(location: span.range.location, length: span.range.length)
            var attributes: [NSAttributedString.Key: Any] = [
                styleNamesKey: span.attributes.styleNames.joined(separator: ",")
            ]
            if !span.attributes.extensions.isEmpty,
               let encoded = try? JSONEncoder().encode(span.attributes.extensions),
               let encodedString = String(data: encoded, encoding: .utf8) {
                attributes[extensionsKey] = encodedString
            }
            var traits = baseFont.fontDescriptor.symbolicTraits
            if span.attributes.contains(.bold) { traits.insert(.traitBold) }
            if span.attributes.contains(.italic) { traits.insert(.traitItalic) }
            if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) {
                attributes[.font] = UIFont(descriptor: descriptor, size: baseFont.pointSize)
            }
            if span.attributes.contains(.underline) {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if span.attributes.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let name = span.attributes.foregroundColorName {
                attributes[foregroundNameKey] = name
                if let color = RichTextColor(rawValue: name) {
                    attributes[.foregroundColor] = uiColor(color)
                }
            }
            if let name = span.attributes.highlightColorName {
                attributes[highlightNameKey] = name
                if let color = RichTextColor(rawValue: name) {
                    attributes[.backgroundColor] = uiColor(color).withAlphaComponent(0.34)
                }
            }
            result.addAttributes(attributes, range: range)
        }
        if completed, result.length > 0 {
            result.addAttribute(
                .strikethroughStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: NSRange(location: 0, length: result.length)
            )
        }
        return result
    }

    private static func richText(from attributed: NSAttributedString) -> RichText {
        var spans: [RichTextSpan] = []
        attributed.enumerateAttributes(
            in: NSRange(location: 0, length: attributed.length)
        ) { attributes, range, _ in
            let styleNames = (attributes[styleNamesKey] as? String)?
                .split(separator: ",").map(String.init) ?? []
            let extensions: [String: String]
            if let encodedString = attributes[extensionsKey] as? String,
               let data = encodedString.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                extensions = decoded
            } else {
                extensions = [:]
            }
            let richAttributes = RichTextAttributes(
                styleNames: styleNames,
                foregroundColorName: attributes[foregroundNameKey] as? String,
                highlightColorName: attributes[highlightNameKey] as? String,
                extensions: extensions
            )
            guard !richAttributes.isEmpty else { return }
            spans.append(RichTextSpan(
                range: RichTextRange(location: range.location, length: range.length),
                attributes: richAttributes
            ))
        }
        return RichText(text: attributed.string, spans: spans)
    }

    private static func uiColor(_ color: RichTextColor) -> UIColor {
        switch color {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .gray: .systemGray
        }
    }

    private static let styleNamesKey = NSAttributedString.Key("TildoneRichTextStyles")
    private static let foregroundNameKey = NSAttributedString.Key("TildoneRichTextForeground")
    private static let highlightNameKey = NSAttributedString.Key("TildoneRichTextHighlight")
    private static let extensionsKey = NSAttributedString.Key("TildoneRichTextExtensions")
}
