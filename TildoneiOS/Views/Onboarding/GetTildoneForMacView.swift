import SwiftUI

struct GetTildoneForMacView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GeometryReader { geometry in
                        CompanionPreview(showsPhone: false)
                            .scaleEffect(min(1, geometry.size.width / 356))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .aspectRatio(356.0 / 320.0, contentMode: .fit)
                    Text("A little space on your desktop")
                        .font(.title.bold()).fixedSize(horizontal: false, vertical: true)
                    Text("Keep tasks visible in desktop notes on your Mac, and take them with you on iPhone. Share the download link to your Mac to get started.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ShareLink(item: CompanionAppLink.appStore, subject: Text("Tildone for Mac")) {
                        Label("Share download link", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("get-mac-share")
                    Link("Open download page", destination: CompanionAppLink.appStore)
                        .accessibilityIdentifier("get-mac-download")
                }
                .padding(24)
            }
            .navigationTitle("Tildone for Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }.accessibilityIdentifier("get-mac-close")
                }
            }
        }
    }
}
