#if MARKETING_CAPTURE
import AppKit
import SwiftUI

/// Presentation canvas only. The notes above this view are real MacNoteWindows.
@available(macOS 15, *)
struct MarketingCaptureBackdrop: View {
    @ObservedObject var director: MarketingCaptureDirector
    let wallpaper: NSImage

    var body: some View {
        ZStack(alignment: .top) {
            Image(nsImage: wallpaper)
                .resizable()
                .scaledToFill()
                .frame(width: 1440, height: 810)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.24), .clear],
                           startPoint: .top, endPoint: .center)
            VStack(spacing: 12) {
                Text(LocalizedStringKey(director.headline))
                    .font(.system(size: 82.5, weight: .semibold, design: .rounded))
                    .tracking(-1.2)
                    .id(director.headline)
                    .transition(.opacity)
                Text("Sticky to-dos for your Mac.")
                    .font(.system(size: 33.75, weight: .medium))
                    .opacity(0.84)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 1320)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 2)
            .padding(.top, 64)
            .animation(.easeInOut(duration: 0.35), value: director.headline)
        }
        .overlay(alignment: .bottomTrailing) {
            Text(verbatim: "Tildone")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.25), radius: 8)
                .padding(40)
        }
        .frame(width: 1440, height: 810)
        .clipped()
    }
}
#endif
