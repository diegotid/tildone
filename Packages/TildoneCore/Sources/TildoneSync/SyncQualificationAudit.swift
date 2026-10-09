#if DEBUG
import CloudKit
import CryptoKit
import Foundation
import OSLog
import TildoneDomain
import TildonePersistence

/// Opt-in local comparisons. Only fixed categories, counts and SHA-256 digests
/// leave this type; domain payloads and opaque identifiers stay in process.
enum SyncQualificationAudit {
    private struct WorkspaceIdentity: Encodable {
        let kind: String
        let workspace: String?
        let replica: ReplicaID
    }

    private struct ServerReceipt: Encodable {
        let type: String
        let name: String
        let zone: String
        let owner: String
        let changeTag: String?
        let created: Date?
        let modified: Date?

        init(_ record: CKRecord) {
            type = record.recordType
            name = record.recordID.recordName
            zone = record.recordID.zoneID.zoneName
            owner = record.recordID.zoneID.ownerName
            changeTag = record.recordChangeTag
            created = record.creationDate
            modified = record.modificationDate
        }
    }

    private enum Component: String {
        case notes, tasks, tombstones, pending, workspace, counter
        case engineEnvelope = "engine-envelope"
        case systemFields = "system-fields"
        case serverReceipts = "server-receipts"
        case clients
        case canonicalClients = "canonical-clients"
        case ownClient = "own-client"
        case iPhoneClients = "iphone-clients"
        case iPadClients = "ipad-clients"
        case macClients = "mac-clients"
    }

    private static let logger = Logger(subsystem: "studio.cuatro.tildone", category: "CloudKitSync")

    static func inspect(in repository: TildoneRepository, phase: SyncDiagnostics.QualificationPhase) async {
        guard ProcessInfo.processInfo.arguments.contains("--inspect-stage12-synthetic-state") else { return }
        do {
            for fixture in TildoneRepository.QualificationFixture.allCases {
                let snapshot = try await repository.qualificationSnapshot(fixture)
                let state = SyncPersistentState(data: snapshot.workspace.futureSyncEngineState)
                let names = (snapshot.notes.map { $0.id.recordName } + snapshot.tasks.map { $0.id.recordName }).sorted()
                let systemFields = names.reduce(into: [String: Data]()) { result, name in
                    result[name] = state.systemFieldsByRecordName[name]
                }
                let receipts = names.compactMap { state.systemRecord(named: $0).map(ServerReceipt.init) }
                try emit(snapshot.notes, fixture, phase, .notes, count: snapshot.notes.count)
                try emit(snapshot.tasks, fixture, phase, .tasks, count: snapshot.tasks.count)
                let tombstones = snapshot.tasks.filter { $0.lifecycle == .deleted }
                try emit(tombstones, fixture, phase, .tombstones, count: tombstones.count)
                try emit(snapshot.pending, fixture, phase, .pending, count: snapshot.pending.count)
                try emit(WorkspaceIdentity(kind: snapshot.workspace.identityKind,
                                           workspace: snapshot.workspace.opaqueWorkspaceID,
                                           replica: snapshot.workspace.replicaID),
                         fixture, phase, .workspace, count: 1)
                try emit(snapshot.workspace.logicalCounter, fixture, phase, .counter, count: 1)
                // Compare raw retained bytes within one replica across pause/restart.
                // Cross-device equality instead uses canonical domain/receipt digests.
                try emit(snapshot.workspace.futureSyncEngineState, fixture, phase, .engineEnvelope,
                         count: snapshot.workspace.futureSyncEngineState == nil ? 0 : 1)
                try emit(systemFields, fixture, phase, .systemFields, count: systemFields.count)
                try emit(receipts, fixture, phase, .serverReceipts, count: receipts.count)
                if fixture == .offline {
                    // These are content-free advisory registrations already
                    // received by CKSyncEngine; this does not query CloudKit.
                    let registrations = state.clientRegistrationsByReplicaID
                    let clients = registrations.values.sorted { $0.recordName < $1.recordName }
                    let canonical = clients.filter { client in
                        registrations[client.replicaID.stringValue] == client &&
                        client.schemaVersion == SyncClientRegistration.currentSchemaVersion &&
                        SyncClientRegistration.replicaID(recordName: client.recordName) == client.replicaID &&
                        state.systemRecord(named: client.recordName).map {
                            $0.recordType == "TDClient" &&
                            $0.recordID.zoneID == TildoneCloudSchema.zoneID &&
                            $0.modificationDate == client.lastSeenAt
                        } == true
                    }
                    let own = canonical.filter { $0.replicaID == snapshot.workspace.replicaID }
                    try emit(clients, fixture, phase, .clients, count: clients.count)
                    try emit(canonical, fixture, phase, .canonicalClients, count: canonical.count)
                    try emit(own, fixture, phase, .ownClient, count: own.count)
                    for (platform, component) in [
                        (SyncClientPlatform.iPhone, Component.iPhoneClients),
                        (.iPad, .iPadClients), (.mac, .macClients)
                    ] {
                        let selected = clients.filter { $0.platform == platform }
                        try emit(selected, fixture, phase, component, count: selected.count)
                    }
                }
            }
        } catch {
            SyncDiagnostics.boundary(.qualificationInspectionFailed, count: 1)
        }
    }

    private static func emit<Value: Encodable>(
        _ value: Value, _ fixture: TildoneRepository.QualificationFixture,
        _ phase: SyncDiagnostics.QualificationPhase, _ component: Component, count: Int
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(value))
            .map { String(format: "%02x", $0) }.joined()
        logger.debug("sync-audit fixture=\(fixture.rawValue, privacy: .public) phase=\(phase.rawValue, privacy: .public) component=\(component.rawValue, privacy: .public) count=\(count, privacy: .public) sha256=\(digest, privacy: .public)")
        print("TildoneQualificationAudit fixture=\(fixture.rawValue) phase=\(phase.rawValue) component=\(component.rawValue) count=\(count) sha256=\(digest)")
    }
}
#endif
