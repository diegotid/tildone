//
//  TildoneiOSAppDelegate.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import UIKit
import Combine

enum HomeQuickAction: String {
    case newNote = "studio.cuatro.tildone.new-note"
    case search = "studio.cuatro.tildone.search"
}

@MainActor
final class HomeQuickActionRouter: ObservableObject {
    static let shared = HomeQuickActionRouter()
    @Published var pending: HomeQuickAction?

    func receive(_ item: UIApplicationShortcutItem) -> Bool {
        guard let action = HomeQuickAction(rawValue: item.type) else { return false }
        pending = action
        return true
    }
}

final class TildoneiOSSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            _ = HomeQuickActionRouter.shared.receive(item)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(HomeQuickActionRouter.shared.receive(shortcutItem))
    }
}

final class TildoneiOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.applicationSupportsShakeToEdit = true
        application.shortcutItems = [
            UIApplicationShortcutItem(type: HomeQuickAction.newNote.rawValue, localizedTitle: NSLocalizedString("New Note", comment: "Home Screen quick action"), localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "plus")),
            UIApplicationShortcutItem(type: HomeQuickAction.search.rawValue, localizedTitle: NSLocalizedString("Search", comment: "Home Screen quick action"), localizedSubtitle: nil, icon: UIApplicationShortcutIcon(systemImageName: "magnifyingglass"))
        ]
        if TildoneiOSSyncBootstrapper.featureEnabled {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = TildoneiOSSceneDelegate.self
        return configuration
    }

}
