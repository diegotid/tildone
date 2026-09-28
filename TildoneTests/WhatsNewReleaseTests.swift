import XCTest
import SwiftUI
import TipKit
@testable import Tildone

final class WhatsNewReleaseTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "WhatsNewReleaseTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testOldPendingReleaseNoteIsRetiredWithoutConsumingNewHighlights() {
        defaults.set("1.6.0", forKey: WhatsNewRelease.retiredPendingNoteKey)
        defaults.set("1.6.0", forKey: UpdateChecker.Local.knownVersionFlag)
        XCTAssertTrue(WhatsNewRelease.shouldPresent(defaults: defaults))
        XCTAssertNil(defaults.object(forKey: WhatsNewRelease.retiredPendingNoteKey))
        XCTAssertEqual(defaults.string(forKey: UpdateChecker.Local.knownVersionFlag), "1.6.0")
        // Merely checking or starting the flow must not mark it dismissed.
        XCTAssertTrue(WhatsNewRelease.shouldPresent(defaults: defaults))
    }

    func testAcknowledgmentSurvivesRelaunchAndNewContentCanPresent() {
        WhatsNewRelease.acknowledge(defaults: defaults)
        let reopenedDefaults = UserDefaults(suiteName: suiteName)!
        XCTAssertFalse(WhatsNewRelease.shouldPresent(defaults: reopenedDefaults))
        XCTAssertTrue(WhatsNewRelease.shouldPresent(defaults: reopenedDefaults, contentID: "next-release"))
        WhatsNewRelease.acknowledge(defaults: reopenedDefaults, contentID: "next-release")
        XCTAssertFalse(WhatsNewRelease.shouldPresent(defaults: reopenedDefaults, contentID: "next-release"))
    }

    func testSuppressionLastsUntilNextMarketingVersionWithoutAcknowledgingContent() {
        WhatsNewRelease.suppressUntilNextVersion(defaults: defaults, version: "1.7.0")
        XCTAssertNil(defaults.object(forKey: WhatsNewRelease.seenContentKey))
        let reopenedDefaults = UserDefaults(suiteName: suiteName)!
        XCTAssertFalse(WhatsNewRelease.shouldPresent(defaults: reopenedDefaults, version: "1.7.0"))
        XCTAssertFalse(WhatsNewRelease.shouldPresent(defaults: reopenedDefaults, contentID: "other-content", version: "1.7.0"))
        XCTAssertTrue(WhatsNewRelease.shouldPresent(defaults: reopenedDefaults, version: "1.7.1"))
        WhatsNewRelease.acknowledge(defaults: reopenedDefaults)
        XCTAssertNil(reopenedDefaults.object(forKey: WhatsNewRelease.suppressedVersionKey))
        XCTAssertFalse(WhatsNewRelease.shouldPresent(defaults: reopenedDefaults, version: "1.7.1"))
        XCTAssertTrue(WhatsNewRelease.shouldPresent(defaults: reopenedDefaults, contentID: "next-release", version: "1.7.1"))
        WhatsNewRelease.suppressUntilNextVersion(defaults: reopenedDefaults, version: "1.7.1")
        XCTAssertFalse(WhatsNewRelease.shouldPresent(defaults: reopenedDefaults, version: "1.7.1"))
        XCTAssertTrue(WhatsNewRelease.shouldPresent(defaults: reopenedDefaults, version: "1.7.2"))
    }

    func testClosingWithoutAnExplicitAcknowledgmentLeavesHighlightsEligible() {
        // Opening/checking does not mutate acknowledgment or suppression state.
        XCTAssertTrue(WhatsNewRelease.shouldPresent(defaults: defaults, version: "1.7.0"))
        XCTAssertTrue(WhatsNewRelease.shouldPresent(defaults: UserDefaults(suiteName: suiteName)!, version: "1.7.0"))
        XCTAssertNil(defaults.object(forKey: WhatsNewRelease.seenContentKey))
        XCTAssertNil(defaults.object(forKey: WhatsNewRelease.suppressedVersionKey))
    }

    func testDiscoveryStateIsInstallationLocal() {
        let otherName = "WhatsNewReleaseTests.other.\(UUID().uuidString)"
        let other = UserDefaults(suiteName: otherName)!
        defer { other.removePersistentDomain(forName: otherName) }
        WhatsNewRelease.acknowledge(defaults: defaults)
        XCTAssertTrue(WhatsNewRelease.shouldPresent(defaults: other))
    }

    func testHostedTestsAndPreviewsCannotConsumeLiveDiscoveryState() {
        let seen = UserDefaults.standard.object(forKey: WhatsNewRelease.seenContentKey) as? String
        let pending = UserDefaults.standard.object(forKey: WhatsNewRelease.retiredPendingNoteKey) as? String
        let suppressed = UserDefaults.standard.object(forKey: WhatsNewRelease.suppressedVersionKey) as? String
        XCTAssertFalse(WhatsNewRelease.shouldPresent())
        WhatsNewRelease.acknowledge()
        WhatsNewRelease.suppressUntilNextVersion()
        XCTAssertEqual(UserDefaults.standard.object(forKey: WhatsNewRelease.seenContentKey) as? String, seen)
        XCTAssertEqual(UserDefaults.standard.object(forKey: WhatsNewRelease.retiredPendingNoteKey) as? String, pending)
        XCTAssertEqual(UserDefaults.standard.object(forKey: WhatsNewRelease.suppressedVersionKey) as? String, suppressed)
    }

    @MainActor
    func testMenuBarOnlyUsersHaveAnActionToReopenHighlights() throws {
        let controller = MenuBarController.shared
        let menu = controller.makeMenu()
        let item = try XCTUnwrap(menu.item(withTitle: String(localized: "What’s New…")))
        XCTAssertTrue(item.isEnabled)
        XCTAssertTrue((item.target as? MenuBarController) === controller)
        XCTAssertTrue(item.target?.responds(to: try XCTUnwrap(item.action)) == true)
    }

    func testMacHighlightsCoverEveryProFeatureAfterFreeImprovements() {
        XCTAssertEqual(WhatsNewRelease.steps.first, .everyday)
        XCTAssertTrue(WhatsNewRelease.Step.everyday.features.isEmpty)
        XCTAssertEqual(Set(WhatsNewRelease.steps.flatMap(\.features)), Set(ProFeature.catalog))
    }

    func testEverydayPreviewUsesColorAndCompletedOrderingWithoutPersisting() {
        let original = WhatsNewPreviewContent(noteColor: .pink, movesCompletedTasksToEnd: false).content
        let reordered = WhatsNewPreviewContent(noteColor: .blue, movesCompletedTasksToEnd: true).content
        XCTAssertEqual(original.note.color, .pink)
        XCTAssertEqual(reordered.note.color, .blue)
        XCTAssertTrue(original.tasks[1].isCompleted)
        XCTAssertTrue(reordered.tasks.last!.isCompleted)
        XCTAssertEqual(Set(original.tasks.map(\.text)), Set(reordered.tasks.map(\.text)))
        XCTAssertEqual(reordered.tasks.map(\.orderToken), reordered.tasks.map(\.orderToken).sorted())
        XCTAssertTrue(reordered.tasks.allSatisfy { $0.noteID == reordered.note.id })
    }

    @MainActor
    func testHierarchyHintRendersComputedTextColorInNativeTipView() async throws {
        let tipStore = FileManager.default.temporaryDirectory
            .appendingPathComponent("HierarchyHintTests-\(UUID().uuidString)", isDirectory: true)
        try Tips.configure([.datastoreLocation(.url(tipStore)), .displayFrequency(.immediate)])
        Tips.showAllTipsForTesting()
        defer {
            Tips.hideAllTipsForTesting()
            try? FileManager.default.removeItem(at: tipStore)
        }

        for appearance in [ColorScheme.light, .dark] {
            for opacity in [0.2, 0.7, 1.0] {
                let usesLightText = NoteContentForeground.usesLightText(
                    colorScheme: appearance, backgroundOpacity: opacity
                )
                let foreground = NoteContentForeground.color(
                    colorScheme: appearance, backgroundOpacity: opacity
                )
                let view = TipView(FeatureDiscoveryTip(kind: .subtasks, contentColor: foreground))
                    .tipBackground(Color.clear)
                    .environment(\.colorScheme, usesLightText ? .dark : .light)
                    .tint(foreground)
                    .frame(width: 420, height: 130)
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 420, height: 130),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.orderFront(nil)
                defer { window.close() }
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                var darkPixels = 0
                var lightPixels = 0
                // Wait for TipKit's asynchronous first presentation, with a bounded deadline.
                for _ in 0..<20 {
                    try await Task.sleep(for: .milliseconds(100))
                    host.layoutSubtreeIfNeeded()
                    host.displayIfNeeded()
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    darkPixels = 0
                    lightPixels = 0
                    for y in 0..<bitmap.pixelsHigh {
                        for x in 0..<bitmap.pixelsWide {
                            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                                  color.alphaComponent > 0.8 else { continue }
                            let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                            if channels.allSatisfy({ $0 < 0.2 }) { darkPixels += 1 }
                            if channels.allSatisfy({ $0 > 0.75 }) { lightPixels += 1 }
                        }
                    }
                    if darkPixels + lightPixels > 100 { break }
                }
                XCTAssertGreaterThan(usesLightText ? lightPixels : darkPixels,
                                     usesLightText ? darkPixels : lightPixels,
                                     "Hierarchy hint must use computed text color for \(appearance), opacity \(opacity)")
                let image = NSImage(size: host.bounds.size)
                image.addRepresentation(bitmap)
                let attachment = XCTAttachment(image: image)
                attachment.name = "hierarchy-hint-\(appearance)-opacity-\(opacity)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    @MainActor
    func testEverydayPreviewRendersRealRowsInEverySupportedLanguage() throws {
        let english = WhatsNewPreviewContent(noteColor: .pink, movesCompletedTasksToEnd: true,
                                             locale: Locale(identifier: "en")).content
        for language in ["en", "es", "fr", "zh-Hans"] {
            let locale = Locale(identifier: language)
            let content = WhatsNewPreviewContent(noteColor: .pink, movesCompletedTasksToEnd: true,
                                                locale: locale).content
            if language != "en" { XCTAssertNotEqual(content.tasks.first?.text, english.tasks.first?.text) }
            for appearance in [ColorScheme.light, .dark] {
                let image = try XCTUnwrap(MacProPreviewNote.rasterImage(
                    content: content, locale: locale, colorScheme: appearance,
                    backgroundOpacity: 0.25, noteColor: .pink, fontSize: 15, truncation: .multiple
                ))
                XCTAssertEqual(image.size, CGSize(width: 216, height: 262))
                XCTAssertGreaterThan(try XCTUnwrap(image.tiffRepresentation).count, 2_000)
                let attachment = XCTAttachment(image: image)
                attachment.name = "everyday-\(language)-\(appearance)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
