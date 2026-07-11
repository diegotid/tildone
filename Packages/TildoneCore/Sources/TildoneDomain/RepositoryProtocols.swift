import Foundation

/// Persistence-independent note operations. Implementations own version
/// generation and must return immutable domain snapshots across isolation.
public protocol NoteRepository: Sendable {
    func createNote(id: NoteID, createdAt: Date, title: String?) async throws -> Note
    func note(id: NoteID, includingDeleted: Bool) async throws -> Note
    func visibleNotes() async throws -> [Note]
    func notesMeaningfullyEdited(since date: Date) async throws -> [Note]
    func renameNote(id: NoteID, to title: String?, editedAt: Date) async throws -> Note
    func deleteNote(id: NoteID) async throws
    func restoreNote(id: NoteID) async throws -> Note
}

/// Persistence-independent task operations. Implementations enforce immutable
/// ownership and derive visibility and counts from domain lifecycle state.
public protocol TaskRepository: Sendable {
    func addTask(
        id: TaskID,
        to noteID: NoteID,
        createdAt: Date,
        text: String,
        orderToken: OrderToken
    ) async throws -> Task
    func task(id: TaskID, includingDeleted: Bool) async throws -> Task
    func orderedTasks(in noteID: NoteID) async throws -> [Task]
    func editTask(id: TaskID, text: String) async throws -> Task
    func setTaskCompletion(id: TaskID, completion: CompletionState) async throws -> Task
    func moveTask(id: TaskID, to orderToken: OrderToken) async throws -> Task
    func deleteTask(id: TaskID) async throws
    func restoreTask(id: TaskID) async throws -> Task
    func taskSummary(in noteID: NoteID) async throws -> NoteTaskSummary
}

public typealias TildoneRepositoryProtocol = NoteRepository & TaskRepository
