import SwiftUI
import TildoneDomain

struct NotesGridView: View {
    let notes: [Note]
    let summaries: [NoteID: NoteTaskSummary]
    let taskPreviews: [NoteID: [NoteTaskPreview]]
    let open: (Note) -> Void
    let rename: (Note) -> Void
    let delete: (Note) -> Void

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        GeometryReader { proxy in
            let cardHeight = NoteCardLayoutMetrics.gridHeight(in: proxy.size.height)
            let gridCardHeight = NoteCardLayoutMetrics.gridHeight(in: proxy.size.height)
            let contentScale = cardHeight / gridCardHeight
            
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(notes, id: \.id) { note in
                        NoteCard(
                            note: note,
                            summary: summaries[note.id],
                            tasks: taskPreviews[note.id] ?? [],
                            style: .grid,
                            height: cardHeight,
                            contentScale: contentScale,
                            rename: { rename(note) },
                            delete: { delete(note) }
                        )
                        .onTapGesture { open(note) }
                    }
                }
                .padding(16)
            }
        }
    }
}
