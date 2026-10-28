import Foundation
#if os(macOS)
import AppKit
#endif

enum CompanionAppLink {
    static let writeReview = appStore.appending(queryItems: [URLQueryItem(name: "action", value: "write-review")])

    #if os(macOS)
    @discardableResult
    static func copyToPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(appStore.absoluteString, forType: .string)
    }
    #endif

    // One App Store record contains the native Mac and iPhone apps.
    static let appStore = URL(string: "https://apps.apple.com/app/id6473126292")!
}
