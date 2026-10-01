//
//  MacNotePresentation.swift
//  Tildone
//

import Foundation
import TildoneDomain

/// Granular observable state for one note window. Content mutations update only
/// this object instead of invalidating every open note through MacSharedStore.
@MainActor
final class MacNotePresentation: ObservableObject {
    @Published fileprivate(set) var snapshot: MacNoteSnapshot

    // The titlebar lives in a separate hosting view. Route its user action to
    // the note editor so staging, first-responder handoff and draft buffering
    // happen synchronously before persistence begins.
    var onKindChange: ((NoteKind) -> Void)?

    func requestKindChange(_ kind: NoteKind) {
        onKindChange?(kind)
    }

    init(snapshot: MacNoteSnapshot) {
        self.snapshot = snapshot
    }

    func update(_ snapshot: MacNoteSnapshot) {
        self.snapshot = snapshot
    }
}
