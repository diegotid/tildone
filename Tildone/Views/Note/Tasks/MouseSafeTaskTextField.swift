//
//  MouseSafeTaskTextField.swift
//  Tildone
//

import AppKit
import SwiftUI
import TildoneDomain

struct MouseSafeTaskTextField: NSViewRepresentable {
    @Binding var richText: RichText
    let taskID: TaskID
    let isFocused: Bool
    let placesCaretAtStartOnFocus: Bool
    let fontSize: CGFloat
    let textColor: Color
    let cursorColor: Color
    let truncation: TaskLineTruncation
    let onFocus: () -> Void
    let onBlur: () -> Void
    let onEnter: (Int) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MouseSafeTaskNSTextField {
        let field = MouseSafeTaskNSTextField()
        field.cell = MouseSafeTaskNSTextFieldCell(textCell: "")
        field.isEditable = true
        field.allowsEditingTextAttributes = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .left
        field.lineBreakMode = truncation == .single ? .byTruncatingTail : .byWordWrapping
        field.usesSingleLineMode = truncation == .single
        field.cell?.lineBreakMode = field.lineBreakMode
        // Inactive task rows should use their tail-truncation mode. A
        // scrollable NSTextField clips its right edge instead of drawing an
        // ellipsis, particularly when indentation leaves little width.
        field.cell?.isScrollable = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.cursorColor = NSColor(cursorColor)
        field.onEditorFocus = { [weak coordinator = context.coordinator] in
            coordinator?.editorDidAcquireFocus()
        }
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: MouseSafeTaskNSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.field = field
        field.taskID = taskID
        field.placesCaretAtStartOnFocus = placesCaretAtStartOnFocus
        field.cursorColor = NSColor(cursorColor)
        let editor = field.currentEditor()
        let isActivelyEditing = editor != nil && field.window?.firstResponder === editor
        let fieldRichText = Self.richText(from: field.attributedStringValue)
        let preservingCanonicalAfterBlur = context.coordinator.shouldPreserveCanonicalAfterBlur(model: richText)
        if !isActivelyEditing, !preservingCanonicalAfterBlur {
            context.coordinator.canonicalRichText = richText
        }
        let baseColor = NSColor(textColor)
        let presentationChanged = context.coordinator.lastFontSize != fontSize
            || context.coordinator.lastBaseColor?.isEqual(baseColor) != true
        if !isActivelyEditing,
           !preservingCanonicalAfterBlur,
           fieldRichText != richText || presentationChanged {
            field.attributedStringValue = Self.attributedString(
                from: richText,
                fontSize: fontSize,
                baseColor: baseColor
            )
        }
        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastBaseColor = baseColor
        field.cell?.isScrollable = isActivelyEditing
        field.updateTruncationTooltip()
        if let editor = editor as? NSTextView {
            Self.configure(
                editor,
                cursorColor: NSColor(cursorColor)
            )
        }

        // Model refreshes during blur must not reclaim focus from the row the
        // user just clicked. Only a new SwiftUI focus request moves responders.
        if isFocused && !context.coordinator.lastRequestedFocus {
            field.hasPendingFocusRequest = true
        } else if !isFocused {
            field.hasPendingFocusRequest = false
        }
        context.coordinator.lastRequestedFocus = isFocused
        field.applyPendingFocusRequest()
    }

    static func shouldApplyModelText(
        fieldText: String,
        modelText: String,
        isActivelyEditing: Bool
    ) -> Bool {
        !isActivelyEditing && fieldText != modelText
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MouseSafeTaskTextField
        weak var field: MouseSafeTaskNSTextField?
        var lastFontSize: CGFloat?
        var lastBaseColor: NSColor?
        var lastRequestedFocus = false
        var canonicalRichText: RichText
        private var lastSelection = NSRange(location: 0, length: 0)
        private var lastEditor: NSTextView?
        private var hasLocalEdits = false
        private var preservesCanonicalAfterBlur = false
        private var formatObserver: NSObjectProtocol?
        private var selectionObserver: NSObjectProtocol?

        init(parent: MouseSafeTaskTextField) {
            self.parent = parent
            canonicalRichText = parent.richText
            super.init()
            formatObserver = NotificationCenter.default.addObserver(
                forName: .formatTaskText,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let format = notification.object as? RichTextFormat else { return }
                self?.apply(format)
            }
            selectionObserver = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      let editor = notification.object as? NSTextView,
                      editor === self.field?.currentEditor(),
                      self.field?.window?.firstResponder === editor else { return }
                self.lastEditor = editor
                self.lastSelection = editor.selectedRange()
                self.configure(editor)
            }
        }

