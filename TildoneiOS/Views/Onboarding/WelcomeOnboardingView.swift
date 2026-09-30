import SwiftUI

struct WelcomeOnboardingView: View {
    let close: () -> Void
    @State private var step = 0
    @State private var showsMacDownload = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Welcome to Tildone").font(.headline).foregroundStyle(.secondary)
                    Text(step == 0 ? LocalizedStringKey("Tildone, now in your pocket") : LocalizedStringKey("Your notes, across your devices"))
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("welcome-title")
                    Text(step == 0
                         ? LocalizedStringKey("Capture ideas and manage tasks on iPhone. A companion to Tildone for Mac, it also works on its own. No Mac required.")
                         : LocalizedStringKey("Keep your notes, tasks, and progress together with iCloud. Use the same Apple Account on iPhone and Mac. Work offline and sync when you reconnect."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if step == 0 {
                        WhatsNewEverydayPreview()
                    } else {
                        CompanionPreview()
                        Button("Get Tildone for Mac") { showsMacDownload = true }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("welcome-get-mac")
                        Text("Desktop notes keep your tasks in sight while you work.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(24)
            }
            .id(step)
            Divider()
            HStack(spacing: 12) {
                Button("Skip", action: finish).accessibilityIdentifier("welcome-skip")
                Spacer()
                if step > 0 {
                    Button("Back") { navigate(to: 0) }.accessibilityIdentifier("welcome-back")
                }
                Button(step == 0 ? LocalizedStringKey("Next") : LocalizedStringKey("Start using Tildone")) {
                    if step == 0 { navigate(to: 1) } else { finish() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(step == 0 ? "welcome-next" : "welcome-start")
            }
            .padding(24)
        }
        .sheet(isPresented: $showsMacDownload) { GetTildoneForMacView() }
    }

    private func finish() {
        WelcomeOnboarding.finish()
        close()
    }

    private func navigate(to step: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { self.step = step }
    }
}
