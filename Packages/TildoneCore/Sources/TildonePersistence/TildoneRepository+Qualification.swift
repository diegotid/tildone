import Foundation
import SwiftData
import TildoneDomain

#if DEBUG
extension TildoneRepository {
    /// Fixed synthetic fixtures only: this API cannot select personal titles.
    public enum QualificationFixture: String, CaseIterable, Sendable {
        case offline
        case fields
        case memo

        public var title: String {
            switch self {
            case .offline: "Stage12 Mac Offline 20261007"
            case .fields: "Stage12 Canonical Fields 20261008"
            case .memo: "Stage12 Canonical Memo 20261008"
            }
        }
    }

    /// A synchronous actor read keeps these payloads and metadata consistent.
    /// Deleted children are included so tombstone retention can be compared.
    public func qualificationSnapshot(_ fixture: QualificationFixture) throws -> (
        notes: [Note], tasks: [Task], pending: [PendingMutationSnapshot], workspace: WorkspaceSnapshot
    ) {
        let context = readContext()
        let title: String? = fixture.title
        let rows = try context.fetch(FetchDescriptor<StoredNote>(
            predicate: #Predicate { $0.title == title }
        ))
        let notes = try rows.map { try mappedNote(from: $0, in: context) }
            .sorted { $0.id.stringValue < $1.id.stringValue }
        guard Set(notes.map(\.id)).count == notes.count else {
            throw PersistenceError.duplicateID(.note, "qualification-fixture")
        }
        var tasks: [Task] = []
        for note in notes {
            let noteID = note.id.stringValue
            let children = try context.fetch(FetchDescriptor<StoredTask>(
                predicate: #Predicate { $0.noteStableID == noteID }
            ))
            tasks += try children.map { try mappedTask(from: $0, expectedNoteID: note.id, in: context) }
        }
        tasks.sort { $0.id.stringValue < $1.id.stringValue }
        guard Set(tasks.map(\.id)).count == tasks.count else {
            throw PersistenceError.duplicateID(.task, "qualification-fixture")
        }
        let targets = Set(notes.map { $0.id.stringValue } + tasks.map { $0.id.stringValue })
        let pending = try pendingMutations(includeSuperseded: true).filter {
            targets.contains($0.targetStableID)
        }
        return (notes, tasks, pending, try workspaceSnapshot())
    }
}
#endif
