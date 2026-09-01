import TildoneDomain

struct DeckCarouselGroup: Identifiable {
    enum ID: Hashable {
        case color(NoteColor)
        case singleNoteColors
    }

    let id: ID
    let notes: [Note]
}
