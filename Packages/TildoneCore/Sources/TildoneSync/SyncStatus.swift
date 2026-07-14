//
//  SyncStatus.swift
//  Tildone
//
import Foundation

public enum SyncAvailability: String, Codable, Hashable, Sendable {
    case disabled
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case adoptionRequired
    case accountChanged
    case zoneResetRequired
    case incompatibleRemoteData
}

public enum SyncActivity: String, Codable, Hashable, Sendable {
    case idle
    case syncing
    case offline
    case attentionNeeded
}

public enum SyncIssue: String, Codable, Hashable, Sendable {
    case network
    case service
    case quotaExceeded
    case permission
    case malformedRemoteRecord
    case futureSchema
    case accountChanged
    case zoneReset
    case unknown
}

/// Small presentation-neutral status. It contains no record IDs or content.
public struct SyncStatus: Codable, Hashable, Sendable {
    public let availability: SyncAvailability
    public let activity: SyncActivity
    public let pendingMutationCount: Int
    public let lastSuccessfulSyncAt: Date?
    public let issue: SyncIssue?

    public init(
        availability: SyncAvailability,
        activity: SyncActivity,
        pendingMutationCount: Int = 0,
        lastSuccessfulSyncAt: Date? = nil,
        issue: SyncIssue? = nil
    ) {
        self.availability = availability
        self.activity = activity
        self.pendingMutationCount = pendingMutationCount
        self.lastSuccessfulSyncAt = lastSuccessfulSyncAt
        self.issue = issue
    }

    public static let disabled = SyncStatus(availability: .disabled, activity: .idle)
}

public actor SyncStatusModel {
    private var value: SyncStatus
    private var continuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]

    public init(initialValue: SyncStatus = .disabled) {
        value = initialValue
    }

    public func snapshot() -> SyncStatus { value }

    public func updates() -> AsyncStream<SyncStatus> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(value)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    public func set(_ status: SyncStatus) {
        guard status != value else { return }
        value = status
        for continuation in continuations.values { continuation.yield(status) }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}
