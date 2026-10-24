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
                .frame(width: director.canvasSize.width, height: director.canvasSize.height)
                .clipped()
            LinearGradient(colors: [.black.opacity(0.24), .clear],
                           startPoint: .top, endPoint: .center)
            VStack(spacing: 12) {
                Text(LocalizedStringKey(director.headline))
                    .font(.system(size: 82.5, weight: .semibold, design: .rounded))
                    .tracking(-1.2)
                    .lineLimit(director.isScreenshot ? 1 : nil)
                    .minimumScaleFactor(director.isScreenshot ? 0.68 : 1)
                    .id(director.headline)
                    .transition(.opacity)
                Text(LocalizedStringKey(director.subtitle))
                    .font(.system(size: 33.75, weight: .medium))
                    .opacity(0.84)
                if director.isProScreenshot || director.isPrivacyScreenshot {
                    Text("Tildone Pro · One-time purchase")
                        .font(.system(size: 19, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.14), in: Capsule())
                        .padding(.top, 8)
                }
                if director.isSecondScreenshot {
                    Label("Same iCloud account", systemImage: "icloud")
                        .font(.system(size: 19, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.14), in: Capsule())
                        .padding(.top, 8)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 1320)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 2)
            .padding(.top, 64)
            .animation(.easeInOut(duration: 0.35), value: director.headline)
        }
        .overlay(alignment: .topLeading) {
            if director.isSecondScreenshot, let phone = director.phoneScreenshot {
                let scale = director.phoneRenderingScale
                let frame = director.phoneFrame
                Image(nsImage: phone)
                    .resizable()
                    .frame(width: director.phoneSourceSize.width * scale,
                           height: director.phoneSourceSize.height * scale)
                    .clipShape(RoundedRectangle(cornerRadius: 52 * scale, style: .continuous))
                    .padding(director.phoneBezel * scale)
                    .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 64 * scale, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 64 * scale, style: .continuous)
                        .stroke(.white.opacity(0.3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                    .position(x: frame.midX, y: frame.midY)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text(verbatim: "Tildone")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.25), radius: 8)
                .padding(40)
        }
        .frame(width: director.canvasSize.width, height: director.canvasSize.height)
        .clipped()
    }
}
#endif
