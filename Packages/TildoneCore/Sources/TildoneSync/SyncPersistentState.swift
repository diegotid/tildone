//
//  SyncPersistentState.swift
//  Tildone
//
import CloudKit
import Foundation
import TildoneDomain
import TildonePersistence

struct SyncPersistentState: Codable, Hashable, Sendable {
    static let currentVersion = 1

    var version = currentVersion
    var engineSerialization: Data?
    var systemFieldsByRecordName: [String: Data] = [:]
    var clientRegistrationsByReplicaID: [String: SyncClientRegistration] = [:]
    var zoneCreated = false
    var zoneResetRequired = false

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version
        case engineSerialization
        case systemFieldsByRecordName
        case clientRegistrationsByReplicaID
        case zoneCreated
        case zoneResetRequired
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        engineSerialization = try container.decodeIfPresent(Data.self, forKey: .engineSerialization)
        systemFieldsByRecordName = try container.decodeIfPresent(
            [String: Data].self,
            forKey: .systemFieldsByRecordName
        ) ?? [:]
        clientRegistrationsByReplicaID = try container.decodeIfPresent(
            [String: SyncClientRegistration].self,
            forKey: .clientRegistrationsByReplicaID
        ) ?? [:]
        zoneCreated = try container.decodeIfPresent(Bool.self, forKey: .zoneCreated) ?? false
        zoneResetRequired = try container.decodeIfPresent(
            Bool.self,
            forKey: .zoneResetRequired
        ) ?? false
    }

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

    func clientRegistration(replicaID: ReplicaID) -> SyncClientRegistration? {
        clientRegistrationsByReplicaID[replicaID.stringValue]
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

    @discardableResult
    func storeClientRegistration(
        _ registration: SyncClientRegistration,
        record: CKRecord
    ) async throws -> Bool {
        let key = registration.replicaID.stringValue
        if let existing = persistent.clientRegistrationsByReplicaID[key],
           existing.lastSeenAt > registration.lastSeenAt {
            return false
        }
        let changed = persistent.clientRegistrationsByReplicaID[key] != registration
        persistent.clientRegistrationsByReplicaID[key] = registration
        try persistent.storeSystemFields(for: record)
        try await persist()
        return changed
    }

    @discardableResult
    func removeClientRegistration(recordName: String) async throws -> Bool {
        guard let replicaID = SyncClientRegistration.replicaID(recordName: recordName) else {
            return false
        }
        persistent.systemFieldsByRecordName[recordName] = nil
        let removed = persistent.clientRegistrationsByReplicaID.removeValue(
            forKey: replicaID.stringValue
        ) != nil
        try await persist()
        return removed
    }

    func updateEngineSerialization(
        _ serialization: CKSyncEngine.State.Serialization
    ) async throws {
        try persistent.setEngineSerialization(serialization)
        try await persist()
    }

    func markZoneCreated() async throws -> Bool {
        guard !frozen, !persistent.zoneResetRequired else { return false }
        persistent.zoneCreated = true
        persistent.zoneResetRequired = false
        try await persist()
        return true
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
