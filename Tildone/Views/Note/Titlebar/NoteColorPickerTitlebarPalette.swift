//
//  NoteColorPickerTitlebarPalette.swift
//  Tildone
//

import SwiftUI
import TildoneDomain

struct NoteColorPickerTitlebarPalette: View {
    let store: MacSharedStore
    @ObservedObject var presentation: MacNotePresentation
    let noteID: NoteID
    let dismiss: () -> Void

    var body: some View {
        NoteColorPalette(selected: presentation.snapshot.color) { selectedColor in
            Swift.Task { try? await store.setColor(selectedColor, for: noteID) }
            dismiss()
        }
    }
}
