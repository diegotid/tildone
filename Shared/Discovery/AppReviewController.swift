import SwiftUI
import StoreKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// One coordinator for every note/window; no prompts in tests, previews or Debug.
@MainActor
final class AppReviewController {
    static let shared = AppReviewController()
    private var policy: AppReviewPolicy
    private var pending: Task<Void, Never>?
    private var requestReview: (() -> Void)?
    private var sessionStartedAt = Date()
    private var observers: [NSObjectProtocol] = []
    #if os(macOS)
    private var eventMonitor: Any?
    #endif

    private var enabled: Bool {
        #if DEBUG
        return false
        #else
        return !WhatsNewRelease.isIsolatedProcess
        #endif
    }

    private init() {
        policy = UserDefaults.standard.data(forKey: AppReviewPolicy.storageKey)
            .flatMap { try? JSONDecoder().decode(AppReviewPolicy.self, from: $0) } ?? AppReviewPolicy()
    }

    func start(requestReview: @escaping () -> Void) {
        guard enabled else { return }
        self.requestReview = requestReview
        recordActivity()
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        #if os(macOS)
        let active = NSApplication.didBecomeActiveNotification
        let inactive = NSApplication.didResignActiveNotification
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged]) { [weak self] event in
            self?.cancelPendingRequest()
            return event
        }
        #else
        let active = UIApplication.didBecomeActiveNotification
        let inactive = UIApplication.willResignActiveNotification
        observers.append(center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancelPendingRequest() }
        })
        #endif
        observers.append(center.addObserver(forName: active, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.sessionStartedAt = Date()
                self?.recordActivity()
            }
        })
        observers.append(center.addObserver(forName: inactive, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancelPendingRequest() }
        })
    }

    // Mac's coordinator is hidden. The key note supplies its own StoreKit
    // environment so the prompt belongs to the window the user is working in.
    func setPresenter(_ requestReview: @escaping () -> Void) {
        guard enabled else { return }
        self.requestReview = requestReview
    }

    func recordCompletion(_ id: UUID, completed: Bool) {
        guard enabled else { return }
        cancelPendingRequest()
        recordActivity()
        policy.recordCompletion(id, completed: completed)
        save()
        guard completed, policy.isEligible(at: Date(), version: version) else { return }
        // Leave time for completion animations and undo. Never retry a blocked
        // presentation on launch/resume: wait for another successful completion.
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, !Task.isCancelled,
                  Date().timeIntervalSince(self.sessionStartedAt) >= 60,
                  self.policy.isEligible(at: Date(), version: self.version),
                  self.canPresent, let requestReview = self.requestReview else { return }
            self.policy.recordRequest(at: Date(), version: self.version)
            self.save()
            requestReview()
            self.pending = nil
        }
    }

    func cancelPendingRequest() {
        pending?.cancel()
        pending = nil
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private func recordActivity() {
        policy.recordActivity(at: Date())
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(policy) {
            UserDefaults.standard.set(data, forKey: AppReviewPolicy.storageKey)
        }
    }

    private var canPresent: Bool {
        guard ProEntitlement.shared.requestedFeature == nil else { return false }
        #if os(macOS)
        guard NSApp.isActive, NSApp.modalWindow == nil,
              let window = NSApp.keyWindow, window.isVisible,
              window.identifier == nil, !(window is NSPanel),
              !(window.firstResponder is NSTextView),
              !NSApp.windows.contains(where: { $0.isVisible && $0.attachedSheet != nil }) else { return false }
        // Named app windows include What's New, About, settings and the paywall.
        return !NSApp.windows.contains { $0.isVisible && $0.identifier != nil && $0 !== window && $0.identifier?.rawValue != "tildone-desktop-coordinator" }
        #else
        guard UIApplication.shared.applicationState == .active,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let root = window.rootViewController,
              root.presentedViewController == nil else { return false }
        return !hasFirstResponder(in: window)
        #endif
    }

    #if !os(macOS)
    private func hasFirstResponder(in view: UIView) -> Bool {
        view.isFirstResponder || view.subviews.contains(where: hasFirstResponder)
    }
    #endif
}
