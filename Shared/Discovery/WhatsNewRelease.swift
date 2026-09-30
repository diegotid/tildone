import Foundation
import SwiftUI

/// Curated release content and its installation-local presentation policy.
/// Change the identifier when shipping a new set of highlights, independently
/// of build numbers. Discovery never creates notes or writes to a repository.
enum WhatsNewRelease {
    static let contentID = "connected-notes-2026"
    static let seenContentKey = "seenWhatsNewContent"
    static let suppressedVersionKey = "suppressedWhatsNewVersion"
    static let retiredPendingNoteKey = "pendingReleaseNoteVersion"
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? contentID
    }

    enum Step: Int, CaseIterable, Identifiable {
        case welcome, companion, everyday, expression, subtasks, desktop, focusPrivacy

        var id: Int { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .welcome: "Welcome to Tildone"
            case .companion: "Your notes can come with you"
            case .everyday: "Small improvements, every day"
            case .expression: "More ways to express an idea"
            case .subtasks: "Keep smaller steps together"
            case .desktop: "A calmer desktop"
            case .focusPrivacy: "Focus settings for each note"
            }
        }

        var detail: LocalizedStringKey {
            switch self {
            case .welcome: "Discover iPhone sync, everyday refinements, and new ways to shape your notes."
            case .companion:
                "Tildone is now on iPhone. Keep your notes, tasks, and progress together with iCloud using the same Apple Account. Work offline and sync when you reconnect."
            case .everyday:
                "Find notes, undo recent changes, and turn words in brackets into clear tags."
            case .expression:
                "Give one thought its own memo, or make important words stand out with text styling."
            case .subtasks:
                "Break a task into smaller steps, see their progress, and collapse them when you want a simpler view."
            case .desktop:
                "Gather notes in a corner and dim one note or all of them to soften desktop distractions."
            case .focusPrivacy:
                "Set each note to blur its task text or stay behind other windows, using the privacy choices you already know from Focus Filters."
            }
        }

        var features: [ProFeature] {
            switch self {
            case .welcome, .companion, .everyday: []
            case .expression: [.singleMemo, .textStyling]
            case .subtasks: [.subtasks]
            case .desktop: [.gathering, .dimming]
            case .focusPrivacy: [.blur, .background]
            }
        }

        var symbolName: String {
            switch self {
            case .welcome: "checklist"
            case .companion: "macbook.and.iphone"
            case .everyday: "paperplane"
            case .expression: "textformat"
            case .subtasks: "checklist"
            case .desktop: "lamp.desk"
            case .focusPrivacy: "moon.stars.fill"
            }
        }

        var indexDescription: LocalizedStringKey {
            switch self {
            case .welcome: "Discover iPhone sync, everyday refinements, and new ways to shape your notes."
            case .companion: "Keep notes and tasks in sync with iPhone."
            case .everyday: "Find notes, undo edits, and use bracket tags."
            case .expression: "Create a memo or style important text."
            case .subtasks: "Break tasks into smaller, manageable steps."
            case .desktop: "Gather notes, dim distractions, and protect privacy."
            case .focusPrivacy: "Choose per note when to blur text or stay behind other windows."
            }
        }
    }

    static var steps: [Step] {
        #if os(macOS)
        Step.allCases
        #else
        [.welcome, .everyday, .expression, .subtasks]
        #endif
    }

    static func shouldPresent(defaults: UserDefaults = .standard, contentID: String = contentID,
                              version: String = appVersion) -> Bool {
        guard defaults !== UserDefaults.standard || !isIsolatedProcess else { return false }
        // An old, undismissed update note must never bring its window back.
        defaults.removeObject(forKey: retiredPendingNoteKey)
        return defaults.string(forKey: seenContentKey) != contentID
            && defaults.string(forKey: suppressedVersionKey) != version
    }

    static func suppressUntilNextVersion(defaults: UserDefaults = .standard, version: String = appVersion) {
        guard defaults !== UserDefaults.standard || !isIsolatedProcess else { return }
        defaults.set(version, forKey: suppressedVersionKey)
        // An explicit deferral also takes effect after manually reopening a completed tour.
        defaults.removeObject(forKey: seenContentKey)
        defaults.removeObject(forKey: retiredPendingNoteKey)
    }

    static func acknowledge(defaults: UserDefaults = .standard, contentID: String = contentID) {
        guard defaults !== UserDefaults.standard || !isIsolatedProcess else { return }
        defaults.set(contentID, forKey: seenContentKey)
        defaults.removeObject(forKey: suppressedVersionKey)
        defaults.removeObject(forKey: retiredPendingNoteKey)
    }

    static var isIsolatedProcess: Bool {
        let process = ProcessInfo.processInfo
        return NSClassFromString("XCTestCase") != nil
            || process.arguments.contains("--tildone-ui-test")
            || process.environment["TILDONE_UI_TESTING"] == "1"
            || process.environment["TILDONE_TEST_USE_IN_MEMORY_LEGACY"] == "1"
            || process.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}
