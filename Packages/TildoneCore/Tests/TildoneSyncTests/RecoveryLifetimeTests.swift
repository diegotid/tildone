import Foundation
import XCTest
import TildoneDomain
import TildonePersistence
@testable import TildoneSync

/// Exercises the production retry/retirement driver with an explicit fake SDK
/// boundary. The real in-memory outbox/state remains in the workflow.
final class RecoveryLifetimeTests: XCTestCase {
    func testRecoveryReleasesFailedFetchFrameBeforeConstructingNextEngine() async throws {
        let harness = try await Harness.make(failures: 1)
        let queued = try await harness.pending()
        await harness.run(allowRetry: true)
        let result = await harness.result()
        XCTAssertEqual(result.attempts, 2)
        XCTAssertEqual(result.created, 2)
        XCTAssertEqual(result.maximumLive, 1)
        XCTAssertEqual(result.retirementFailures, 0)
        XCTAssertFalse(result.recoveryRequired)
        XCTAssertEqual(result.trace, ["create-1", "fetch-1", "failed-1", "cancel-1", "release-1", "create-2", "fetch-2", "committed-2"])
        let after = try await harness.pending()
        XCTAssertEqual(after, queued)
    }

    func testExternalOutstandingReferenceBlocksReplacementAndPreservesRecoveryWork() async throws {
        let harness = try await Harness.make(failures: 1)
        let queued = try await harness.pending()
        let outstanding = await harness.retainCurrentEngine()
        await harness.run(allowRetry: true)
        withExtendedLifetime(outstanding) {}
        let result = await harness.result()
        XCTAssertEqual(result.attempts, 2)
        XCTAssertEqual(result.created, 1)
        XCTAssertEqual(result.maximumLive, 1)
        XCTAssertEqual(result.retirementFailures, 1)
        XCTAssertTrue(result.recoveryRequired)
        XCTAssertTrue(result.frozen)
        let after = try await harness.pending()
        XCTAssertEqual(after, queued)
    }

    func testRetainedEngineBeforeFirstAttemptFreezesLaterCheckpointRequests() async throws {
        let harness = try await Harness.make(failures: 0, initialRecovery: true)
        let queued = try await harness.pending()
        let outstanding = await harness.retainCurrentEngine()
        await harness.run(allowRetry: true)
        await harness.run(allowRetry: true)
        withExtendedLifetime(outstanding) {}
        let result = await harness.result()
        XCTAssertEqual(result.attempts, 1)
        XCTAssertEqual(result.created, 1)
        XCTAssertEqual(result.maximumLive, 1)
        XCTAssertEqual(result.retirementFailures, 1)
        XCTAssertTrue(result.recoveryRequired)
        XCTAssertTrue(result.frozen)
        let after = try await harness.pending()
        XCTAssertEqual(after, queued)
    }

    func testRepeatedRecoveryFailureStopsAfterOneRetryWithoutDrainingQueue() async throws {
        let harness = try await Harness.make(failures: 10)
        let queued = try await harness.pending()
        await harness.run(allowRetry: true)
        let result = await harness.result()
        XCTAssertEqual(result.attempts, 2)
        XCTAssertEqual(result.created, 2)
        XCTAssertEqual(result.maximumLive, 1)
        XCTAssertTrue(result.recoveryRequired)
        let after = try await harness.pending()
        XCTAssertEqual(after, queued)
    }

    func testSessionFrozenAfterFailureDoesNotStartRecoveryReplacement() async throws {
        let harness = try await Harness.make(failures: 1, freezeAfterFailure: true)
        let queued = try await harness.pending()
        await harness.run(allowRetry: true)
        let result = await harness.result()
        XCTAssertEqual(result.attempts, 1)
        XCTAssertEqual(result.created, 1)
        XCTAssertTrue(result.frozen)
        XCTAssertTrue(result.recoveryRequired)
        let after = try await harness.pending()
        XCTAssertEqual(after, queued)
    }

    func testCallerCanSuppressImmediateRecoveryRetry() async throws {
        let harness = try await Harness.make(failures: 1)
        await harness.run(allowRetry: false)
        let result = await harness.result()
        XCTAssertEqual(result.attempts, 1)
        XCTAssertEqual(result.created, 1)
        XCTAssertTrue(result.recoveryRequired)
    }

    private final class Trace: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [String] = []
        private var live = 0
        private var maximum = 0
        private var constructors = 0

        func created() -> Int {
            lock.lock()
            defer { lock.unlock() }
            constructors += 1
            live += 1
            maximum = max(maximum, live)
            events.append("create-\(constructors)")
            return constructors
        }