        deinit {
            if let formatObserver { NotificationCenter.default.removeObserver(formatObserver) }
            if let selectionObserver { NotificationCenter.default.removeObserver(selectionObserver) }
        }

        func editorDidAcquireFocus() {
            // Selection/caret placement starts before NSTextField reports a
            // text edit. Publish that focus after AppKit installs its editor.
            DispatchQueue.main.async { [weak self] in
                guard let self, let field = self.field,
                      let editor = field.currentEditor() as? NSTextView,
                      field.window?.firstResponder === editor else { return }
                self.lastEditor = editor
                self.lastSelection = editor.selectedRange()
                self.configure(editor)
                field.cell?.isScrollable = true
                self.parent.onFocus()
            }
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            hasLocalEdits = false
            preservesCanonicalAfterBlur = false
            if let field = notification.object as? NSTextField,
               let editor = field.currentEditor() as? NSTextView {
                lastEditor = editor
                lastSelection = editor.selectedRange()
                configure(editor)
            }
            parent.onFocus()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            let editedField = (notification.object as? MouseSafeTaskNSTextField) ?? field
            let publishesLocalValue = hasLocalEdits
            let finalRichText: RichText
            if publishesLocalValue {
                if let editor = editedField?.currentEditor() as? NSTextView {
                    lastEditor = editor
                    lastSelection = editor.selectedRange()
                    finalRichText = preservingCanonicalSpans(
                        in: MouseSafeTaskTextField.richText(from: editor.attributedString())
                    )
                } else if let editedField {
                    finalRichText = preservingCanonicalSpans(
                        in: MouseSafeTaskTextField.richText(from: editedField.attributedStringValue)
                    )
                } else {
                    finalRichText = canonicalRichText
                }
            } else {
                finalRichText = parent.richText
            }
            canonicalRichText = finalRichText
            preservesCanonicalAfterBlur = publishesLocalValue
            hasLocalEdits = false
            if publishesLocalValue {
                parent.richText = finalRichText
            }
            // Publish the rich value before changing SwiftUI's focused-row
            // state. The latter swaps this editor for the inactive renderer;
            // deferring it one turn prevents that renderer from reading the
            // pre-blur plain task snapshot.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let field = self.field,
                   let editor = field.currentEditor() as? NSTextView,
                   field.window?.firstResponder === editor {
                    return
                }
                self.parent.onBlur()
            }

