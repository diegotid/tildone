//
//  TildoneiOSApplicationModel.swift
//  Tildone
//
//  Created by Diego Rivera on 8/1/26.
//
import Foundation
import SwiftUI
import TildoneDomain
import TildonePersistence
import TildoneSync

@MainActor
final class TildoneiOSApplicationModel: ObservableObject {
    typealias RepositoryFactory = (WorkspaceIdentity) throws -> TildoneRepository

    @Published private(set) var notes: [Note] = []
    @Published private(set) var taskSummaries: [NoteID: NoteTaskSummary] = [:]
    @Published private(set) var taskListTexts: [NoteID: String] = [:]
    @Published private(set) var taskPreviews: [NoteID: [NoteTaskPreview]] = [:]
    @Published private(set) var syncStatus: SyncStatus = .disabled
    @Published private(set) var isResolvingWorkspace = true
    @Published private(set) var hasWorkspace = false
    @Published private(set) var contentRevision: UInt64 = 0

    private let repositoryFactory: RepositoryFactory
    private let accountResolver: () async -> CloudAccountSnapshot
    private let synchronizationEnabled: Bool
    private var repository: TildoneRepository?
    private var coordinator: TildoneSyncCoordinator?
    private var statusTask: Swift.Task<Void, Never>?
    private var workspaceResolutionTask: Swift.Task<Void, Never>?
    private var activeWorkspace: UUID?

    init(
        repositoryFactory: @escaping RepositoryFactory = TildoneiOSApplicationModel.makeRepository,
        accountResolver: @escaping () async -> CloudAccountSnapshot = {
            await CloudAccountResolver().resolve()
        },
        synchronizationEnabled: Bool = TildoneiOSSyncBootstrapper.featureEnabled
    ) {
        self.repositoryFactory = repositoryFactory
        self.accountResolver = accountResolver
        self.synchronizationEnabled = synchronizationEnabled
    }

    deinit { statusTask?.cancel() }

    func start() {
        guard workspaceResolutionTask == nil else { return }
        workspaceResolutionTask = Swift.Task { [weak self] in
            guard let self else { return }
            await resolveAndOpenCurrentWorkspace()
            workspaceResolutionTask = nil
        }
    }

    func applicationBecameActive() {
        start()
    }

    func syncNow() {
        guard let coordinator else { return }
        Swift.Task { [weak self, weak coordinator] in
            guard let self, let coordinator else { return }
            await coordinator.start()
            try? await reloadNotes()
        }
    }

    func resolveAndOpenCurrentWorkspace() async {
        isResolvingWorkspace = true
        let account = await accountResolver()
        guard account.state == .available, let workspaceID = account.workspaceID else {
            await closeWorkspace(status: Self.status(for: account.state))
            isResolvingWorkspace = false
            return
        }

        if activeWorkspace == workspaceID, repository != nil {
            isResolvingWorkspace = false
            syncNow()
            return
        }

        await closeWorkspace(status: .disabled)
        do {
            let repository = try repositoryFactory(.account(workspaceID))
            self.repository = repository
            activeWorkspace = workspaceID
            hasWorkspace = true
            syncStatus = synchronizationEnabled
                ? SyncStatus(availability: .available, activity: .idle)
                : .disabled
            try await reloadNotes()
            if synchronizationEnabled { try await startCoordinator(for: repository, workspaceID: workspaceID) }
        } catch {
            await closeWorkspace(status: SyncStatus(
                availability: .temporarilyUnavailable,
                activity: .attentionNeeded,
                issue: .unknown
            ))
        }
        isResolvingWorkspace = false
    }

    func reloadNotes() async throws {
        guard let repository else { return }
        let notes = try await repository.visibleNotes()
        var taskSummaries: [NoteID: NoteTaskSummary] = [:]
        var taskListTexts: [NoteID: String] = [:]
        var taskPreviews: [NoteID: [NoteTaskPreview]] = [:]
        taskSummaries.reserveCapacity(notes.count)

        for note in notes {
            let tasks = try await repository.orderedTasks(in: note.id)
            taskSummaries[note.id] = NoteTaskSummary(noteID: note.id, tasks: tasks)
            let oldestTasksFirst = tasks.sorted {
                $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
            }
            let taskTexts = oldestTasksFirst.map(\.text)
            taskPreviews[note.id] = oldestTasksFirst.map(NoteTaskPreview.init)
            let taskListText = taskTexts.joined(separator: ", ")
            if !taskListText.isEmpty {
                taskListTexts[note.id] = taskListText
            }
        }

        self.notes = notes
        self.taskSummaries = taskSummaries
        self.taskListTexts = taskListTexts
        self.taskPreviews = taskPreviews
        contentRevision &+= 1
    }

    func tasks(in noteID: NoteID) async throws -> [Task] {
        guard let repository else { return [] }
        return try await repository.orderedTasks(in: noteID)
    }

    @discardableResult
    func createNote(title: String? = nil, id: NoteID = NoteID()) async throws -> Note {
        let note = try await withRepository { repository in
            try await repository.createNote(id: id, createdAt: Date(), title: title)
        }
        try await didMutate()
        return note
    }

    func rename(noteID: NoteID, title: String?) async throws {
        _ = try await withRepository { repository in
            try await repository.renameNote(id: noteID, to: Self.normalizedTitle(title), editedAt: Date())
        }
        try await didMutate()
    }

    func delete(noteID: NoteID) async throws {
        _ = try await withRepository { repository in try await repository.deleteNote(id: noteID) }
        try await didMutate()
    }

