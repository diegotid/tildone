import SwiftUI

struct TildoneiOSAboutView: View {
    @State private var showsPro = false
    @State private var showsWhatsNew = false
    private var version: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Text("Tildone")
                        .font(.largeTitle.bold())
                    if let version {
                        Text("Version \(version)")
                            .foregroundStyle(.secondary)
                    }
                    Text("© 2023 Diego Rivera")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }

            Section {
                Button("Tildone Pro") { showsPro = true }
                Button("Restore Purchases") {
                    showsPro = true
                    Task { await ProEntitlement.shared.restore() }
                }
            }

            Section {
                Button("What’s New") { showsWhatsNew = true }
                NavigationLink("Font Attributions") {
                    FontAttributionsView()
                }
            }
        }
        .navigationTitle("About Tildone")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsWhatsNew) {
            WhatsNewView {
                showsWhatsNew = false
            }
        }
        .sheet(isPresented: $showsPro) {
            ProPaywallView(feature: nil)
        }
    }
}
