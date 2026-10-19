import Foundation

/// Scope the last owned strong reference to a completed cancellation frame.
/// Public-object release does not assert private SDK actor teardown.
enum SyncEngineRetirement {
    enum Failure: Error { case engineStillRetained }

    final class Observation<Engine: AnyObject>: @unchecked Sendable {
        private weak var engine: Engine?
        let hadEngine: Bool

        init(_ engine: Engine?) {
            self.engine = engine
            hadEngine = engine != nil
        }

        var isReleased: Bool { engine == nil }
    }

    static func release<Engine: AnyObject & Sendable>(
        takeEngine: @escaping @Sendable () async -> Engine?,
        cancel: @escaping @Sendable (Engine) async -> Void
    ) async -> Observation<Engine> {
        let previous = await takeEngine()
        let observation = Observation(previous)
        if let previous { await cancel(previous) }
        return observation
    }
    /// One shared boundary owns the rejection policy as well as releasing the
    /// cancellation frame, so callers cannot accidentally retry past a hold.
    static func retire<Engine: AnyObject & Sendable>(
        takeEngine: @escaping @Sendable () async -> Engine?,
        cancel: @escaping @Sendable (Engine) async -> Void,
        freezeSession: @escaping @Sendable () async -> Void
    ) async throws -> Observation<Engine> {
        let observation = await release(takeEngine: takeEngine, cancel: cancel)
        guard observation.isReleased else {
            // The engine property was already cleared. Freeze the entire
            // session so a later attempt cannot mistake nil for safe retirement.
            await freezeSession()
            throw Failure.engineStillRetained
        }
        return observation
    }

}
