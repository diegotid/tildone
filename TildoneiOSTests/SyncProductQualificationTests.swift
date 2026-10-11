import SwiftUI
import UIKit
import XCTest
import TildoneSync
@testable import Tildone

@MainActor
final class SyncProductQualificationTests: XCTestCase {
    func testRecoveryViewsAtNarrowWidthAndLargestDynamicType() async throws {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        if let expected = ProcessInfo.processInfo.environment["TILDONE_EXPECTED_PRODUCT_LANGUAGE"] {
            XCTAssertEqual(language, expected, "The hosted app must actually use the requested localization")
            if expected != "en" {
                XCTAssertNotEqual(SyncStatusPresentation.title(for: .init(
                    availability: .zoneResetRequired, activity: .attentionNeeded
                )), "Sync needs attention")
            }
        }
        for appearance in [ColorScheme.light, .dark] {
            for size in [DynamicTypeSize.large, .accessibility3, .accessibility5] {
                for availability in [SyncAvailability.zoneResetRequired, .incompatibleRemoteData, .accountChanged] {
                    let status = SyncStatus(availability: availability, activity: .attentionNeeded)
                    let host = UIHostingController(rootView: WorkspaceStatusView(status: status, retry: {
                        XCTFail("Attention states cannot offer a reset or retry action")
                    }).environment(\.colorScheme, appearance).environment(\.dynamicTypeSize, size))
                    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap {
                        $0 as? UIWindowScene
                    }.first)
                    let window = UIWindow(windowScene: scene)
                    window.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
                    window.rootViewController = host
                    window.isHidden = false
                    defer { window.isHidden = true; window.rootViewController = nil }
                    host.view.frame = window.bounds
                    host.view.backgroundColor = appearance == .dark ? .black : .white
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    try await Swift.Task.sleep(for: .milliseconds(100))
                    host.view.layoutIfNeeded()
                    func scrollViews(in view: UIView) -> [UIScrollView] {
                        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
                    }
                    let scroll = try XCTUnwrap(scrollViews(in: host.view).first,
                                               "Recovery guidance must be scrollable when text exceeds the screen")
                    let visibleHeight = scroll.bounds.height - scroll.adjustedContentInset.top - scroll.adjustedContentInset.bottom
                    XCTAssertGreaterThanOrEqual(scroll.contentSize.height, visibleHeight - 1)
                    if size == .accessibility5, language == "en" {
                        XCTAssertGreaterThan(scroll.contentSize.height, visibleHeight,
                                             "The full largest-text guidance must grow beyond the viewport")
                    }
                    print("SyncProductScroll language=\(language) state=\(availability.rawValue) size=\(size) viewport=\(visibleHeight) content=\(scroll.contentSize.height)")
                    let renderer = UIGraphicsImageRenderer(size: host.view.bounds.size)
                    func attach(_ position: String) {
                        let image = renderer.image { _ in
                            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                        }
                        let attachment = XCTAttachment(image: image)
                        attachment.name = "\(availability.rawValue)-\(language)-\(appearance)-\(size)-\(position)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                    attach("top")
                    if scroll.contentSize.height > visibleHeight + 1 {
                        scroll.setContentOffset(CGPoint(
                            x: 0, y: scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
                        ), animated: false)
                        try await Swift.Task.sleep(for: .milliseconds(20))
                        host.view.layoutIfNeeded()
                        attach("bottom")
                    }
                }
            }
        }
        print("SyncProductRender language=\(language) cases=18")
    }
}
