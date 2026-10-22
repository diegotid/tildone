#if MARKETING_CAPTURE
import AppKit
import SwiftUI

/// Caption overlays for the continuity story; all note UI lives in native windows.
@available(macOS 15, *)
struct MarketingSyncCaptureBackdrop: View {
    @ObservedObject var director: MarketingSyncCaptureDirector
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .id(director.headline)
                    .transition(.opacity)
                Text(LocalizedStringKey(director.subtitle))
                    .font(.system(size: 33.75, weight: .medium))
                    .opacity(0.9)
                    .id(director.subtitle)
                    .transition(.opacity)
                Label(LocalizedStringKey(director.eventLabel), systemImage: director.eventSymbol)
                    .font(.system(size: 23, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.16), in: Capsule())
                    .padding(.top, 12)
                    .id(director.eventLabel)
                    .transition(.opacity)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 1320)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 2)
            .padding(.top, 64)
            .animation(.easeInOut(duration: 0.35), value: director.headline)
            .animation(.easeInOut(duration: 0.35), value: director.eventLabel)
        }
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                MarketingSyncCapturePhone(director: director)
                    .position(director.phoneCenter)
                if let flowSymbol = director.flowSymbol {
                    Image(systemName: flowSymbol)
                        .font(.system(size: 35, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.15), radius: 5)
                        .position(x: 929, y: 455)
                }
                Image(systemName: "icloud")
                    .resizable()
                    .scaledToFit()
                    .frame(width: director.cloudSize.width, height: director.cloudSize.height)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.15), radius: 5)
                    .position(director.cloudCenter)
            }
            .frame(width: 1440, height: 810)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text("iCloud sync included. No Pro required.")
                Text("Use the same Apple Account on Mac and iPhone.")
                    .opacity(0.85)
            }
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 8)
            .padding(40)
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
