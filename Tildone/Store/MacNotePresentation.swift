//
//  MacNotePresentation.swift
//  Tildone
//

import Foundation

/// Granular observable state for one note window. Content mutations update only
/// this object instead of invalidating every open note through MacSharedStore.
@MainActor
final class MacNotePresentation: ObservableObject {
    @Published fileprivate(set) var snapshot: MacNoteSnapshot

    init(snapshot: MacNoteSnapshot) {
        self.snapshot = snapshot
    }

    func update(_ snapshot: MacNoteSnapshot) {
        self.snapshot = snapshot
    }
}
