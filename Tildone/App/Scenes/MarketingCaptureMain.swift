#if MARKETING_CAPTURE
import AppKit

/// Separate entry point selected only by Scripts/build-marketing-preview.py.
/// The customer bootstrapper, app delegate, CloudKit and StoreKit never start.
@main
enum MarketingCaptureMain {
    @MainActor
    static func main() {
        guard #available(macOS 15, *),
              Bundle.main.bundleIdentifier == "studio.cuatro.tildone.marketing-preview" else {
            fatalError("Marketing capture requires its private bundle and macOS 15 or later.")
        }
        let locale = Bundle.main.infoDictionary?["MarketingLocale"] as? String ?? "en-US"
        guard ["en-US", "es-ES", "fr-FR", "zh-Hans"].contains(locale) else {
            fatalError("Unsupported marketing capture locale.")
        }
        // Only this private capture bundle's preferences are affected. Set the
        // language before AppKit, Foundation localization, or views are started.
        UserDefaults.standard.set([locale], forKey: "AppleLanguages")
        UserDefaults.standard.set(locale.replacingOccurrences(of: "-", with: "_"), forKey: "AppleLocale")
        setenv("TILDONE_UI_TESTING", "1", 1)
        let application = NSApplication.shared
        let director: NSApplicationDelegate
        if Bundle.main.infoDictionary?["MarketingStory"] as? String == "sync" {
            director = MarketingSyncCaptureDirector()
        } else if Bundle.main.infoDictionary?["MarketingStory"] as? String == "screenshot-5" {
            director = MarketingGatherCaptureDirector()
        } else if Bundle.main.infoDictionary?["MarketingStory"] as? String == "screenshot-6" {
            director = MarketingAppearanceCaptureDirector()
        } else {
            director = MarketingCaptureDirector()
        }
        application.delegate = director
        application.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appMenu = NSMenuItem()
        appMenu.submenu = NSMenu()
        appMenu.submenu?.addItem(withTitle: String(localized: "Quit Tildone Preview Studio"),
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(appMenu)
        application.mainMenu = menu
        withExtendedLifetime(director) { application.run() }
    }
}
#endif
