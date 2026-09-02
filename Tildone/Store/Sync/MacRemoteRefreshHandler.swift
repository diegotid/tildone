//
//  MacRemoteRefreshHandler.swift
//  Tildone
//

import Foundation
import TildoneDomain
import TildoneSync

enum MacRemoteRefreshHandler {
    static func run(
        remoteChange: RemoteContentChange,
        invalidateUndo: (Set<DomainRecordID>) async -> Void,
        migrateColors: () async throws -> Void,
        reloadSnapshots: () async throws -> Void
    ) async throws {
        await invalidateUndo(remoteChange.changedRecords)
        try await migrateColors()
        try await reloadSnapshots()
    }
}
