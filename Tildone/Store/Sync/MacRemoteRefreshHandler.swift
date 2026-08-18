//
//  MacRemoteRefreshHandler.swift
//  Tildone
//

import Foundation

enum MacRemoteRefreshHandler {
    static func run(
        migrateColors: () async throws -> Void,
        reloadSnapshots: () async throws -> Void
    ) async throws {
        try await migrateColors()
        try await reloadSnapshots()
    }
}
