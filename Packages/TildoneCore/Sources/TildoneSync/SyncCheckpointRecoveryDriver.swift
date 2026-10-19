import Foundation

/// Finish and release each attempt's stack before beginning recovery. A second
/// failure remains visible and durable; one request cannot retry indefinitely.
enum SyncCheckpointRecoveryDriver {
    static func run(
        retryAfterRecovery: Bool,
        attempt: @escaping @Sendable () async -> Void,
        recoveryIsRequired: @escaping @Sendable () async -> Bool
    ) async {
        await attempt()
        guard retryAfterRecovery, await recoveryIsRequired() else { return }
        await attempt()
    }
}
