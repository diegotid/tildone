import SwiftUI

struct TildoneiOSAboutView: View {
    private enum ProPresentation: String, Identifiable {
        case pro, restore
        var id: String { rawValue }
        var title: LocalizedStringKey {
            self == .restore ? "Restore Purchases" : "Tildone Pro"
        }
    }

    @State private var proPresentation: ProPresentation?
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
                    Text("© 2026 Diego Rivera")
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            }

            Section {
                Button("Tildone Pro") {
                    proPresentation = .pro
                }
                Button("Restore Purchases") {
                    proPresentation = .restore
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
        .sheet(item: $proPresentation) { presentation in
            NavigationStack {
                ProPaywallView(feature: nil, indexTitle: presentation.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Close") { proPresentation = nil }
                                .accessibilityIdentifier("about-pro-close")
                        }
                    }
            }
        }
    }
}
