//
//  TildoneiOSAppDelegate.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import UIKit

final class TildoneiOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if TildoneiOSSyncBootstrapper.featureEnabled {
            application.registerForRemoteNotifications()
        }
        return true
    }
}
