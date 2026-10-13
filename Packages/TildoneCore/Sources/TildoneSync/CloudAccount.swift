//
//  CloudAccount.swift
//  Tildone
//
import CloudKit
import CryptoKit
import Foundation

public enum CloudAccountState: String, Codable, Hashable, Sendable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

public enum CloudKitEnvironment: String, Hashable, Sendable {
    case development = "Development"
    case production = "Production"
}

public struct CloudAccountSnapshot: Hashable, Sendable {
    public let state: CloudAccountState
    /// Stable, content-free workspace key derived from CloudKit's private user
    /// record ID. The source identifier is never exposed or logged.
    public let workspaceID: UUID?

    public init(state: CloudAccountState, workspaceID: UUID?) {
        self.state = state
        self.workspaceID = workspaceID
    }
}

public struct CloudAccountResolver: Sendable {
    public let environment: CloudKitEnvironment

    public init(environment: CloudKitEnvironment) {
        self.environment = environment
    }

    public func resolve(
        container: CKContainer = CKContainer(identifier: TildoneCloudSchema.containerIdentifier)
    ) async -> CloudAccountSnapshot {
        do {
            switch try await container.accountStatus() {
            case .available:
                let userID = try await container.userRecordID()
                return CloudAccountSnapshot(
                    state: .available,
                    workspaceID: Self.opaqueWorkspaceID(
                        containerIdentifier: TildoneCloudSchema.containerIdentifier,
                        userRecordName: userID.recordName,
                        environment: environment
                    )
                )
            case .noAccount:
                return CloudAccountSnapshot(state: .noAccount, workspaceID: nil)
            case .restricted:
                return CloudAccountSnapshot(state: .restricted, workspaceID: nil)
            case .temporarilyUnavailable:
                return CloudAccountSnapshot(state: .temporarilyUnavailable, workspaceID: nil)
            case .couldNotDetermine:
                return CloudAccountSnapshot(state: .couldNotDetermine, workspaceID: nil)
            @unknown default:
                return CloudAccountSnapshot(state: .couldNotDetermine, workspaceID: nil)
            }
        } catch {
            return CloudAccountSnapshot(state: .couldNotDetermine, workspaceID: nil)
        }
    }

    public static func opaqueWorkspaceID(
        containerIdentifier: String,
        userRecordName: String,
        environment: CloudKitEnvironment = .development
    ) -> UUID {
        // Preserve the existing Development UUID, paths and preferences. Give
        // Production a distinct namespace even if CloudKit returns the same
        // private user ID, so it cannot reuse Development cursors or receipts.
        let namespace = environment == .development
            ? containerIdentifier
            : containerIdentifier + "\u{0}" + environment.rawValue
        let digest = SHA256.hash(data: Data((namespace + "\u{0}" + userRecordName).utf8))
        var bytes = Array(digest.prefix(16))
        // RFC 4122-compatible deterministic UUID namespace/version bits.
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

public enum SyncAccountChange: String, Codable, Hashable, Sendable {
    case signedIn
    case signedOut
    case switched

    /// A sign-out or switch invalidates every handle associated with the
    /// current account-keyed workspace. Sign-in is resolved before opening a
    /// new workspace and therefore does not invalidate an existing nil session.
    public var requiresWorkspaceInvalidation: Bool {
        self == .signedOut || self == .switched
    }
}
