//
//  NoteTitleTextField.swift
//  Tildone
//

import AppKit
import SwiftUI

/// A native title editor that can route a pasted task list back to its note
/// before AppKit inserts that list into the title field.
struct NoteTitleTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isFocused: Bool
    let font: NSFont
    let textColor: NSColor
    let onFocus: () -> Void
    let onBlur: () -> Void
    let onTextChange: () -> Void
    let onSubmit: () -> Void
    let onPastedList: (MouseSafeTaskTextField.PastedList) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> MouseSafeTaskNSTextField {
        let field = MouseSafeTaskNSTextField()
        field.cell = MouseSafeTaskNSTextFieldCell(textCell: "")
        field.isNoteTitleField = true
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.font = font
        field.textColor = textColor
        field.isEditable = true
        field.isSelectable = true
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = false
        field.lineBreakMode = .byTruncatingTail
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.onPastedList = { [weak coordinator = context.coordinator] attributed in
            coordinator?.handlePastedList(attributed) ?? false
        }
        field.onPasteboardList = { [weak coordinator = context.coordinator] list in
            coordinator?.parent.onPastedList(list) ?? false
        }
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: MouseSafeTaskNSTextField, context: Context) {
        context.coordinator.parent = self
        context.coordinator.field = field
        field.placeholderString = placeholder
        field.font = font
        field.textColor = textColor
        field.onPastedList = { [weak coordinator = context.coordinator] attributed in
            coordinator?.handlePastedList(attributed) ?? false
        }
        field.onPasteboardList = { [weak coordinator = context.coordinator] list in
            coordinator?.parent.onPastedList(list) ?? false
        }
        let isEditing = context.coordinator.isEditing
            || field.window?.firstResponder === field.currentEditor()
        if !isEditing, field.stringValue != text {
            field.stringValue = text
        }
        if isFocused, !isEditing {
            field.hasPendingFocusRequest = true
            field.applyPendingFocusRequest()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NoteTitleTextField
        weak var field: MouseSafeTaskNSTextField?
        var isEditing = false

        init(parent: NoteTitleTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
            parent.onFocus()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            parent.onTextChange()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
            parent.onBlur()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }
            parent.onSubmit()
            return true
        }

        func handlePastedList(_ attributed: NSAttributedString) -> Bool {
            guard let list = MouseSafeTaskTextField.pastedListItems(from: attributed) else {
                return false
            }
            return parent.onPastedList(list)
        }
    }
}
