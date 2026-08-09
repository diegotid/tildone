//
//  SyncTransportControl.swift
//  Tildone
//
//  Account-scoped transport intent. This state never selects or migrates a
//  workspace and deliberately lives outside the shared content schema.
//

import Foundation

public enum SyncTransportState: String, Codable, Hashable, Sendable {
    case active
    case paused
}

/// A small installation-local preference store keyed by the opaque account
/// workspace UUID. Missing state preserves the Debug automatic-sync default;
/// malformed state fails safely to paused.
public struct SyncTransportStateStore: @unchecked Sendable {
    private static let keyPrefix = "syncTransportState."

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func state(for workspaceID: UUID) -> SyncTransportState {
        let key = Self.storageKey(for: workspaceID)
        guard let stored = defaults.object(forKey: key) else { return .active }
        guard let rawValue = stored as? String,
              let state = SyncTransportState(rawValue: rawValue) else {
            return .paused
        }
        return state
    }

    public func set(_ state: SyncTransportState, for workspaceID: UUID) {
        defaults.set(state.rawValue, forKey: Self.storageKey(for: workspaceID))
    }

    static func storageKey(for workspaceID: UUID) -> String {
        keyPrefix + workspaceID.uuidString.lowercased()
    }
}

public enum SyncTransportActivationPolicy {
    /// Build/test policy remains authoritative. A user preference can pause an
    /// otherwise enabled transport, but it can never enable a disabled build.
    public static func shouldActivate(
        enabledByDefault: Bool,
        persistedState: SyncTransportState
    ) -> Bool {
        enabledByDefault && persistedState == .active
    }
}
