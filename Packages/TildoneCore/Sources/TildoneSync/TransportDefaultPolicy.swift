//
//  TransportDefaultPolicy.swift
//  Tildone
//
//  One symmetric build/test default shared by both platform bootstrappers.
//

public enum TransportBuildMode: Hashable, Sendable {
    case debug
    case release
}

public enum TransportDefaultPolicy {
    /// Debug apps synchronize automatically except under XCTest/UI testing.
    /// Release transport stays off until a later, explicitly authorized stage.
    public static func isEnabled(
        buildMode: TransportBuildMode,
        isTestProcess: Bool
    ) -> Bool {
        buildMode == .debug && !isTestProcess
    }
}
