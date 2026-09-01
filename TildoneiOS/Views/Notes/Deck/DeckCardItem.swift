import TildoneDomain

struct DeckCardItem: Identifiable {
    let note: Note
    let relativePosition: Int

    var id: NoteID { note.id }
}