            // NSTextField may copy the field editor's string back after this
            // delegate callback. Reinstall the canonical attributed value on
            // the following run-loop turn so the inactive row cannot retain a
            // visually flattened value while its model still has spans.
            let fontSize = parent.fontSize
            let baseColor = NSColor(parent.textColor)
            DispatchQueue.main.async { [weak editedField] in
                guard let editedField,
                      editedField.window?.firstResponder !== editedField.currentEditor() else { return }
                editedField.attributedStringValue = MouseSafeTaskTextField.attributedString(
                    from: finalRichText,
                    fontSize: fontSize,
                    baseColor: baseColor
                )
                editedField.updateTruncationTooltip()
            }
        }

        private func configure(_ editor: NSTextView) {
            MouseSafeTaskTextField.configure(
                editor,
                cursorColor: NSColor(parent.cursorColor)
            )
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField,
                  let editor = field.currentEditor() as? NSTextView else { return }
            lastEditor = editor
            lastSelection = editor.selectedRange()
            let editedRichText = preservingCanonicalSpans(
                in: MouseSafeTaskTextField.richText(from: editor.attributedString())
            )
            hasLocalEdits = true
            canonicalRichText = editedRichText
            parent.richText = editedRichText
        }

        private func apply(_ format: RichTextFormat) {
            guard let field, let window = field.window,
                  NSApp.keyWindow == nil || window.isKeyWindow else { return }
            let activeEditor = field.currentEditor() as? NSTextView
            let isEditing = activeEditor != nil && window.firstResponder === activeEditor
            // The notification is shared by every note and row. A retained
            // editor from a previous selection must not receive this command.
            guard isEditing || (parent.isFocused && lastEditor != nil) else { return }
            let editor = (field.currentEditor() as? NSTextView) ?? lastEditor
            let fieldRichText = MouseSafeTaskTextField.richText(from: field.attributedStringValue)
            let editorRichText = editor.map {
                MouseSafeTaskTextField.richText(from: $0.attributedString())
            }
            // AppKit can leave a retained field editor with an empty or
            // flattened string for one turn after it resigns first responder.
            // Prefer whichever native value still has the canonical text;
            // otherwise use the session value captured before blur.
            let currentNativeRichText: RichText
            if let editorRichText, editorRichText.text == canonicalRichText.text {
                currentNativeRichText = editorRichText
            } else if fieldRichText.text == canonicalRichText.text {
                currentNativeRichText = fieldRichText
            } else {
                currentNativeRichText = canonicalRichText
            }
            let rawSelection: NSRange
            if let editor,
               field.window?.firstResponder === editor {
                rawSelection = editor.selectedRange()
            } else {
                rawSelection = lastSelection
            }
            let selectionLocation = max(0, min(rawSelection.location, currentNativeRichText.utf16Count))
            let selection = NSRange(
                location: selectionLocation,
                length: max(0, min(rawSelection.length, currentNativeRichText.utf16Count - selectionLocation))
            )
            let current = preservingCanonicalSpans(in: currentNativeRichText)
            let formatted = current.applying(
                format,
                to: RichTextRange(location: selection.location, length: selection.length)
            )
            guard formatted != current else { return }
            hasLocalEdits = true
            preservesCanonicalAfterBlur = true
            canonicalRichText = formatted
            let attributed = MouseSafeTaskTextField.attributedString(
                from: formatted,
                fontSize: parent.fontSize,
                baseColor: NSColor(parent.textColor)
            )
            if isEditing, let editor {
                editor.textStorage?.setAttributedString(attributed)
                editor.setSelectedRange(selection)
                configure(editor)
            } else {
                field.attributedStringValue = attributed
            }
            parent.richText = formatted
        }

        func textViewDidChangeSelection(_ textView: NSTextView) {
            lastEditor = textView
            lastSelection = textView.selectedRange()
        }

        private func preservingCanonicalSpans(in nativeRichText: RichText) -> RichText {
            nativeRichText.text == canonicalRichText.text
                ? canonicalRichText
                : nativeRichText
        }

        func shouldPreserveCanonicalAfterBlur(model: RichText) -> Bool {
            guard preservesCanonicalAfterBlur else { return false }
            if model == canonicalRichText {
                preservesCanonicalAfterBlur = false
                return false
            }
            // The model can be one SwiftUI update behind the blur callback.
            // Keep the editor-session value only while that stale snapshot has
            // the same characters. A real text change is accepted immediately.
            return model.text == canonicalRichText.text
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onEnter(textView.selectedRange().location)
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown()
                return true
            default:
                return false
            }
        }
    }

    private static func configure(_ editor: NSTextView, cursorColor: NSColor) {
        let opaqueCursorColor = cursorColor.withAlphaComponent(1)
        if let editor = editor as? MouseSafeTaskFieldEditor {
            editor.enforceInsertionPointColor(opaqueCursorColor)
        } else {
            editor.insertionPointColor = opaqueCursorColor
        }
        TaskTextSelectionStyle.apply(to: editor)
    }

    static func attributedString(
        from richText: RichText,
        fontSize: CGFloat,
        baseColor: NSColor
    ) -> NSAttributedString {
        let baseFont = NSFont.systemFont(ofSize: fontSize)
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
            var traits: NSFontTraitMask = []
            if span.attributes.contains(.bold) { traits.insert(.boldFontMask) }
            if span.attributes.contains(.italic) { traits.insert(.italicFontMask) }
            if !traits.isEmpty {
                attributes[.font] = NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
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
                    attributes[.foregroundColor] = nsColor(color)
                }
            }
            if let name = span.attributes.highlightColorName {
                attributes[highlightNameKey] = name
                if let color = RichTextColor(rawValue: name) {
                    attributes[.backgroundColor] = nsColor(color).withAlphaComponent(0.34)
                }
            }
            result.addAttributes(attributes, range: range)
        }
        return result
    }

    static func richText(from attributed: NSAttributedString) -> RichText {
        var spans: [RichTextSpan] = []
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttributes(in: fullRange) { attributes, range, _ in
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

    static func displayAttributedString(
        from richText: RichText,
        fontSize: CGFloat,
        baseColor: NSColor,
        detectLinks: Bool = true,
        shortenLinks: Bool = false
    ) -> AttributedString {
        let result = NSMutableAttributedString(
            attributedString: attributedString(from: richText, fontSize: fontSize, baseColor: baseColor)
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
                    attributes[.foregroundColor] = NSColor.controlAccentColor
                    result.replaceCharacters(
                        in: match.range,
                        with: NSAttributedString(string: displayHost, attributes: attributes)
                    )
                } else {
                    result.addAttributes([
                        .link: url,
                        .foregroundColor: NSColor.controlAccentColor
                    ], range: match.range)
                }
            }
        }
        return (try? AttributedString(result, including: \.appKit))
            ?? AttributedString(richText.text)
    }

    static func nsColor(_ color: RichTextColor) -> NSColor {
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
