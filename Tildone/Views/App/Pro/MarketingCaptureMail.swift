#if MARKETING_CAPTURE
import AppKit
import SwiftUI

/// Fictional email context for the capture, never a customer account or app feature.
@available(macOS 15, *)
struct MarketingCaptureMail: View {
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Label("Inbox", systemImage: "tray")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(10)
                Divider()
                messageRow(sender: "Coast Rail", subject: "Your tickets are ready", selected: true)
                messageRow(sender: "North Gallery", subject: "Your gallery receipt")
                messageRow(sender: "The Weekly Edit", subject: "This week in design")
                Spacer(minLength: 0)
            }
            .frame(width: 126)
            .background(Color.gray.opacity(0.06))
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    Image(systemName: "arrow.uturn.backward")
                    Image(systemName: "archivebox")
                    Spacer()
                    Image(systemName: "ellipsis")
                }
                .font(.system(size: 12))
                Divider()
                Text("Your tickets are ready")
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "Coast Rail")
                        .font(.system(size: 12, weight: .medium))
                    Text("To: Alex")
                        .font(.system(size: 11))
                }
                Text("Hello Alex,\n\nYour tickets are attached. Have a wonderful journey!\n\nCoast Rail")
                    .font(.system(size: 12))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        .background(Color(nsColor: NSColor(calibratedWhite: 0.9, alpha: 1)))
        .environment(\.colorScheme, .light)
        .clipped()
    }

    private func messageRow(sender: String, subject: LocalizedStringKey, selected: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: sender)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Text(subject)
                .font(.system(size: 11))
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.gray.opacity(0.13) : .clear)
    }
}
#endif
