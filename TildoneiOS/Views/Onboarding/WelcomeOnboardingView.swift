import SwiftUI
import TildoneDomain

struct WelcomeOnboardingView: View {
    let close: () -> Void
    @State private var step = 0
    @State private var showsMacDownload = false
    @State private var selectedFeature: ProFeature?
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var previewHeight: CGFloat = 240

    private var title: LocalizedStringKey {
        switch step {
        case 0: "Tildone, now in your pocket"
        case 1: "Your notes, across your devices"
        default: "Make room for more ideas"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Welcome to Tildone").font(.headline).foregroundStyle(.secondary)
                        Text(title)
                            .font(.largeTitle.bold())
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("welcome-title")
                        page(availableWidth: geometry.size.width)
                    }
                    .padding(24)
                    .frame(width: geometry.size.width, alignment: .leading)
                }
                .id(step)
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Button("Skip", action: finish).accessibilityIdentifier("welcome-skip")
                    Spacer(minLength: 12)
                    navigationButtons
                }
                VStack(spacing: 12) {
                    navigationButtons
                    Button("Skip", action: finish).accessibilityIdentifier("welcome-skip")
                }
            }
            .padding(24)
        }
        .sheet(isPresented: $showsMacDownload) { GetTildoneForMacView() }
        .sheet(item: $selectedFeature) { feature in
            NavigationStack {
                ProPaywallView(feature: feature)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedFeature = nil }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private func page(availableWidth: CGFloat) -> some View {
        switch step {
        case 0:
            Text("Capture ideas and manage tasks on iPhone. A companion to Tildone for Mac.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            notePreview(availableWidth: availableWidth)
                .padding(.horizontal, -24)
        case 1:
            Text("Keep your notes, tasks, and progress together with iCloud. Use the same Apple Account on iPhone and Mac. Work offline and sync when you reconnect.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 24) {
                Image(systemName: "desktopcomputer").font(.system(size: 68))
                Image(systemName: "icloud").foregroundStyle(.secondary)
                Image(systemName: "iphone").font(.system(size: 68))
            }
            .font(.largeTitle)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .accessibilityHidden(true)
            macDownloadButton
            Text("Desktop notes keep your tasks in sight while you work.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        default:
            Text("Discover more ways to shape your notes on iPhone and Mac with Tildone Pro.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach([ProFeature.singleMemo, .textStyling, .subtasks]) { feature in
                Button {
                    selectedFeature = feature
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(feature.title).font(.headline)
                            Spacer(minLength: 8)
                            Text("PRO")
                                .font(.caption.bold())
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(.tint.opacity(0.12), in: Capsule())
                        }
                        Text(feature.indexCaption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Label("See it in action", systemImage: "chevron.right")
                            .font(.callout)
                            .foregroundStyle(.tint)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("welcome-pro-\(feature.rawValue)")
            }
        }
    }

    private func notePreview(availableWidth: CGFloat) -> some View {
        let front = WhatsNewPreviewContent(noteColor: .yellow, movesCompletedTasksToEnd: false, locale: locale).content
        let back = ProPreviewContent(
            feature: .textStyling, locale: locale, noteColor: .blue,
            title: String(localized: "Ideas for later", bundle: ProPreviewContent.localizationBundle(for: locale), locale: locale)
        )
        let contents = [front, back]
        return DeckCarousel(
            notes: contents.map(\.note),
            departingNoteID: nil,
            isDepartingNoteFading: false,
            summaries: Dictionary(uniqueKeysWithValues: contents.map {
                ($0.note.id, NoteTaskSummary(noteID: $0.note.id, tasks: $0.tasks))
            }),
            taskPreviews: Dictionary(uniqueKeysWithValues: contents.map {
                ($0.note.id, $0.tasks.map { NoteTaskPreview($0) })
            }),
            cardHeight: previewHeight, contentScale: 1,
            open: { _ in }, rename: { _ in }, delete: { _ in }
        )
        .frame(width: availableWidth)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var macDownloadButton: some View {
        Button("Get Tildone for Mac") { showsMacDownload = true }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("welcome-get-mac")
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Back") { navigate(to: step - 1) }.accessibilityIdentifier("welcome-back")
            }
            Button(step < 2 ? LocalizedStringKey("Next") : LocalizedStringKey("Start using Tildone")) {
                if step < 2 { navigate(to: step + 1) } else { finish() }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(step < 2 ? "welcome-next" : "welcome-start")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func finish() {
        WelcomeOnboarding.finish()
        close()
    }

    private func navigate(to step: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { self.step = step }
    }
}
