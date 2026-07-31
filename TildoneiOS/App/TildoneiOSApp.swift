//
//  TildoneiOSApp.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
import SwiftUI
import TildonePersistence
import TildoneSync

@main
struct TildoneiOSApp: App {
    @UIApplicationDelegateAdaptor(TildoneiOSAppDelegate.self) private var appDelegate
    @StateObject private var appModel: TildoneiOSApplicationModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if ProcessInfo.processInfo.environment["TILDONE_UI_TESTING"] == "1" {
            let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000009")!
            _appModel = StateObject(wrappedValue: TildoneiOSApplicationModel(
                repositoryFactory: { _ in
                    try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceID)))
                },
                accountResolver: { CloudAccountSnapshot(state: .available, workspaceID: workspaceID) },
                synchronizationEnabled: false
            ))
        } else {
            _appModel = StateObject(wrappedValue: TildoneiOSApplicationModel())
        }
    }

    var body: some Scene {
        WindowGroup {
            TildoneiOSRootView(appModel: appModel)
                .task { appModel.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { appModel.applicationBecameActive() }
                }
        }
    }
}