        func released(_ id: Int) {
            lock.lock()
            defer { lock.unlock() }
            live -= 1
            events.append("release-\(id)")
        }

        func add(_ event: String) {
            lock.lock()
            defer { lock.unlock() }
            events.append(event)
        }

        func snapshot() -> (events: [String], created: Int, maximumLive: Int) {
            lock.lock()
            defer { lock.unlock() }
            return (events, constructors, maximum)
        }
    }

    private final class Engine: @unchecked Sendable {
        let id: Int
        let trace: Trace
        init(trace: Trace) { self.trace = trace; id = trace.created() }
        deinit { trace.released(id) }
    }

    private actor Harness {
        struct Result {
            let attempts: Int
            let created: Int
            let maximumLive: Int
            let retirementFailures: Int
            let recoveryRequired: Bool
            let frozen: Bool
            let trace: [String]
        }

        let repository: TildoneRepository
        let state: SyncCoordinatorState
        let trace = Trace()
        var engine: Engine?
        var failures: Int
        var attempts = 0
        var retirementFailures = 0
        let freezeAfterFailure: Bool

        init(repository: TildoneRepository, state: SyncCoordinatorState,
             failures: Int, freezeAfterFailure: Bool) {
            self.repository = repository
            self.state = state
            self.failures = failures
            self.freezeAfterFailure = freezeAfterFailure
            engine = Engine(trace: trace)
        }

        static func make(failures: Int, freezeAfterFailure: Bool = false, initialRecovery: Bool = false) async throws -> Harness {
            let repository = try TildoneRepository(descriptor: .inMemory(workspace: .account(UUID())))
            let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let note = try await repository.createNote(id: NoteID(), createdAt: date, title: "Recovery lifetime fixture")
            let task = try await repository.addTask(id: TaskID(), to: note.id, createdAt: date,
                                                   text: "Retained deletion", orderToken: OrderToken(rawValue: "m"))
            try await repository.deleteTask(id: task.id)
            var persistent = SyncPersistentState()
            persistent.zoneCreated = true
            persistent.fullReconciliationRequired = initialRecovery
            persistent.completedReconciliationVersion = SyncPersistentState.currentReconciliationVersion
            try await repository.storeFutureSyncEngineState(persistent.encoded())
            return Harness(repository: repository,
                           state: SyncCoordinatorState(persistent: persistent, repository: repository),
                           failures: failures, freezeAfterFailure: freezeAfterFailure)
        }

        func pending() async throws -> [PendingMutationSnapshot] {
            try await repository.pendingMutations(includeSuperseded: true)
        }

        func retainCurrentEngine() -> Engine? { engine }
        func takeEngine() -> Engine? { let previous = engine; engine = nil; return previous }

        func run(allowRetry: Bool) async {
            guard !(await state.isFrozen()) else { return }
            await SyncCheckpointRecoveryDriver.run(
                retryAfterRecovery: allowRetry,
                attempt: { await self.attempt() },
                recoveryIsRequired: {
                    let required = await self.state.requiresFullReconciliation()
                    let frozen = await self.state.isFrozen()
                    return required && !frozen
                }
            )
        }

        func attempt() async {
            attempts += 1
            if await state.requiresFullReconciliation() {
                do {
                    _ = try await SyncEngineRetirement.retire(
                        takeEngine: { await self.takeEngine() },
                        cancel: { self.trace.add("cancel-\($0.id)") },
                        freezeSession: { await self.state.freeze() }
                    )
                } catch {
                    retirementFailures += 1
                    return
                }
                guard !(await state.isFrozen()) else { return }
                engine = Engine(trace: trace)
            }
            guard let engine else { return }
            await fetch(engine)
        }

        func fetch(_ retainedEngine: Engine) async {
            trace.add("fetch-\(retainedEngine.id)")
            if failures > 0 {
                failures -= 1
                try? await state.requireFullReconciliation()
                trace.add("failed-\(retainedEngine.id)")
                if freezeAfterFailure { await state.freeze() }
                return
            }
            await state.beginFetch()
            await state.recordRequiredZoneFetchCompletion(succeeded: true)
            try? await state.updateEncodedEngineSerialization(Data([9, 8, 7]))
            if (try? await state.completeFetch()) == true {
                trace.add("committed-\(retainedEngine.id)")
            }
        }

        func result() async -> Result {
            let values = trace.snapshot()
            return Result(attempts: attempts, created: values.created,
                          maximumLive: values.maximumLive, retirementFailures: retirementFailures,
                          recoveryRequired: await state.requiresFullReconciliation(), frozen: await state.isFrozen(),
                          trace: values.events)
        }
    }
}
