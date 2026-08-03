//
//  SyncClientRegistration.swift
//  Tildone
//
import Foundation
import TildoneDomain

public enum SyncClientPlatform: String, Codable, Hashable, Sendable {
    case iPhone
    case iPad
    case mac
}

/// Content-free aggregate of recently active installations. Counts exclude
/// the installation presenting the status, which is represented separately.
public struct SyncDeviceSummary: Codable, Hashable, Sendable {
    public let currentPlatform: SyncClientPlatform
    public let otherIPhoneCount: Int
    public let otherIPadCount: Int
    public let otherMacCount: Int

    public init(
        currentPlatform: SyncClientPlatform,
        otherIPhoneCount: Int = 0,
        otherIPadCount: Int = 0,
        otherMacCount: Int = 0
    ) {
        self.currentPlatform = currentPlatform
        self.otherIPhoneCount = max(0, otherIPhoneCount)
        self.otherIPadCount = max(0, otherIPadCount)
        self.otherMacCount = max(0, otherMacCount)
    }

    public var totalDeviceCount: Int {
        1 + otherIPhoneCount + otherIPadCount + otherMacCount
    }
}

/// Content-free evidence that one Tildone installation has recently completed
/// a CloudKit checkpoint. The timestamp comes from CloudKit's server metadata,
/// not from a client-controlled record field.
public struct SyncClientRegistration: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1
    static let recordNamePrefix = "client-"

    public let replicaID: ReplicaID
    public let platform: SyncClientPlatform
    public let lastSeenAt: Date
    public let schemaVersion: Int

    public init(
        replicaID: ReplicaID,
        platform: SyncClientPlatform,
        lastSeenAt: Date,
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.replicaID = replicaID
        self.platform = platform
        self.lastSeenAt = lastSeenAt
        self.schemaVersion = schemaVersion
    }

    public var recordName: String {
        Self.recordNamePrefix + replicaID.stringValue
    }

    static func replicaID(recordName: String) -> ReplicaID? {
        guard recordName.hasPrefix(recordNamePrefix) else { return nil }
        let value = String(recordName.dropFirst(recordNamePrefix.count))
        guard let replicaID = ReplicaID(string: value), value == replicaID.stringValue else {
            return nil
        }
        return replicaID
    }
}

enum SyncClientActivityPolicy {
    static let heartbeatInterval: TimeInterval = 24 * 60 * 60
    static let activeWindow: TimeInterval = 90 * 24 * 60 * 60

    static func shouldRefresh(
        registration: SyncClientRegistration?,
        at date: Date
    ) -> Bool {
        guard let registration else { return true }
        return date.timeIntervalSince(registration.lastSeenAt) >= heartbeatInterval
    }

    static func activeDeviceSummary(
        registrations: [String: SyncClientRegistration],
        currentReplicaID: ReplicaID,
        currentPlatform: SyncClientPlatform,
        at date: Date
    ) -> SyncDeviceSummary {
        let cutoff = date.addingTimeInterval(-activeWindow)
        var seenReplicaIDs: Set<ReplicaID> = [currentReplicaID]
        var iPhoneCount = 0
        var iPadCount = 0
        var macCount = 0

        for registration in registrations.values where registration.lastSeenAt >= cutoff {
            guard seenReplicaIDs.insert(registration.replicaID).inserted else { continue }
            switch registration.platform {
            case .iPhone: iPhoneCount += 1
            case .iPad: iPadCount += 1
            case .mac: macCount += 1
            }
        }

        return SyncDeviceSummary(
            currentPlatform: currentPlatform,
            otherIPhoneCount: iPhoneCount,
            otherIPadCount: iPadCount,
            otherMacCount: macCount
        )
    }
}
