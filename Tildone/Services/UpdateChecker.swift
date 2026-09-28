import Foundation

/// The legacy version key remains available for existing-installation detection.
/// Release discovery is now a curated scene, never a system note or user data.
struct UpdateChecker {
    static func shouldPresentWhatsNew() -> Bool {
        guard !WhatsNewRelease.isIsolatedProcess else { return false }
        return WhatsNewRelease.shouldPresent()
    }

    enum Local {
        static let knownVersionFlag = "knownAppVersion"
    }
}
