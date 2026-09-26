import SwiftUI

extension ProFeature {
    static let catalog: [ProFeature] = [.singleMemo, .textStyling, .subtasks, .blur, .background, .dimming, .gathering]

    var isMacOnly: Bool {
        switch self {
        case .blur, .background, .focusPrivacy, .dimming, .gathering: true
        case .singleMemo, .textStyling, .subtasks: false
        }
    }

    /// Resetting Focus defaults concerns both settings; each gets its own example.
    var previewFeatures: [ProFeature] {
        self == .focusPrivacy ? [.blur, .background] : [self]
    }

    var indexCaption: LocalizedStringKey {
        switch self {
        case .singleMemo: "One note, one focused message."
        case .textStyling: "Emphasis, colors, highlights, and fonts."
        case .subtasks: "Organize tasks into smaller steps."
        case .blur: "Reveal private text on hover."
        case .background: "Keep notes behind other windows."
        case .focusPrivacy: "Control note visibility and privacy."
        case .dimming: "Make one or all notes less visible."
        case .gathering: "Gather in a corner, then restore."
        }
    }

    var outcome: LocalizedStringKey {
        switch self {
        case .singleMemo:
            "Turn a checklist into one focused memo, with your message filling the note."
        case .textStyling:
            "Make important words stand out with emphasis, text colors, highlights, and memo fonts."
        case .subtasks:
            "Break a task into smaller steps and keep them together in a clear hierarchy."
        case .blur:
            "Keep a Mac note’s text private by blurring it until you hover over the note."
        case .background:
            "Let other windows stay in front of a Mac note while keeping it on your desktop."
        case .focusPrivacy:
            "Choose when each Mac note blurs its text or stays behind other windows."
        case .dimming:
            "Lower the opacity of one or all Mac notes to keep your desktop less distracting."
        case .gathering:
            "Bring Mac notes together in a corner, then return them to their previous positions."
        }
    }
}
