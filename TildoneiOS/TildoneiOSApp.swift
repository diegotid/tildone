//
//  TildoneiOSApp.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
import CloudKit
import SwiftUI
import TildonePersistence
import TildoneSync
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

@MainActor
final class TildoneiOSSyncBootstrapper: ObservableObject {
    @Published private(set) var syncStatus: SyncStatus = .disabled

    private var coordinator: TildoneSyncCoordinator?
    private var repository: TildoneRepository?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        guard Self.featureEnabled, !Self.isTestProcess else { return }

        Swift.Task {
            let container = CKContainer(identifier: TildoneCloudSchema.containerIdentifier)
            let account = await CloudAccountResolver().resolve(container: container)
            guard account.state == .available, let workspaceID = account.workspaceID else {
                syncStatus = Self.status(for: account.state)
                return
            }

            do {
                let repository = try TildoneRepository(descriptor: .persistent(
                    baseDirectory: try Self.applicationSupportDirectory(),
                    workspace: .account(workspaceID)
                ))
                let coordinator = try await TildoneSyncCoordinator(
                    repository: repository,
                    container: container,
                    onAccountChange: { [weak self] change in
                        guard change.requiresWorkspaceInvalidation else { return }
                        Swift.Task { @MainActor in
                            // Drop all handles immediately. A subsequently signed-in
                            // account can only reopen its independently keyed workspace.
                            self?.repository = nil
                            self?.coordinator = nil
                            self?.syncStatus = SyncStatus(
                                availability: .accountChanged,
                                activity: .attentionNeeded,
                                issue: .accountChanged
                            )
                        }
                    }
                )
                self.repository = repository
                self.coordinator = coordinator
                Swift.Task { [weak self] in
                    for await status in await coordinator.statusModel.updates() {
                        self?.syncStatus = status
                    }
                }
                await coordinator.start()
            } catch {
                syncStatus = SyncStatus(
                    availability: .temporarilyUnavailable,
                    activity: .attentionNeeded,
                    issue: .unknown
                )
            }
        }
    }

    static var featureEnabled: Bool {
#if DEBUG
        ProcessInfo.processInfo.environment["TILDONE_ENABLE_CLOUDKIT_SYNC"] == "1"
#else
        false
#endif
    }

    private static var isTestProcess: Bool {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil ||
            environment["XCTestBundlePath"] != nil ||
            environment["XCInjectBundleInto"] != nil ||
            NSClassFromString("XCTestCase") != nil
#else
        false
#endif
    }

    private static func applicationSupportDirectory() throws -> URL {
        guard let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PersistenceError.invalidStoreLocation
        }
        return directory
    }

    private static func status(for account: CloudAccountState) -> SyncStatus {
        switch account {
        case .available:
            SyncStatus(availability: .available, activity: .idle)
        case .noAccount:
            SyncStatus(availability: .noAccount, activity: .idle)
        case .restricted:
            SyncStatus(availability: .restricted, activity: .attentionNeeded, issue: .permission)
        case .temporarilyUnavailable, .couldNotDetermine:
            SyncStatus(
                availability: .temporarilyUnavailable,
                activity: .offline,
                issue: .service
            )
        }
    }
}

@main
struct TildoneiOSApp: App {
    @UIApplicationDelegateAdaptor(TildoneiOSAppDelegate.self) private var appDelegate
    @StateObject private var syncBootstrapper = TildoneiOSSyncBootstrapper()

    var body: some Scene {
        WindowGroup {
            TildoneiOSRootView()
                .task { syncBootstrapper.start() }
        }
    }
}
