import AppKit
import SwiftUI

/// Keeps AppKit's native search/cancel controls and immediate filtering behavior.
struct MacFindSearchField: NSViewRepresentable {
    @Binding var query: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = String(localized: "Search Notes and Tasks")
        field.setAccessibilityLabel(String(localized: "Search Notes and Tasks"))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        DispatchQueue.main.async { [weak field] in
            guard let field else { return }
            field.window?.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.query = $query
        if field.stringValue != query {
            field.stringValue = query
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(query: $query)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var query: Binding<String>

        init(query: Binding<String>) {
            self.query = query
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            query.wrappedValue = field.stringValue
        }

        // The native cancel button sends an action, including when it clears text.
        @objc func searchChanged(_ field: NSSearchField) {
            query.wrappedValue = field.stringValue
        }
    }
}
