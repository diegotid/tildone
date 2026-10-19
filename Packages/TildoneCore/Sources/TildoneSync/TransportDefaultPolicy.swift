//
//  TransportDefaultPolicy.swift
//  Tildone
//
//  One symmetric build/test default shared by both platform bootstrappers.
//

public enum TransportBuildMode: Hashable, Sendable {
    case debug
    case release

    /// Matches the platform's Debug/Release entitlement selection independently
    /// of installation-local transport intent.
    public var cloudKitEnvironment: CloudKitEnvironment {
        switch self {
        case .debug: .development
        case .release: .production
        }
    }
}

public enum TransportDefaultPolicy {
    /// Both build configurations synchronize except in test processes.
    public static func isEnabled(
        buildMode: TransportBuildMode,
        isTestProcess: Bool
    ) -> Bool {
        !isTestProcess
    }
}
