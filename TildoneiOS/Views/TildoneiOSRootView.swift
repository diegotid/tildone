//
//  TildoneiOSRootView.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import SwiftUI
import TildonePersistence
import TildoneSync

struct TildoneiOSRootView: View {
    @ObservedObject var appModel: TildoneiOSApplicationModel

    var body: some View {
        Group {
            if appModel.hasWorkspace {
                NotesListView(appModel: appModel)
            } else if appModel.isResolvingWorkspace {
                ProgressView("Opening Tildone…")
            } else {
                WorkspaceStatusView(status: appModel.syncStatus) {
                    appModel.start()
                }
            }
        }
    }
}

#Preview {
    TildoneiOSRootView(appModel: TildoneiOSApplicationModel(
        repositoryFactory: { _ in try TildoneRepository(descriptor: .inMemory(workspace: .account(UUID()))) },
        accountResolver: { CloudAccountSnapshot(state: .noAccount, workspaceID: nil) }
    ))
}
