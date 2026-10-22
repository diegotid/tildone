#if MARKETING_CAPTURE
import AppKit
import AVFoundation
import SwiftUI

/// The real iPhone creation flow, recorded on its isolated simulator.
@available(macOS 15, *)
struct MarketingSyncCapturePhone: View {
    @ObservedObject var director: MarketingSyncCaptureDirector

    var body: some View {
        NativeVideo(player: director.phonePlayer)
            .frame(width: 222, height: 482)
            .clipShape(RoundedRectangle(cornerRadius: 29, style: .continuous))
            .padding(7)
            .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(.white.opacity(0.30), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
    }

    private struct NativeVideo: NSViewRepresentable {
        let player: AVPlayer

        func makeNSView(context: Context) -> PlayerView {
            PlayerView(player: player)
        }

        func updateNSView(_ view: PlayerView, context: Context) {}

        final class PlayerView: NSView {
            private let playerLayer: AVPlayerLayer

            init(player: AVPlayer) {
                playerLayer = AVPlayerLayer(player: player)
                playerLayer.videoGravity = .resizeAspect
                super.init(frame: .zero)
                wantsLayer = true
                layer?.addSublayer(playerLayer)
            }

            required init?(coder: NSCoder) { return nil }

            override func layout() {
                super.layout()
                playerLayer.frame = bounds
            }
        }
    }
}
#endif
