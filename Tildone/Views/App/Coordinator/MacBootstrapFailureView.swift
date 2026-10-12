import SwiftUI

struct MacBootstrapFailureView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Tildone could not open your notes.").font(.headline)
            Text("Your existing notes have not been changed. Tildone needs your help before it can open them.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        // The coordinator starts at zero size. Give the failure branch its
        // own width so it can expand rather than inherit the hidden proposal.
        .frame(width: 420)
    }
}
