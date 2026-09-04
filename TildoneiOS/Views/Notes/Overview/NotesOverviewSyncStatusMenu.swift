import SwiftUI
import TildoneDomain

struct TildoneiOSSyncStatusMenu: View {
    let appModel: TildoneiOSApplicationModel
    let showsLaunchProgress: Bool
    @ObservedObject private var presentation: TildoneiOSSyncPresentation

    init(appModel: TildoneiOSApplicationModel, showsLaunchProgress: Bool = false) {
        self.appModel = appModel
        self.showsLaunchProgress = showsLaunchProgress
        _presentation = ObservedObject(wrappedValue: appModel.syncPresentation)
    }

    var body: some View {
        SyncStatusMenu(
            status: presentation.status,
            transportState: presentation.transportState,
            canControlTransport: appModel.canControlTransport,
            canOfferCloudAdoption: appModel.canOfferCloudAdoption,
            syncNow: appModel.syncNow,
            pause: appModel.pauseTransport,
            resume: appModel.resumeTransport,
            offerCloudAdoption: appModel.offerCloudAdoption
        )
        .overlay(alignment: .bottomTrailing) {
            if showsLaunchProgress {
                ProgressView()
                    .controlSize(.mini)
                    .offset(x: 5, y: 5)
                    .accessibilityHidden(true)
            }
        }
    }
}
