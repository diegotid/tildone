import XCTest
import TildoneDomain
import TildonePersistence
import TildoneSync
@testable import Tildone

@MainActor
final class TildoneiOSTests: XCTestCase {
    func testNotesArePresentedInMeaningfulEditOrderWithUntitledFallback() async throws {
        let workspace = UUID()
        let repository = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspace)))
        let model = try await makeModel(repository: repository)
        let older = try await repository.createNote(
            id: NoteID(), createdAt: Date(timeIntervalSince1970: 100), title: nil
        )
        let newer = try await repository.createNote(
            id: NoteID(), createdAt: Date(timeIntervalSince1970: 200), title: "Later"
        )
        try await model.reloadNotes()

        XCTAssertEqual(model.notes.map(\.id), [newer.id, older.id])
        XCTAssertEqual(SyncStatusPresentation.title(for: .disabled), "Sync is disabled")
        XCTAssertEqual(older.title, nil)
    }

    func testCreateRenameAndDeleteNoteUsesRepositoryLifecycle() async throws {
        let model = try await makeModel()
        let note = try await model.createNote()
        try await model.rename(noteID: note.id, title: "  Groceries  ")
        XCTAssertEqual(model.notes.first?.title, "Groceries")

        try await model.delete(noteID: note.id)
        XCTAssertTrue(model.notes.isEmpty)
    }

    func testTaskEditingCompletionDeletionAndOrderingUseDomainCommands() async throws {
        let model = try await makeModel()
        let note = try await model.createNote(title: "Checklist")
        let createdFirst = try await model.addTask(noteID: note.id, text: "First", after: [])
        let first = try XCTUnwrap(createdFirst)
        let createdSecond = try await model.addTask(noteID: note.id, text: "Second", after: [first])
        let second = try XCTUnwrap(createdSecond)

        try await model.edit(taskID: second.id, text: "Changed")
        try await model.setCompletion(taskID: first.id, completed: true)
        try await model.move(taskID: second.id, in: [first, second], from: IndexSet(integer: 1), to: 0)
        let reordered = try await model.tasks(in: note.id)
        XCTAssertEqual(reordered.map(\.id), [second.id, first.id])
        XCTAssertEqual(reordered.first?.text, "Changed")
        XCTAssertTrue(reordered.last?.isCompleted == true)

        try await model.delete(taskID: first.id)
        let remaining = try await model.tasks(in: note.id)
        XCTAssertEqual(remaining.map(\.id), [second.id])
    }

    func testRemoteStyleRefreshDoesNotDuplicateRowsAndHidesTombstones() async throws {
        let workspace = UUID()
        let repository = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspace)))
        let model = try await makeModel(repository: repository)
        try await model.openForTesting(workspaceID: workspace)
        let note = try await repository.createNote(id: NoteID(), createdAt: Date(), title: "From Mac")

        try await model.reloadNotes()
        try await model.reloadNotes() // Redelivery/reload is idempotent for presentation.
        XCTAssertEqual(model.notes.map(\.id), [note.id])

        try await repository.deleteNote(id: note.id)
        try await model.reloadNotes()
        XCTAssertTrue(model.notes.isEmpty)
    }

    func testOfflineAndAttentionStatesRemainUnderstandable() async throws {
        let model = try await makeModel()
        let note = try await model.createNote()
        _ = try await model.addTask(noteID: note.id, text: "Works offline", after: [])
        let tasks = try await model.tasks(in: note.id)
        XCTAssertEqual(tasks.count, 1)

        for availability in [SyncAvailability.noAccount, .restricted, .adoptionRequired, .zoneResetRequired, .incompatibleRemoteData] {
            let status = SyncStatus(availability: availability, activity: .attentionNeeded)
            XCTAssertFalse(SyncStatusPresentation.title(for: status).isEmpty)
            XCTAssertNotNil(SyncStatusPresentation.detail(for: status))
        }

        let malformed = SyncStatus(
            availability: .available,
            activity: .attentionNeeded,
            issue: .malformedRemoteRecord
        )
        XCTAssertEqual(SyncStatusPresentation.title(for: malformed), "iCloud needs attention")
        XCTAssertEqual(
            SyncStatusPresentation.detail(for: malformed),
            "Some synchronized data could not be read. Local editing is still available."
        )
    }

    func testAccountChangeDropsOldWorkspaceImmediately() async throws {
        let workspaceA = UUID()
        let workspaceB = UUID()
        let repositoryA = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceA)))
        let repositoryB = try TildoneRepository(descriptor: .inMemory(workspace: .account(workspaceB)))
        let model = TildoneiOSApplicationModel(repositoryFactory: { workspace in
            switch workspace {
            case let .account(id) where id == workspaceA: return repositoryA
            case let .account(id) where id == workspaceB: return repositoryB
            default: throw PersistenceError.workspaceMismatch
            }
        }, synchronizationEnabled: false)
        try await model.openForTesting(workspaceID: workspaceA)
        _ = try await model.createNote(title: "Account A")
        XCTAssertFalse(model.notes.isEmpty)

        model.present(status: SyncStatus(availability: .accountChanged, activity: .attentionNeeded))
        XCTAssertFalse(model.hasWorkspace)
        XCTAssertTrue(model.notes.isEmpty)

        try await model.openForTesting(workspaceID: workspaceB)
        XCTAssertTrue(model.notes.isEmpty)
    }

    private func makeModel(repository: TildoneRepository? = nil) async throws -> TildoneiOSApplicationModel {
        let workspace = UUID()
        let repository = try repository ?? TildoneRepository(descriptor: .inMemory(workspace: .account(workspace)))
        let model = TildoneiOSApplicationModel(
            repositoryFactory: { _ in repository },
            synchronizationEnabled: false
        )
        try await model.openForTesting(workspaceID: workspace)
        return model
    }
}
