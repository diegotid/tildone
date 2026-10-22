#if MARKETING_CAPTURE
import SwiftUI
import TildoneDomain

/// Matches preview one's real note content scale without coupling the directors.
@available(macOS 15, *)
struct MarketingSyncCaptureNote: View {
    let store: MacSharedStore
    let presentation: MacNotePresentation
    let noteID: NoteID

    var body: some View {
        GeometryReader { geometry in
            Note(store: store, presentation: presentation, noteID: noteID)
                .frame(width: geometry.size.width / 0.75,
                       height: geometry.size.height / 0.75)
                .scaleEffect(0.75, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height,
                       alignment: .topLeading)
        }
    }
}
#endif
