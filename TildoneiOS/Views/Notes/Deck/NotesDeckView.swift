import SwiftUI
import TildoneDomain

struct NotesDeckView: View {
    let notes: [Note]
    let summaries: [NoteID: NoteTaskSummary]
    let taskPreviews: [NoteID: [NoteTaskPreview]]
    let open: (Note) -> Void
    let rename: (Note) -> Void
    let delete: (Note) -> Void

    private var carouselGroups: [DeckCarouselGroup] {
        let notesByColor = Dictionary(grouping: notes, by: \.color)
        var groups = NoteColor.allCases.compactMap { color -> DeckCarouselGroup? in
            guard let colorNotes = notesByColor[color], colorNotes.count > 1 else { return nil }
            return DeckCarouselGroup(id: .color(color), notes: colorNotes)
        }

        let singletonNotes = notes.filter { notesByColor[$0.color]?.count == 1 }
        if !singletonNotes.isEmpty {
            groups.append(DeckCarouselGroup(id: .singleNoteColors, notes: singletonNotes))
        }
        return groups
    }

    var body: some View {
        GeometryReader { proxy in
            let cardHeight = NoteCardLayoutMetrics.deckHeight(in: proxy.size.height)
            let gridCardHeight = NoteCardLayoutMetrics.gridHeight(in: proxy.size.height)
            let contentScale = cardHeight / gridCardHeight

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(carouselGroups) { group in
                        DeckCarousel(
                            notes: group.notes,
                            summaries: summaries,
                            taskPreviews: taskPreviews,
                            cardHeight: cardHeight,
                            contentScale: contentScale,
                            open: open,
                            rename: rename,
                            delete: delete
                        )
                    }
                }
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

}
