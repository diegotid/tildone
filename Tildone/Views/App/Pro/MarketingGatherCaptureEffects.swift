#if MARKETING_CAPTURE
import SwiftUI

/// Transparent own-process overlay above mock documents, below actual notes.
@available(macOS 15, *)
struct MarketingGatherCaptureEffects: View {
    @ObservedObject var director: MarketingGatherCaptureDirector

    private func local(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX - director.insetFrame.minX,
               y: director.insetFrame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(director.ghostFrames.indices, id: \.self) { index in
                let ghost = local(director.ghostFrames[index])
                if director.gatheredFrames.indices.contains(index) {
                    let target = local(director.gatheredFrames[index])
                    Path { path in
                        path.move(to: CGPoint(x: ghost.midX, y: ghost.midY))
                        path.addLine(to: CGPoint(x: target.midX, y: target.midY))
                    }
                    .stroke(Color(nsColor: director.colors[index].nsColor).opacity(director.trailOpacity),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(nsColor: director.colors[index].nsColor).opacity(director.ghostOpacity), lineWidth: 1)
                    .frame(width: ghost.width, height: ghost.height)
                    .position(x: ghost.midX, y: ghost.midY)
            }
            Text("Gather with a scroll.")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(.black.opacity(0.48), in: Capsule())
                .padding(.leading, 16).padding(.top, 16)
            Group {
                if director.freezeChevron {
                    ScrollChevronIndicator(state: ScrollChevronState(travelOffset: 17,
                        pointsDown: true, directionTransitionOpacity: 1))
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        ScrollChevronIndicator(state: ScrollChevronState(
                            travelOffset: CGFloat(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)) * 60,
                            pointsDown: true, directionTransitionOpacity: 1))
                    }
                }
            }
            .scaleEffect(1.5)
            .position(x: director.insetFrame.width - 23, y: director.insetFrame.height / 2)
        }
        .frame(width: director.insetFrame.width, height: director.insetFrame.height)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .allowsHitTesting(false)
    }
}
#endif
