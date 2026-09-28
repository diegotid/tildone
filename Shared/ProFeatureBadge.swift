import SwiftUI

struct ProFeatureBadge: View {
    var body: some View {
        Label("Pro", systemImage: "lock.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .overlay {
                Capsule().stroke(.secondary.opacity(0.18), lineWidth: 0.5)
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Requires Pro")
    }
}
