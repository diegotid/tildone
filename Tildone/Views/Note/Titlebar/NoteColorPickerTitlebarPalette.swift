//
//  NoteColorPickerTitlebarPalette.swift
//  Tildone
//

import SwiftUI
import TildoneDomain

struct NoteColorPickerTitlebarPalette: View {
    @ObservedObject var store: MacSharedStore
    let noteID: NoteID
    let dismiss: () -> Void

    var body: some View {
        NoteColorPalette(selected: store.note(noteID)?.color ?? .yellow) { selectedColor in
            Swift.Task { try? await store.setColor(selectedColor, for: noteID) }
            dismiss()
        }
    }
}
