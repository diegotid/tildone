import SwiftUI

struct WhatsNewView: View {
    let close: () -> Void
    @State private var stepIndex = 0
    @ObservedObject private var pro = ProEntitlement.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #else
    @State private var selectedFeature: ProFeature?
    #endif

    private var step: WhatsNewRelease.Step { WhatsNewRelease.steps[stepIndex] }
    private var isLastStep: Bool { stepIndex == WhatsNewRelease.steps.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                #if !os(macOS)
                Text("What’s New").font(.headline)
                #endif
                Spacer()
                Text("Step \(stepIndex + 1) of \(WhatsNewRelease.steps.count)")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("whats-new-progress")
            }
            .padding(24)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(step.title).font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("whats-new-title")
                    Text(step.detail).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    availability
                    if step == .everyday {
                        WhatsNewEverydayPreview()
                            .frame(maxWidth: 360)
                            .frame(maxWidth: .infinity)
                    } else {
                        featurePreviews
                    }
                    if step == .subtasks {
                        Text("Existing subtasks remain visible and editable without Pro. Creating or changing their hierarchy requires Pro.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .id(step.id)

            Divider()
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button("Close", action: close)
                        .accessibilityIdentifier("whats-new-close")
                        #if os(macOS)
                        .keyboardShortcut(.cancelAction)
                        #endif
                    Spacer()
                    if stepIndex > 0 {
                        Button("Back") { navigate(to: stepIndex - 1) }
                            .accessibilityIdentifier("whats-new-back")
                    }
                    Button(isLastStep ? LocalizedStringKey("Let’s get started") : LocalizedStringKey("Next")) {
                        if isLastStep {
                            WhatsNewRelease.acknowledge()
                            close()
                        } else { navigate(to: stepIndex + 1) }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(isLastStep ? "whats-new-done" : "whats-new-next")
                    #if os(macOS)
                    .keyboardShortcut(.defaultAction)
                    #endif
                }
                Button("Don't show until next version") {
                    WhatsNewRelease.suppressUntilNextVersion()
                    close()
                }
                .font(.caption)
                .accessibilityIdentifier("whats-new-suppress")
                #if os(macOS)
                .buttonStyle(.link)
                #else
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                #endif
            }
            .padding(24)
        }
        #if os(macOS)
        .onAppear { stepIndex = 0 }
        .frame(width: 680, height: 640)
        #else
        .sheet(item: $selectedFeature) { feature in
            NavigationStack {
                ProPaywallView(feature: feature)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { selectedFeature = nil }
                                .accessibilityIdentifier("whats-new-preview-done")
                        }
                    }
            }
        }
        #endif
    }

    private var availability: some View {
        Group {
            if step == .everyday {
                Label("Included for everyone", systemImage: "checkmark.circle")
            } else if pro.isPro {
                Label("Included in your Pro purchase", systemImage: "checkmark.circle")
            } else {
                HStack(spacing: 8) {
                    ProFeatureBadge()
                    Text("Preview available to everyone")
                }
            }
        }
        .font(.callout.weight(.medium))
        .accessibilityIdentifier("whats-new-availability")
    }

    private var featurePreviews: some View {
        LazyVGrid(columns: previewColumns, alignment: .leading, spacing: 18) {
            ForEach(step.features) { feature in
                VStack(alignment: .leading, spacing: 8) {
                    ProFeaturePreview(feature: feature, canvasSize: previewCanvasSize)
                        .frame(maxWidth: step == .desktop ? 236 : .infinity)
                    Button {
                        #if os(macOS)
                        pro.preparePaywall(for: feature)
                        openWindow(id: "tildonePro")
                        #else
                        selectedFeature = feature
                        #endif
                    } label: {
                        HStack {
                            Text(feature.title)
                            Image(systemName: "arrow.up.right")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("whats-new-feature-\(feature.rawValue)")
                }
                .frame(maxWidth: step.features.count == 1 ? 340 : .infinity)
            }
        }
    }

    private var previewCanvasSize: CGSize {
        step == .desktop ? CGSize(width: 360, height: 200) : CGSize(width: 360, height: 360)
    }

    private var previewColumns: [GridItem] {
        #if os(macOS)
        Array(repeating: GridItem(.flexible(), spacing: 18), count: step.features.count == 1 ? 1 : 2)
        #else
        // Give each example full width on iPhone, including accessibility sizes.
        [GridItem(.flexible())]
        #endif
    }

    private func navigate(to index: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            stepIndex = index
        }
    }
}
