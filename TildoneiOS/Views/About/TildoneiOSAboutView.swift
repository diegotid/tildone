import SwiftUI

struct TildoneiOSAboutView: View {
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
                NavigationLink("Font Attributions") {
                    FontAttributionsView()
                }
            }
        }
        .navigationTitle("About Tildone")
        .navigationBarTitleDisplayMode(.inline)
    }
}
