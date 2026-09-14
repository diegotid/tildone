import SwiftUI
import TildoneDomain

struct TildoneiOSSyncStatusMenu: View {
    let appModel: TildoneiOSApplicationModel
    let showsLaunchProgress: Bool
    let showAbout: () -> Void
    @ObservedObject private var presentation: TildoneiOSSyncPresentation

    init(
        appModel: TildoneiOSApplicationModel,
        showsLaunchProgress: Bool = false,
        showAbout: @escaping () -> Void
    ) {
        self.appModel = appModel
        self.showsLaunchProgress = showsLaunchProgress
        self.showAbout = showAbout
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
            offerCloudAdoption: appModel.offerCloudAdoption,
            showAbout: showAbout,
            animatesSyncSymbol: showsLaunchProgress
        )
    }
}
