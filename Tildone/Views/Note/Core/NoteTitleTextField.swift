//
//  NoteTitleTextField.swift
//  Tildone
//

import AppKit
import SwiftUI

/// A native title/new-task editor that routes a pasted task list back to its note
/// before AppKit inserts that list into the title field.
struct NoteTitleTextField: NSViewRepresentable {
    @AppStorage(TaskSpellChecking.storageKey) private var spellCheckingEnabled = true
    @Binding var text: String
    let placeholder: String
    let isFocused: Bool
    var isNoteTitleField = true
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
        field.isNoteTitleField = isNoteTitleField
        field.isNewTaskField = !isNoteTitleField
        field.onEditorFocus = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onFocus()
        }
        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderString = placeholder
        field.font = font
        field.textColor = textColor
        field.cursorColor = textColor
        field.isEditable = true
        field.isSelectable = true
        field.focusRingType = .none
        field.isBordered = false
        field.drawsBackground = false
        field.lineBreakMode = .byTruncatingTail
        field.cell?.lineBreakMode = .byTruncatingTail
        field.cell?.truncatesLastVisibleLine = true
        // A scrollable inactive field clips its trailing edge instead of drawing
        // the topic's ellipsis. Enable scrolling only while the user edits it.
        field.cell?.isScrollable = false
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
        field.cursorColor = textColor
        field.onPastedList = { [weak coordinator = context.coordinator] attributed in
            coordinator?.handlePastedList(attributed) ?? false
        }
        field.onPasteboardList = { [weak coordinator = context.coordinator] list in
            coordinator?.parent.onPastedList(list) ?? false
        }
        let editor = field.currentEditor()
        if let editor = editor as? NSTextView {
            TaskSpellChecking.apply(spellCheckingEnabled, to: editor)
        }
        let isEditing = context.coordinator.isEditing
            || (editor != nil && field.window?.firstResponder === editor)
        field.cell?.isScrollable = isEditing
        // New notes can receive automatic title focus before the iPhone's
        // rename arrives. Focus alone must not hold back that remote title.
        if (!isEditing || !context.coordinator.hasEditedText), field.stringValue != text {
            field.stringValue = text
            if isEditing, let editor = editor as? NSTextView {
                let selection = editor.selectedRange()
                editor.string = text
                let location = min(selection.location, text.utf16.count)
                editor.setSelectedRange(NSRange(
                    location: location,
                    length: min(selection.length, text.utf16.count - location)
                ))
            }
        }
        // A model refresh must not reclaim focus after the user clicks a row.
        if isFocused, !context.coordinator.lastRequestedFocus {
            field.hasPendingFocusRequest = true
        } else if !isFocused {
            field.hasPendingFocusRequest = false
        }
        context.coordinator.lastRequestedFocus = isFocused
        field.schedulePendingFocusRequest()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NoteTitleTextField
        weak var field: MouseSafeTaskNSTextField?
        var isEditing = false
        var hasEditedText = false
        var lastRequestedFocus = false

        init(parent: NoteTitleTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
            hasEditedText = false
            parent.onFocus()
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            hasEditedText = true
            parent.text = field.stringValue
            parent.onTextChange()
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
            hasEditedText = false
            // A remote snapshot skipped during typing may not trigger another
            // SwiftUI update when editing ends. Reconcile the field here too.
            field?.stringValue = parent.text
            field?.cell?.isScrollable = false
            parent.onBlur()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            let advancesFromTitle = parent.isNoteTitleField && (
                commandSelector == #selector(NSResponder.moveDown(_:))
                    || commandSelector == #selector(NSResponder.insertTab(_:))
            )
            guard commandSelector == #selector(NSResponder.insertNewline(_:))
                    || advancesFromTitle else {
                return false
            }
            parent.onSubmit()
            if !parent.isNoteTitleField {
                // Return keeps the draft editor active; reflect the cleared
                // binding without waiting for an end-editing notification.
                field?.stringValue = parent.text
                textView.string = parent.text
            }
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
