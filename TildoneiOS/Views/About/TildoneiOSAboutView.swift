import SwiftUI

struct TildoneiOSAboutView: View {
    @State private var showsPro = false
    @State private var showsWelcome = false
    @State private var showsMacDownload = false
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
                Button("Welcome to Tildone") { showsWelcome = true }
                Button("Get Tildone for Mac") { showsMacDownload = true }
                NavigationLink("Font Attributions") {
                    FontAttributionsView()
                }
            }
        }
        .navigationTitle("About Tildone")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsWelcome, onDismiss: { WelcomeOnboarding.finish() }) {
            WelcomeOnboardingView {
                showsWelcome = false
            }
        }
        .sheet(isPresented: $showsMacDownload) { GetTildoneForMacView() }
        .sheet(isPresented: $showsPro) {
            ProPaywallView(feature: nil)
        }
    }
}
