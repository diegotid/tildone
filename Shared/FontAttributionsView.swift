import SwiftUI

struct FontAttributionsView: View {
    var body: some View {
        List(SingleMemoTypography.attributions) { attribution in
            VStack(alignment: .leading, spacing: 7) {
                Text(verbatim: attribution.font.displayName)
                    .font(.custom(
                        SingleMemoTypography.fontName(for: attribution.font),
                        size: 22
                    ))
                Text(verbatim: attribution.copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if let sourceURL = URL(string: attribution.sourceURL) {
                        Link("Source", destination: sourceURL)
                    }
                    if let licenseURL = URL(string: attribution.licenseURL) {
                        Link(attribution.license, destination: licenseURL)
                    }
                }
                .font(.caption)
            }
            .padding(.vertical, 5)
        }
        .navigationTitle("Font Attributions")
    }
}
