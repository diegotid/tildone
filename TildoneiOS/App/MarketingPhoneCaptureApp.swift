#if MARKETING_CAPTURE && targetEnvironment(simulator)
import SwiftUI
import TildoneDomain

/// Private simulator-only entry: real iPhone views with disposable data.
@main
struct MarketingPhoneCaptureApp: App {
    @StateObject private var fixture: MarketingPhoneCaptureFixture

    init() {
        precondition(Bundle.main.bundleIdentifier == "studio.cuatro.tildone.marketing-phone")
        let locale = Bundle.main.infoDictionary?["MarketingLocale"] as? String ?? "en-US"
        UserDefaults.standard.set([locale], forKey: "AppleLanguages")
        UserDefaults.standard.set(locale.replacingOccurrences(of: "-", with: "_"), forKey: "AppleLocale")
        // Select the shipping overview layout before its AppStorage is read.
        if Bundle.main.infoDictionary?["MarketingStory"] as? String == "screenshot-2" {
            UserDefaults.standard.set(NotesOverviewLayout.deck.rawValue, forKey: "notesOverviewLayout")
        }
        if let story = Bundle.main.infoDictionary?["MarketingStory"] as? String, story.hasPrefix("ios-") {
            let screenshotLayout = Bundle.main.infoDictionary?["MarketingOverviewLayout"] as? String ?? "grid"
            precondition(["grid", "deck"].contains(screenshotLayout))
            UserDefaults.standard.set(story == "ios-screenshot-3" ? screenshotLayout : "list", forKey: "notesOverviewLayout")
        }
        setenv("TILDONE_UI_TESTING", "1", 1)
        _fixture = StateObject(wrappedValue: MarketingPhoneCaptureFixture())
    }

    var body: some Scene {
        WindowGroup {
            NotesListView(appModel: fixture.model)
            .preferredColorScheme(.light)
            .autocorrectionDisabled(true)
            .environment(\.locale, Locale(identifier: Bundle.main.infoDictionary?["MarketingLocale"] as? String ?? "en-US"))
            .task { await fixture.prepare() }
        }
    }
}
#endif
