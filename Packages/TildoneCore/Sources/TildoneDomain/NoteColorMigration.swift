//
//  NoteColorMigration.swift
//  Tildone
//
//  Deterministic authority for the one-time V1/V2 note-color backfill.
//
import Foundation

/// Identifies values synthesized by the V2-to-V3 color migration without
/// adding a CloudKit field. The original replica suffix remains in the stamp,
/// so two migrations at the same counter still have a deterministic order.
public enum NoteColorMigrationAuthority: Int, Hashable, Sendable {
    /// A platform fallback used when no legacy Mac color exists.
    case platformDefault = 1
    /// The per-note or global color retained by the legacy Mac installation.
    case legacyMac = 2

    private var replicaPrefix: String {
        switch self {
        case .platformDefault: "54444950-484f-4e45" // "TDIPHONE"
        case .legacyMac: "54444d41-4343-4f4c" // "TDMACCOL"
        }
    }

    public func migrationReplicaID(sourceReplicaID: ReplicaID) -> ReplicaID {
        let source = sourceReplicaID.rawValue.uuid
        let prefix: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = switch self {
        case .platformDefault: (0x54, 0x44, 0x49, 0x50, 0x48, 0x4f, 0x4e, 0x45)
        case .legacyMac: (0x54, 0x44, 0x4d, 0x41, 0x43, 0x43, 0x4f, 0x4c)
        }
        return ReplicaID(UUID(uuid: (
            prefix.0, prefix.1, prefix.2, prefix.3,
            prefix.4, prefix.5, prefix.6, prefix.7,
            source.8, source.9, source.10, source.11,
            source.12, source.13, source.14, source.15
        )))
    }

    public static func authority(for replicaID: ReplicaID) -> Self? {
        let prefix = String(replicaID.stringValue.prefix(18))
        return Self.allCasesByPriority.first { $0.replicaPrefix == prefix }
    }

    private static let allCasesByPriority: [Self] = [.legacyMac, .platformDefault]
}
