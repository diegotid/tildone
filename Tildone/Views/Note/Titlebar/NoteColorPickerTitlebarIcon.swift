//
//  NoteColorPickerTitlebarIcon.swift
//  Tildone
//

import SwiftUI
import TildoneDomain

struct NoteColorPickerTitlebarIcon: View {
    let store: MacSharedStore
    @ObservedObject var presentation: MacNotePresentation
    let noteID: NoteID

    var body: some View {
        NoteColorPickerIcon(color: presentation.snapshot.color)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .ignoresSafeArea()
    }
}
