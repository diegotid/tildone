#if MARKETING_CAPTURE
import SwiftUI

/// Fictional document context, hosted in a native window with disposable text.
@available(macOS 15, *)
struct MarketingCaptureTextEdit: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Text(verbatim: "Helvetica")
                Divider().frame(height: 16)
                Text(verbatim: "12")
                Image(systemName: "bold")
                Image(systemName: "italic")
                Image(systemName: "underline")
                Spacer()
            }
            .font(.system(size: 11))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Color.gray.opacity(0.06))
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Workshop outline").font(.system(size: 15, weight: .semibold))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Welcome and introductions")
                    Text("A practical example")
                    Text("Questions and next steps")
                }
                .font(.system(size: 14))
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        .background(Color(nsColor: NSColor(calibratedWhite: 0.94, alpha: 1)))
        .environment(\.colorScheme, .light)
    }
}
#endif
