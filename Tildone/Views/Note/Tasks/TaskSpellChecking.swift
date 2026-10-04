import AppKit

enum TaskSpellChecking {
    static let storageKey = "taskSpellCheckingEnabled"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? true
    }

    static func apply(_ isEnabled: Bool, to editor: NSTextView) {
        guard editor.isContinuousSpellCheckingEnabled != isEnabled else { return }
        editor.isContinuousSpellCheckingEnabled = isEnabled
        if isEnabled {
            editor.checkTextInDocument(nil)
        } else {
            editor.layoutManager?.removeTemporaryAttribute(
                .spellingState,
                forCharacterRange: NSRange(location: 0, length: editor.textStorage?.length ?? 0)
            )
            editor.needsDisplay = true
        }
    }
}
