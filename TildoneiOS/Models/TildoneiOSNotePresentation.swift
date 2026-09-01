//
//  TildoneiOSNotePresentation.swift
//  Tildone
//

import Foundation
import TildoneDomain
import TildoneSync

/// Granular observable state for the notes overview. Sync-status publications
/// stay on the application model and do not invalidate list, grid, or deck rows.
@MainActor
final class TildoneiOSOverviewPresentation: ObservableObject {
    struct Snapshot {
        var notes: [Note] = []
        var taskSummaries: [NoteID: NoteTaskSummary] = [:]
        var taskListTexts: [NoteID: String] = [:]
        var taskPreviews: [NoteID: [NoteTaskPreview]] = [:]
    }

    @Published private(set) var snapshot = Snapshot()

    func update(_ snapshot: Snapshot) {
        self.snapshot = snapshot
    }
}

/// Sync progress changes frequently during startup. Keeping it in a dedicated
/// observable prevents those publications from invalidating note content.
@MainActor
final class TildoneiOSSyncPresentation: ObservableObject {
    @Published private(set) var status: SyncStatus = .disabled
    @Published private(set) var transportState: SyncTransportState = .active

    func update(status: SyncStatus) {
        self.status = status
    }

    func update(transportState: SyncTransportState) {
        self.transportState = transportState
    }
}

/// Granular observable state for one iPhone checklist. Local gestures update
/// this snapshot before persistence and sync work is scheduled.
@MainActor
final class TildoneiOSNotePresentation: ObservableObject {
    struct Snapshot: Equatable {
        let note: Note?
        let tasks: [Task]

        static let empty = Snapshot(note: nil, tasks: [])
    }

    @Published private(set) var snapshot: Snapshot

    init(snapshot: Snapshot = .empty) {
        self.snapshot = snapshot
    }

    func update(_ snapshot: Snapshot) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }
}
