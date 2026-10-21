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
        setenv("TILDONE_UI_TESTING", "1", 1)
        let application = NSApplication.shared
        let director = MarketingCaptureDirector()
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
