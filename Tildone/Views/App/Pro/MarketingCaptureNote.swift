#if MARKETING_CAPTURE
import SwiftUI
import TildoneDomain

/// Uniformly scales the real expanded content, including native text fields,
/// spacing and completion overlays. Compact notes retain their normal scale.
@available(macOS 15, *)
struct MarketingCaptureNote: View {
    @ObservedObject var director: MarketingCaptureDirector
    let store: MacSharedStore
    let presentation: MacNotePresentation
    let noteID: NoteID

    private var scale: CGFloat { director.compactNoteID == noteID ? 1 : 0.75 }

    var body: some View {
        GeometryReader { geometry in
            Note(store: store, presentation: presentation, noteID: noteID)
                .frame(width: geometry.size.width / scale,
                       height: geometry.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height,
                       alignment: .topLeading)
        }
    }
}
#endif
