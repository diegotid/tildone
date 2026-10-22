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
        setenv("TILDONE_UI_TESTING", "1", 1)
        _fixture = StateObject(wrappedValue: MarketingPhoneCaptureFixture())
    }

    var body: some Scene {
        WindowGroup {
            NotesListView(appModel: fixture.model)
            .preferredColorScheme(.light)
            .environment(\.locale, Locale(identifier: Bundle.main.infoDictionary?["MarketingLocale"] as? String ?? "en-US"))
            .task { await fixture.prepare() }
        }
    }
}
#endif
