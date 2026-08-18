//
//  NoteColorPickerTitlebarIcon.swift
//  Tildone
//

import SwiftUI
import TildoneDomain

struct NoteColorPickerTitlebarIcon: View {
    @ObservedObject var store: MacSharedStore
    let noteID: NoteID

    var body: some View {
        NoteColorPickerIcon(color: store.note(noteID)?.color ?? .yellow)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .ignoresSafeArea()
    }
}
