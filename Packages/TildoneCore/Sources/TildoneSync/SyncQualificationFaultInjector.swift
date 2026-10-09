#if DEBUG
import Foundation
import TildoneDomain
import TildonePersistence

/// A one-shot presentation failure restricted to a fixed synthetic fixture.
/// It never writes the store, changes an engine cursor, or selects user content.
public actor SyncQualificationFaultInjector {
    public enum Fault: Error, Equatable { case syntheticRemoteRefresh }

    private let armed: Bool
    private var didInject = false

    public init(armed: Bool = ProcessInfo.processInfo.arguments.contains(
        "--fail-stage12-synthetic-remote-refresh-once"
    )) {
        self.armed = armed
    }

    public func check(
        in repository: TildoneRepository,
        changedRecords: Set<DomainRecordID>
    ) async throws {
        guard armed, !didInject else { return }
        let snapshot = try await repository.qualificationSnapshot(.offline)
        guard snapshot.notes.count == 1 else { return }
        let syntheticIDs = Set(snapshot.notes.map { DomainRecordID.note($0.id) } +
            snapshot.tasks.map { DomainRecordID.task($0.id) })
        let markers = snapshot.tasks.filter {
            $0.lifecycle != .deleted && $0.text == "Stage12 refresh failure 20261009"
        }
        guard markers.count == 1,
              changedRecords.isSubset(of: syntheticIDs),
              changedRecords.contains(.task(markers[0].id)),
              !didInject else { return }
        didInject = true
        SyncDiagnostics.boundary(.refreshFailureInjected, count: 1)
        throw Fault.syntheticRemoteRefresh
    }
}
#endif
