#if MARKETING_CAPTURE
import AppKit
import SwiftUI

/// Marketing canvas; all documents and real notes are native child windows.
@available(macOS 15, *)
struct MarketingGatherCaptureBackdrop: View {
    @ObservedObject var director: MarketingGatherCaptureDirector
    let wallpaper: NSImage

    var body: some View {
        ZStack(alignment: .top) {
            Image(nsImage: wallpaper).resizable().scaledToFill()
                .frame(width: director.canvasSize.width, height: director.canvasSize.height).clipped()
            LinearGradient(colors: [.black.opacity(0.24), .clear], startPoint: .top, endPoint: .center)
            VStack(spacing: 12) {
                Text("Keep the reminder. Reclaim the space.")
                    .font(.system(size: 82.5, weight: .semibold, design: .rounded))
                    .tracking(-1.2).lineLimit(1).minimumScaleFactor(0.65)
                Text("Your plans stay close. Your workspace opens up.")
                    .font(.system(size: 33.75, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.8).opacity(0.84)
                Text("Tildone Pro · One-time purchase")
                    .font(.system(size: 19, weight: .semibold))
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(.white.opacity(0.14), in: Capsule()).padding(.top, 8)
            }
            .multilineTextAlignment(.center).frame(width: 1320).foregroundStyle(.white)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 2).padding(.top, 64)
        }
        .overlay(alignment: .topLeading) {
            let frame = director.insetFrame
            Image(nsImage: wallpaper).resizable().scaledToFill()
                .frame(width: frame.width, height: frame.height).clipped()
                .overlay(.black.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.45), lineWidth: 1))
                .position(x: frame.midX, y: director.canvasSize.height - frame.midY)
        }
        .overlay(alignment: .bottomTrailing) {
            Text(verbatim: "Tildone").font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86)).padding(.trailing, 42).padding(.bottom, 40)
        }
        .frame(width: director.canvasSize.width, height: director.canvasSize.height)
    }
}
#endif
