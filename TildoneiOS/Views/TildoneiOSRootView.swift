//
//  TildoneiOSRootView.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import SwiftUI
import TildoneDomain
import TildonePersistence
import TildoneSync

struct TildoneiOSRootView: View {
    @ObservedObject var appModel: TildoneiOSApplicationModel
    @ObservedObject private var pro = ProEntitlement.shared
    @State private var showsWhatsNew = false
    @State private var checkedWhatsNew = false

    var body: some View {
        Group {
            if appModel.hasWorkspace || appModel.isResolvingWorkspace {
                NotesListView(appModel: appModel)
            } else {
                TildoneiOSWorkspaceStatus(appModel: appModel)
            }
        }
        .overlay {
            TildoneiOSUndoOverlay(presentation: appModel.undoPresentation) {
                try await appModel.undoLatestAction()
            }
        }
        .onAppear { presentWhatsNewIfReady() }
        .onChange(of: appModel.hasWorkspace) { _, _ in presentWhatsNewIfReady() }
        .sheet(isPresented: $showsWhatsNew) {
            WhatsNewView {
                showsWhatsNew = false
            }
        }
        .sheet(item: $pro.requestedFeature) { feature in
            ProPaywallView(feature: feature)
        }
    }
    private func presentWhatsNewIfReady() {
        guard appModel.hasWorkspace, !checkedWhatsNew, !WhatsNewRelease.isIsolatedProcess else { return }
        checkedWhatsNew = true
        showsWhatsNew = WhatsNewRelease.shouldPresent()
    }
}

private struct TildoneiOSWorkspaceStatus: View {
    let appModel: TildoneiOSApplicationModel
    @ObservedObject private var syncPresentation: TildoneiOSSyncPresentation

    init(appModel: TildoneiOSApplicationModel) {
        self.appModel = appModel
        _syncPresentation = ObservedObject(wrappedValue: appModel.syncPresentation)
    }

    var body: some View {
        WorkspaceStatusView(status: syncPresentation.status) {
            appModel.start()
        }
    }
}

#Preview("Notes") {
    let workspaceID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
    let weekendPlansID = NoteID(UUID(uuidString: "00000000-0000-0000-0000-000000000021")!)
    let groceriesID = NoteID(UUID(uuidString: "00000000-0000-0000-0000-000000000022")!)
    let model = TildoneiOSApplicationModel(
        repositoryFactory: { _ in
            try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceID)))
        },
        accountResolver: { CloudAccountSnapshot(state: .available, workspaceID: workspaceID) },
        synchronizationEnabled: false
    )

    TildoneiOSRootView(appModel: model)
        .task {
            guard (try? await model.openForTesting(workspaceID: workspaceID)) != nil,
                  (try? await model.createNote(title: "Weekend plans", id: weekendPlansID)) != nil,
                  let firstTask = try? await model.addTask(
                      noteID: weekendPlansID,
                      text: "Book the first appointment",
                      after: []
                  ),
                  let secondTask = try? await model.addTask(
                      noteID: weekendPlansID,
                      text: "Pick up flowers",
                      after: [firstTask]
                  ),
                  (try? await model.createNote(title: "Groceries", id: groceriesID)) != nil,
                  let groceryTask = try? await model.addTask(
                      noteID: groceriesID,
                      text: "Buy coffee",
                      after: []
                  ) else { return }

            try? await model.setCompletion(taskID: secondTask.id, completed: true)
            try? await model.setCompletion(taskID: groceryTask.id, completed: true)
        }
}
