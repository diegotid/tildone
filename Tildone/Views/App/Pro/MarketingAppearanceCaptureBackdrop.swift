#if MARKETING_CAPTURE
import AppKit
import SwiftUI

/// Frozen alternate settings states sit behind the live transparent native note.
@available(macOS 15, *)
struct MarketingAppearanceCaptureBackdrop: View {
    @ObservedObject var director: MarketingAppearanceCaptureDirector
    let wallpaper: NSImage

    var body: some View {
        ZStack(alignment: .top) {
            Image(nsImage: wallpaper).resizable().scaledToFill()
                .frame(width: director.canvasSize.width, height: director.canvasSize.height).clipped()
            LinearGradient(colors: [.black.opacity(0.24), .clear], startPoint: .top, endPoint: .center)
            VStack(spacing: 12) {
                Text("A desktop that feels like yours.")
                    .font(.system(size: 82.5, weight: .semibold, design: .rounded))
                    .tracking(-1.2).lineLimit(1).minimumScaleFactor(0.65)
                Text("Your colors. Your text size. Your level of quiet.")
                    .font(.system(size: 33.75, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8).opacity(0.84)
            }
            .frame(width: 1320).multilineTextAlignment(.center).foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 2).padding(.top, 64)
        }
        .overlay(alignment: .topLeading) {
            ForEach(0..<3) { index in
                if let image = director.images[index], let frame = director.cropFrames[index] {
                    Image(nsImage: image).resizable().frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: director.canvasSize.height - frame.midY)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            VStack(spacing: 8) {
                Text("Dim notes with a scroll.").font(.system(size: 17, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text("Tildone Pro · One-time purchase").font(.system(size: 15, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.75)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(.white.opacity(0.14), in: Capsule())
            }
            .foregroundStyle(.white.opacity(0.9)).frame(width: 400)
            .position(x: director.dimmingCaptionCenter.x, y: director.canvasSize.height - director.dimmingCaptionCenter.y)
        }
        .overlay(alignment: .bottomTrailing) {
            Text(verbatim: "Tildone").font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86)).padding(.trailing, 42).padding(.bottom, 20)
        }
        .frame(width: director.canvasSize.width, height: director.canvasSize.height)
    }
}
#endif
