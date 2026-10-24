#if MARKETING_CAPTURE
import SwiftUI
import TildoneDomain

/// The same production Note and native editors, scaled equally in both scenes.
@available(macOS 15, *)
struct MarketingGatherCaptureNote: View {
    let store: MacSharedStore
    let presentation: MacNotePresentation
    let noteID: NoteID
    let scale: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Note(store: store, presentation: presentation, noteID: noteID)
                .frame(width: geometry.size.width / scale, height: geometry.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }
}
#endif
