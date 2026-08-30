//
//  MouseSafeTaskTextField.swift
//  Tildone
//

import AppKit
import SwiftUI
import TildoneDomain

struct MouseSafeTaskTextField: NSViewRepresentable {
    @Binding var text: String
    let taskID: TaskID
    let isFocused: Bool
    let placesCaretAtStartOnFocus: Bool
    let fontSize: CGFloat
    let textColor: Color
    let cursorColor: Color
    let onFocus: () -> Void
    let onBlur: () -> Void
    let onEnter: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MouseSafeTaskNSTextField {
        let field = MouseSafeTaskNSTextField()
        field.cell = MouseSafeTaskNSTextFieldCell(textCell: "")
        field.isEditable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .left
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.lineBreakMode = .byTruncatingTail
        // Inactive task rows should use their tail-truncation mode. A
        // scrollable NSTextField clips its right edge instead of drawing an
        // ellipsis, particularly when indentation leaves little width.
        field.cell?.isScrollable = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: MouseSafeTaskNSTextField, context: Context) {
        context.coordinator.parent = self
        field.taskID = taskID
        field.placesCaretAtStartOnFocus = placesCaretAtStartOnFocus
        let editor = field.currentEditor()
        let isActivelyEditing = editor != nil && field.window?.firstResponder === editor
        if Self.shouldApplyModelText(
            fieldText: field.stringValue,
            modelText: text,
            isActivelyEditing: isActivelyEditing
        ) {
            field.stringValue = text
        }
        field.font = .systemFont(ofSize: fontSize)
        field.textColor = NSColor(textColor)
        field.cell?.isScrollable = isActivelyEditing
        if let editor = editor as? NSTextView {
            Self.configure(
                editor,
                cursorColor: NSColor(cursorColor)
            )
        }

        guard isFocused,
              field.window?.firstResponder !== field.currentEditor() else {
            return
        }
        field.window?.makeFirstResponder(field)
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

        init(parent: MouseSafeTaskTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField,
               let editor = field.currentEditor() as? NSTextView {
                configure(editor)
            }
            parent.onFocus()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onBlur()
        }

        private func configure(_ editor: NSTextView) {
            MouseSafeTaskTextField.configure(
                editor,
                cursorColor: NSColor(parent.cursorColor)
            )
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onEnter()
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
}
