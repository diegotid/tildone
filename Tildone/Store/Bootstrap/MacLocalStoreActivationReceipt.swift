import Foundation
import TildonePersistence

/// A native Mac workspace is admitted while empty, before presentation can
/// write content. This receipt cannot stand in for legacy migration evidence.
struct MacLocalStoreActivationReceipt: Codable {
    let formatVersion: Int
    let replicaID: String

    static func url(for descriptor: PersistenceStoreDescriptor) throws -> URL {
        guard descriptor.workspace == .localOnly,
              let store = try TildoneRepository.storeURL(for: descriptor) else {
            throw MacSharedStoreBootstrapError.unverifiedSharedStore
        }
        return store.deletingLastPathComponent()
            .appendingPathComponent("native-local-activation.json")
    }

    static func validateOrCreate(
        for repository: TildoneRepository,
        descriptor: PersistenceStoreDescriptor
    ) async throws {
        let workspace = try await repository.workspaceSnapshot()
        let audit = try await repository.legacyMigrationAudit()
        guard workspace.identityKind == "local-only",
              workspace.opaqueWorkspaceID == nil,
              audit.mappingCount == 0 else {
            throw MacSharedStoreBootstrapError.unverifiedSharedStore
        }
        let receiptURL = try url(for: descriptor)
        if FileManager.default.fileExists(atPath: receiptURL.path) {
            guard let receipt = try? JSONDecoder().decode(
                Self.self, from: Data(contentsOf: receiptURL)
            ), receipt.formatVersion == 1,
               receipt.replicaID == workspace.replicaID.stringValue else {
                throw MacSharedStoreBootstrapError.unverifiedSharedStore
            }
            return
        }

        // An unmarked populated store remains blocked. Never infer native
        // origin from missing legacy evidence or from visible-note count alone.
        let quarantine = try await repository.quarantinedRecords()
        guard audit.noteCount == 0, audit.taskCount == 0,
              audit.pendingMutationCount == 0,
              workspace.logicalCounter == 0,
              workspace.futureSyncEngineState == nil,
              quarantine.isEmpty else {
            throw MacSharedStoreBootstrapError.unverifiedSharedStore
        }
        let receipt = Self(formatVersion: 1, replicaID: workspace.replicaID.stringValue)
        let data = try JSONEncoder().encode(receipt)
        // The repository retains its exclusive workspace lease throughout the
        // admission. A failed write leaves the empty store unpresented.
        try data.write(to: receiptURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: receiptURL.path
        )
    }
}
