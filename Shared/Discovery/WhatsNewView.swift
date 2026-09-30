import SwiftUI
import TildoneDomain

struct WhatsNewView: View {
    private static let previewDefaults: UserDefaults = {
        let defaults = UserDefaults(suiteName: "studio.cuatro.tildone.whats-new-preview")!
        defaults.register(defaults: [
            NoteColor.storageKey: NoteColor.yellow.legacyRawValue,
            NoteWindowBackground.opacityStorageKey: 0.8
        ])
        return defaults
    }()
    let close: () -> Void
    let startingStep: WhatsNewRelease.Step
    @State private var stepIndex = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    private var step: WhatsNewRelease.Step { WhatsNewRelease.steps[stepIndex] }
    private var isLastStep: Bool { stepIndex == WhatsNewRelease.steps.count - 1 }

    init(startingAt step: WhatsNewRelease.Step = .welcome, close: @escaping () -> Void) {
        self.close = close
        startingStep = step
        _stepIndex = State(initialValue: WhatsNewRelease.steps.firstIndex(of: step) ?? 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                if step == .welcome {
                    #if os(macOS)
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                        .resizable()
                        .scaledToFit()
                        .frame(width: 76, height: 76)
                    #else
                    Image(systemName: "checklist")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(.tint)
                        .frame(height: 76)
                    #endif
                }
                Text(step.title)
                    .font(.largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("whats-new-title")
                Text(step.detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 44)
            .padding(.top, step == .welcome ? 32 : 40)

            Spacer(minLength: 12)

            stepContent
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 44)
                .padding(.bottom, 12)
                .defaultAppStorage(Self.previewDefaults)
                .id(step.id)

            Spacer(minLength: 12)

            Divider()
            HStack(spacing: 12) {
                Menu("Close") {
                    Button("Show again next launch", action: close)
                        .accessibilityIdentifier("whats-new-remind")
                    Button("Don't show until next version") {
                        WhatsNewRelease.suppressUntilNextVersion()
                        close()
                    }
                    .accessibilityIdentifier("whats-new-suppress")
                }
                .accessibilityIdentifier("whats-new-close")
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            Button("Get Tildone for iPhone") { openURL(CompanionAppLink.appStore) }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.accentColor)
                .accessibilityIdentifier("whats-new-get-iphone")
                Spacer()
                if stepIndex > 0 {
                    Button("Back") { navigate(to: stepIndex - 1) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityIdentifier("whats-new-back")
                }
                Button(primaryActionTitle) {
                    if isLastStep {
                        WhatsNewRelease.acknowledge()
                        close()
                    } else { navigate(to: stepIndex + 1) }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier(isLastStep ? "whats-new-done" : "whats-new-next")
                .keyboardShortcut(.defaultAction)
            }
            .overlay {
                Text("\(stepIndex + 1) of \(WhatsNewRelease.steps.count)")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("whats-new-progress")
            }
            .padding(24)
        }
        .onAppear { stepIndex = WhatsNewRelease.steps.firstIndex(of: startingStep) ?? 0 }
        .onExitCommand(perform: close)
        .frame(width: 760, height: windowHeight)
        #if os(macOS)
        .background(WindowChromeHider())
        #endif
    }

    #if os(macOS)
    private struct WindowChromeHider: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async { configure(view.window) }
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            DispatchQueue.main.async { configure(view.window) }
        }

        private func configure(_ window: NSWindow?) {
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(button)?.isHidden = true
            }
        }
    }
    #endif

    @ViewBuilder
    private var stepContent: some View {
        if step == .welcome {
            welcomeIndex
        } else if step == .companion {
            CompanionPreview()
                .frame(width: 580)
                .frame(maxWidth: .infinity)
        } else if step == .everyday {
            #if os(macOS)
            WhatsNewEverydayPreview()
                .frame(width: 360, height: 360)
            #else
            WhatsNewEverydayPreview()
                .frame(maxWidth: .infinity)
            #endif
        } else {
            featurePreviews
        }
    }

    private var primaryActionTitle: LocalizedStringKey {
        if isLastStep { return "Let’s get started" }
        switch step {
        case .welcome: return "Explore new features"
        case .companion: return "See everyday updates"
        case .everyday: return "Explore creative tools"
        case .expression: return "Explore subtasks"
        case .subtasks: return "Explore desktop features"
        case .desktop: return "Explore Focus settings"
        case .focusPrivacy: return "Continue the tour"
        }
    }

    private var windowHeight: CGFloat {
        switch step {
        case .companion: return 560
        case .welcome: return 520
        default: return 620
        }
    }

    private var welcomeIndex: some View {
        VStack(alignment: .leading, spacing: 20) {
            #if os(macOS)
            indexEntry(
                title: "Across your devices",
                symbol: WhatsNewRelease.Step.companion.symbolName,
                caption: WhatsNewRelease.Step.companion.indexDescription
            ) {
                navigate(to: WhatsNewRelease.steps.firstIndex(of: .companion) ?? 0)
            }
            #endif
            indexEntry(
                title: "Everyday improvements",
                symbol: WhatsNewRelease.Step.everyday.symbolName,
                caption: WhatsNewRelease.Step.everyday.indexDescription
            ) {
                navigate(to: WhatsNewRelease.steps.firstIndex(of: .everyday) ?? 0)
            }
            indexEntry(
                title: "More ways to work",
                symbol: WhatsNewRelease.Step.desktop.symbolName,
                caption: "Memos and text styling, subtasks with progress, a calmer desktop, per-note Focus settings."
            ) {
                navigate(to: WhatsNewRelease.steps.firstIndex(of: .expression) ?? 0)
            }
        }
        .frame(width: 500, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, -24)
    }

    private func indexEntry(
        title: LocalizedStringKey,
        symbol: String,
        caption: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .regular))
                    .foregroundStyle(.tint)
                    .frame(width: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(caption)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var featurePreviews: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20),
                                count: step.features.count == 1 ? 1 : 2), spacing: 16) {
            ForEach(step.features) { feature in
                VStack(alignment: .center, spacing: 10) {
                    ProFeaturePreview(feature: feature, canvasSize: previewCanvasSize, previewDefaults: Self.previewDefaults)
                        .frame(maxWidth: 320, alignment: .center)
                    HStack(spacing: 7) {
                        ProFeatureBadge()
                        Button {
                            ProEntitlement.shared.preparePaywall(for: feature)
                            openWindow(id: "tildonePro")
                        } label: {
                            Text(feature.title).fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .accessibilityIdentifier("whats-new-feature-\(feature.rawValue)")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: step.features.count == 1 ? 340 : .infinity, alignment: .center)
            }
        }
    }

    private var previewCanvasSize: CGSize {
        CGSize(width: 360, height: 360)
    }

    private func navigate(to index: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { stepIndex = index }
    }
}

#Preview("What’s New — feature index") {
    WhatsNewView(startingAt: .welcome, close: {})
}
