//
//  SyncPersistentState.swift
//  Tildone
//
import CloudKit
import Foundation
import TildonePersistence

struct SyncPersistentState: Codable, Hashable, Sendable {
    static let currentVersion = 1

    var version = currentVersion
    var engineSerialization: Data?
    var systemFieldsByRecordName: [String: Data] = [:]
    var zoneCreated = false
    var zoneResetRequired = false

    init() {}

    init(data: Data?) {
        guard let data,
              let decoded = try? PropertyListDecoder().decode(Self.self, from: data),
              decoded.version == Self.currentVersion else { return }
        self = decoded
    }

    func encoded() throws -> Data {
        try PropertyListEncoder().encode(self)
    }

    var decodedEngineSerialization: CKSyncEngine.State.Serialization? {
        guard let engineSerialization else { return nil }
        return try? PropertyListDecoder().decode(
            CKSyncEngine.State.Serialization.self,
            from: engineSerialization
        )
    }

    mutating func setEngineSerialization(_ serialization: CKSyncEngine.State.Serialization) throws {
        engineSerialization = try PropertyListEncoder().encode(serialization)
    }

    mutating func storeSystemFields(for record: CKRecord) throws {
        systemFieldsByRecordName[record.recordID.recordName] = try Self.encodeSystemFields(record)
    }

    func systemRecord(named recordName: String) -> CKRecord? {
        guard let data = systemFieldsByRecordName[recordName] else { return nil }
        return try? Self.decodeSystemFields(data)
    }

    private static func encodeSystemFields(_ record: CKRecord) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return archiver.encodedData
    }

    private static func decodeSystemFields(_ data: Data) throws -> CKRecord {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        guard let record = CKRecord(coder: unarchiver) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return record
    }
}

actor SyncCoordinatorState {
    private(set) var persistent: SyncPersistentState
    private var inFlight: [String: UUID] = [:]
    private(set) var frozen: Bool
    private let repository: TildoneRepository

    init(persistent: SyncPersistentState, repository: TildoneRepository) {
        self.persistent = persistent
        self.repository = repository
        frozen = persistent.zoneResetRequired
    }

    func snapshot() -> SyncPersistentState { persistent }

    func isFrozen() -> Bool { frozen }

    func systemRecord(named name: String) -> CKRecord? {
        persistent.systemRecord(named: name)
    }

    func markInFlight(recordName: String, mutationID: UUID) {
        inFlight[recordName] = mutationID
    }

    func takeInFlight(recordName: String) -> UUID? {
        inFlight.removeValue(forKey: recordName)
    }

    func storeSystemFields(_ record: CKRecord) async throws {
        try persistent.storeSystemFields(for: record)
        try await persist()
    }

    func updateEngineSerialization(
        _ serialization: CKSyncEngine.State.Serialization
    ) async throws {
        try persistent.setEngineSerialization(serialization)
        try await persist()
    }

    func markZoneCreated() async throws {
        persistent.zoneCreated = true
        persistent.zoneResetRequired = false
        try await persist()
    }

    func freezeForZoneReset() async throws {
        persistent.zoneResetRequired = true
        frozen = true
        try await persist()
    }

    func freeze() { frozen = true }

    private func persist() async throws {
        try await repository.storeFutureSyncEngineState(persistent.encoded())
    }
}
