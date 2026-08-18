//
//  MacNoteResolutionService.swift
//  Tildone
//

import CryptoKit
import Foundation
import TildoneDomain
import TildonePersistence

enum MacNoteResolutionService {
    /// Combines a stable snapshot into the account repository using the same
    /// deterministic field-level merge rules as normal sync. The local source
    /// remains intact. If it changes during the copy, the caller must leave the
    /// Mac selected and offer a safe retry instead of hiding uncopied edits.
    static func combine(
        localRepository: TildoneRepository,
        accountRepository: TildoneRepository,
        at date: Date
    ) async throws -> String {
        let source = try await snapshot(repository: localRepository)
        try await accountRepository.adoptSyncContent(
            notes: source.notes,
            tasks: source.tasks,
            at: date
        )
        try await localRepository.markCloudSeedingBegun(at: date)
        guard try await fingerprint(repository: localRepository) == source.fingerprint else {
            throw MacNoteResolutionError.sourceChangedDuringCopy
        }
        return source.fingerprint
    }

    static func fingerprint(repository: TildoneRepository) async throws -> String {
        try await snapshot(repository: repository).fingerprint
    }

    private static func snapshot(repository: TildoneRepository) async throws -> MacSyncContentSnapshot {
        struct EncodableSnapshot: Encodable {
            let notes: [TildoneDomain.Note]
            let tasks: [TildoneDomain.Task]
        }

        let notes = try await repository.allSyncNotes().sorted { $0.id < $1.id }
        let tasks = try await repository.allSyncTasks().sorted { $0.id < $1.id }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(EncodableSnapshot(
            notes: notes,
            tasks: tasks
        )))
        return MacSyncContentSnapshot(
            notes: notes,
            tasks: tasks,
            fingerprint: digest.map { String(format: "%02x", $0) }.joined()
        )
    }
}
