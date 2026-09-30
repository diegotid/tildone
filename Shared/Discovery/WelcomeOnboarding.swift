import Foundation

enum WelcomeOnboarding {
    static let completedKey = "completedWelcomeOnboarding"

    static func shouldPresent(defaults: UserDefaults = .standard) -> Bool {
        guard defaults !== UserDefaults.standard || !WhatsNewRelease.isIsolatedProcess else { return false }
        return !defaults.bool(forKey: completedKey)
    }

    static func finish(defaults: UserDefaults = .standard) {
        guard defaults !== UserDefaults.standard || !WhatsNewRelease.isIsolatedProcess else { return }
        defaults.set(true, forKey: completedKey)
    }
}
