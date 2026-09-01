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
    @Published private(set) var snapshot = TildoneiOSOverviewSnapshot()

    func update(_ snapshot: TildoneiOSOverviewSnapshot) {
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
    @Published private(set) var snapshot: TildoneiOSNoteSnapshot

    init(snapshot: TildoneiOSNoteSnapshot = .empty) {
        self.snapshot = snapshot
    }

    func update(_ snapshot: TildoneiOSNoteSnapshot) {
        guard self.snapshot != snapshot else { return }
        self.snapshot = snapshot
    }
}
