import SwiftUI

struct ProPaywallView: View {
    @ObservedObject private var entitlement = ProEntitlement.shared
    let feature: ProFeature?
    @State private var selectedFeature: ProFeature?
    #if os(macOS)
    @State private var indexHeight: CGFloat = 540
    #endif

    init(feature: ProFeature?) {
        self.feature = feature
        _selectedFeature = State(initialValue: feature)
    }

    var body: some View {
        #if os(macOS)
        macPage(feature: selectedFeature)
            .background {
                macPage(feature: nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .hidden()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: IndexHeightKey.self, value: geometry.size.height)
                        }
                    }
            }
            .onPreferenceChange(IndexHeightKey.self) { height in
                if height > 0 { indexHeight = height }
            }
            .frame(width: 408, height: indexHeight)
            .onChange(of: feature) { _, selected in selectedFeature = selected }
        #else
        ScrollView {
            VStack(spacing: 12) {
                if let selectedFeature {
                    ForEach(selectedFeature.previewFeatures) { example in
                        Text(example.title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                        Text(example.outcome).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if example.isMacOnly {
                            Text("Mac only").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ProFeaturePreview(feature: example).frame(maxWidth: 360)
                        }
                    }
                    discoverButton
                } else {
                    featureIndex
                }
                purchaseControls
            }
            .padding(24)
            .frame(maxWidth: 408)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: feature) { _, selected in selectedFeature = selected }
        #endif
    }

    private var discoverButton: some View {
        Button {
            selectedFeature = nil
        } label: {
            Text("Discover all Pro features")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("pro-discover-all")
    }

    private var purchaseControls: some View {
        VStack(spacing: 12) {
            Text("One purchase unlocks Pro on Mac and iPhone.")
                .multilineTextAlignment(.center)
            if entitlement.isPro {
                Text("Tildone Pro is unlocked.")
                    .foregroundStyle(.secondary)
            } else if let price = entitlement.localizedPrice {
                Button {
                    Task { await entitlement.purchase() }
                } label: {
                    HStack(spacing: 12) {
                        Text("Unlock Tildone Pro")
                        Spacer(minLength: 8)
                        Text(price)
                            .fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("pro-purchase")
                .disabled(entitlement.isPurchasing)
            } else {
                Button {
                    Task { await entitlement.loadProduct() }
                } label: {
                    Text("Try loading price again")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pro-purchase")
                .disabled(entitlement.isLoadingProduct)
            }
            Button {
                Task { await entitlement.restore() }
            } label: {
                Text("Restore Purchases")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            if let message = entitlement.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pro-status")
                    #if os(macOS)
                    .lineLimit(3)
                    .help(message)
                    #endif
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    #if os(macOS)
    private func macPage(feature: ProFeature?) -> some View {
        VStack(spacing: 12) {
            if let feature {
                featureExplanation(feature)
                discoverButton
            } else {
                featureIndex
            }
            purchaseControls
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: ContentHeightKey.self, value: geometry.size.height)
            }
        }
    }

    private func featureExplanation(_ feature: ProFeature) -> some View {
        VStack(spacing: 12) {
            Text(feature.title).font(.largeTitle.bold()).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(feature.outcome).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if feature == .focusPrivacy {
                HStack(spacing: 12) {
                    ForEach(feature.previewFeatures) { example in
                        VStack(spacing: 8) {
                            Text(example.title).font(.headline).multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                            fillingPreview(example)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            } else {
                fillingPreview(feature)
            }
        }
    }

    private func fillingPreview(_ feature: ProFeature) -> some View {
        GeometryReader { geometry in
            ProFeaturePreview(feature: feature, canvasSize: geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(maxHeight: .infinity)
    }

    private struct IndexHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    struct ContentHeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
    #endif

    private var featureIndex: some View {
        VStack(spacing: 8) {
            ForEach(ProFeature.catalog) { feature in
                Button {
                    selectedFeature = feature
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(feature.title).font(.headline)
                                if feature.isMacOnly {
                                    Text("Mac only").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(feature.indexCaption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                #if os(macOS)
                                .lineLimit(1)
                                #endif
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(.secondary)
                            .padding(.top, 3)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pro-feature-\(feature.rawValue)")
            }
        }
    }

}
