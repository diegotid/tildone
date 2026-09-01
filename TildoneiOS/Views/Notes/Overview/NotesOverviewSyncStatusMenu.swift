import SwiftUI
import TildoneDomain

struct TildoneiOSSyncStatusMenu: View {
    let appModel: TildoneiOSApplicationModel
    @ObservedObject private var presentation: TildoneiOSSyncPresentation

    init(appModel: TildoneiOSApplicationModel) {
        self.appModel = appModel
        _presentation = ObservedObject(wrappedValue: appModel.syncPresentation)
    }

    var body: some View {
        SyncStatusMenu(
            status: presentation.status,
            transportState: presentation.transportState,
            canControlTransport: appModel.canControlTransport,
            syncNow: appModel.syncNow,
            pause: appModel.pauseTransport,
            resume: appModel.resumeTransport
        )
    }
}
