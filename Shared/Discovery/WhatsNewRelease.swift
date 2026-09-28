import Foundation
import SwiftUI

/// Curated release content and its installation-local presentation policy.
/// Change the identifier when shipping a new set of highlights, independently
/// of build numbers. Discovery never creates notes or writes to a repository.
enum WhatsNewRelease {
    static let contentID = "expanded-notes-2026"
    static let seenContentKey = "seenWhatsNewContent"
    static let suppressedVersionKey = "suppressedWhatsNewVersion"
    static let retiredPendingNoteKey = "pendingReleaseNoteVersion"
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? contentID
    }

    enum Step: Int, CaseIterable, Identifiable {
        case everyday, expression, subtasks, desktop

        var id: Int { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .everyday: "Small improvements, every day"
            case .expression: "More ways to express an idea"
            case .subtasks: "Keep smaller steps together"
            case .desktop: "A calmer desktop"
            }
        }

        var detail: LocalizedStringKey {
            switch self {
            case .everyday:
                "Find notes, undo recent changes, and turn words in brackets into clear tags. These improvements are available to everyone."
            case .expression:
                "Give one thought its own memo, or make important words stand out with text styling."
            case .subtasks:
                "Break a task into smaller steps, see their progress, and collapse them when you want a simpler view."
            case .desktop:
                "Gather notes, dim distractions, and choose when your notes stay behind other windows or keep their text private."
            }
        }

        var features: [ProFeature] {
            switch self {
            case .everyday: []
            case .expression: [.singleMemo, .textStyling]
            case .subtasks: [.subtasks]
            case .desktop: [.gathering, .dimming, .blur, .background]
            }
        }
    }

    static var steps: [Step] {
        #if os(macOS)
        Step.allCases
        #else
        [.everyday, .expression, .subtasks]
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
