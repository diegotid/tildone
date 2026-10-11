import SwiftUI
import XCTest
@testable import Tildone

@MainActor
final class SyncProductQualificationTests: XCTestCase {
    func testPrivacyAboutUsesNativeLinkRendering() async throws {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        if let expected = ProcessInfo.processInfo.environment["TILDONE_EXPECTED_PRODUCT_LANGUAGE"] {
            XCTAssertEqual(language, expected)
        }
        let previousKey = NSApp.keyWindow
        defer { previousKey?.makeKey() }
        for appearance in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: About().environment(\.colorScheme, appearance))
            let window = NSWindow(
                contentRect: NSRect(x: -10000, y: -10000, width: Frame.aboutWindowWidth, height: Frame.aboutWindowHeight),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
            window.contentView = host
            window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            host.layoutSubtreeIfNeeded()
            try await Swift.Task.sleep(for: .milliseconds(100))
            host.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "privacy-about-native-\(language)-\(appearance)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

}