    @discardableResult
    func addTask(noteID: NoteID, text: String, after tasks: [Task]) async throws -> Task? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let initialUpperBound = try initialOrderUpperBound()
        let lastToken = tasks.last?.orderToken ?? OrderToken.before(initialUpperBound)
        let order = OrderToken.after(lastToken)
        let task = try await withRepository { repository in
            try await repository.addTask(
                id: TaskID(), to: noteID, createdAt: Date(), text: text, orderToken: order
            )
        }
        try await didMutate()
        return task
    }

    func edit(taskID: TaskID, text: String) async throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        _ = try await withRepository { repository in try await repository.editTask(id: taskID, text: text) }
        try await didMutate()
    }

    func setCompletion(taskID: TaskID, completed: Bool) async throws {
        _ = try await withRepository { repository in
            try await repository.setTaskCompletion(
                id: taskID, completion: completed ? .completed(at: Date()) : .incomplete
            )
        }
        try await didMutate()
    }

    func delete(taskID: TaskID) async throws {
        _ = try await withRepository { repository in try await repository.deleteTask(id: taskID) }
        try await didMutate()
    }

    func move(taskID: TaskID, in orderedTasks: [Task], from source: IndexSet, to destination: Int) async throws {
        guard let originalIndex = source.first else { return }
        var reordered = orderedTasks
        let moved = reordered.remove(at: originalIndex)
        let adjustedDestination = destination > originalIndex ? destination - 1 : destination
        reordered.insert(moved, at: min(adjustedDestination, reordered.count))
        guard let newIndex = reordered.firstIndex(where: { $0.id == taskID }) else { return }
        let lower = newIndex > 0 ? reordered[newIndex - 1].orderToken : nil
        let upper = newIndex + 1 < reordered.count ? reordered[newIndex + 1].orderToken : nil
        let token = try OrderToken.between(lower, upper)
        _ = try await withRepository { repository in try await repository.moveTask(id: taskID, to: token) }
        try await didMutate()
    }

    func openForTesting(workspaceID: UUID) async throws {
        await closeWorkspace(status: .disabled)
        repository = try repositoryFactory(.account(workspaceID))
        activeWorkspace = workspaceID
        hasWorkspace = true
        isResolvingWorkspace = false
        try await reloadNotes()
    }

    func present(status: SyncStatus) {
        syncStatus = status
        if status.availability == .accountChanged {
            hasWorkspace = false
            notes = []
            taskSummaries = [:]
            taskListTexts = [:]
            taskPreviews = [:]
        }
    }

    private func didMutate() async throws {
        try await reloadNotes()
        await coordinator?.notifyLocalChanges()
    }

    private func withRepository<T>(_ operation: (TildoneRepository) async throws -> T) async throws -> T {
        guard let repository else { throw TildoneiOSPresentationError.noWorkspace }
        return try await operation(repository)
    }

    private func startCoordinator(for repository: TildoneRepository, workspaceID: UUID) async throws {
        let coordinator = try await TildoneSyncCoordinator(
            repository: repository,
            clientPlatform: .iPhone,
            onAccountChange: { [weak self] change in
                guard change.requiresWorkspaceInvalidation else { return }
                Swift.Task { @MainActor in
                    guard self?.activeWorkspace == workspaceID else { return }
                    await self?.closeWorkspace(status: SyncStatus(
                        availability: .accountChanged, activity: .attentionNeeded, issue: .accountChanged
                    ))
                }
            },
            onRemoteChange: { [weak self] in
                await self?.reloadRemoteContent(for: workspaceID)
            }
        )
        self.coordinator = coordinator
        statusTask?.cancel()
        statusTask = Swift.Task { [weak self, weak coordinator] in
            guard let coordinator else { return }
            for await status in await coordinator.statusModel.updates() {
                guard !Swift.Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard self?.activeWorkspace == workspaceID else { return }
                    self?.syncStatus = status
                }
            }
        }
        await coordinator.start()
    }

    private func closeWorkspace(status: SyncStatus) async {
        statusTask?.cancel()
        statusTask = nil
        if let coordinator { await coordinator.stop() }
        coordinator = nil
        repository = nil
        activeWorkspace = nil
        notes = []
        taskSummaries = [:]
        taskListTexts = [:]
        taskPreviews = [:]
        hasWorkspace = false
        syncStatus = status
    }

    private func reloadRemoteContent(for workspaceID: UUID) async {
        guard activeWorkspace == workspaceID else { return }
        do {
            try await reloadNotes()
        } catch {
            syncStatus = SyncStatus(
                availability: .available,
                activity: .attentionNeeded,
                pendingMutationCount: syncStatus.pendingMutationCount,
                lastSuccessfulSyncAt: syncStatus.lastSuccessfulSyncAt,
                issue: .unknown
            )
        }
    }

    private nonisolated static func makeRepository(workspace: WorkspaceIdentity) throws -> TildoneRepository {
        guard let baseDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { throw PersistenceError.invalidStoreLocation }
        return try TildoneRepository(descriptor: .persistent(baseDirectory: baseDirectory, workspace: workspace))
    }

    private static func normalizedTitle(_ title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return title
    }

    private func initialOrderUpperBound() throws -> OrderToken { try OrderToken(rawValue: "z") }

    private static func status(for account: CloudAccountState) -> SyncStatus {
        switch account {
        case .available: SyncStatus(availability: .available, activity: .idle)
        case .noAccount: SyncStatus(availability: .noAccount, activity: .idle)
        case .restricted: SyncStatus(availability: .restricted, activity: .attentionNeeded, issue: .permission)
        case .temporarilyUnavailable, .couldNotDetermine:
            SyncStatus(availability: .temporarilyUnavailable, activity: .offline, issue: .service)
        }
    }
}

struct NoteTaskPreview: Identifiable, Hashable {
    let id: TaskID
    let text: String
    let isCompleted: Bool

    init(_ task: Task) {
        id = task.id
        text = task.text
        isCompleted = task.isCompleted
    }
}
