import SwiftUI
import TildoneDomain

struct NotesDeckView: View {
    let notes: [Note]
    let departingNoteID: NoteID?
    let isDepartingNoteFading: Bool
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
                            departingNoteID: departingNoteID,
                            isDepartingNoteFading: isDepartingNoteFading,
                            summaries: summaries,
                            taskPreviews: taskPreviews,
                            cardHeight: cardHeight,
                            contentScale: contentScale,
                            open: open,
                            rename: rename,
                            delete: delete
                        )
#if MARKETING_CAPTURE
                        .background {
                            GeometryReader { geometry in
                                Color.clear.onChange(of: geometry.frame(in: .global), initial: true) { _, frame in
                                    let viewport = proxy.frame(in: .global)
                                    NotificationCenter.default.post(
                                        name: Notification.Name("TildoneMarketingDeckGeometry"), object: nil,
                                        userInfo: ["title": group.notes.first?.title ?? "",
                                                   "color": group.notes.first?.color.rawValue ?? "",
                                                   "noteCount": group.notes.count,
                                                   "frame": frame, "viewport": viewport,
                                                   "cardHeight": cardHeight])
                                }
                            }
                        }
#endif
                    }
                }
                .padding(.vertical, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

}
