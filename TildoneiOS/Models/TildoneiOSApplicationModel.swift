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
    @Published private(set) var transportState: SyncTransportState = .active
    @Published private(set) var isResolvingWorkspace = true
    @Published private(set) var hasWorkspace = false
    @Published private(set) var contentRevision: UInt64 = 0

    private let repositoryFactory: RepositoryFactory
    private let accountResolver: () async -> CloudAccountSnapshot
    private let synchronizationEnabled: Bool
    private let transportStateStore: SyncTransportStateStore
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
        synchronizationEnabled: Bool = TildoneiOSSyncBootstrapper.featureEnabled,
        transportStateStore: SyncTransportStateStore = SyncTransportStateStore()
    ) {
        self.repositoryFactory = repositoryFactory
        self.accountResolver = accountResolver
        self.synchronizationEnabled = synchronizationEnabled
        self.transportStateStore = transportStateStore
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
        guard transportState == .active, let coordinator else { return }
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
            try await repository.migrateMissingNoteColors(
                colorsByNoteID: [:],
                authority: .platformDefault
            )
            self.repository = repository
            activeWorkspace = workspaceID
            hasWorkspace = true
            transportState = transportStateStore.state(for: workspaceID)
            if !synchronizationEnabled {
                syncStatus = .disabled
            } else if transportState == .paused {
                syncStatus = SyncStatus(
                    availability: .available,
                    activity: .paused,
                    pendingMutationCount: try await repository.pendingMutations().count
                )
            } else {
                syncStatus = SyncStatus(availability: .available, activity: .idle)
            }
            try await reloadNotes()
            if SyncTransportActivationPolicy.shouldActivate(
                enabledByDefault: synchronizationEnabled,
                persistedState: transportState
            ) {
                try await startCoordinator(for: repository, workspaceID: workspaceID)
            }
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
            taskSummaries[note.id] = NoteTaskSummary(
                noteID: note.id,
                tasks: TaskHierarchy.leafTasks(in: tasks)
            )
            let oldestTasksFirst = tasks.sorted {
                $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
            }
            let taskTexts = oldestTasksFirst.map(\.text)
            taskPreviews[note.id] = tasks.map(NoteTaskPreview.init)
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

    func setColor(noteID: NoteID, color: NoteColor) async throws {
        _ = try await withRepository { repository in
            try await repository.setNoteColor(id: noteID, color: color)
        }
        try await didMutate()
    }

    func delete(noteID: NoteID) async throws {
        _ = try await withRepository { repository in try await repository.deleteNote(id: noteID) }
        try await didMutate()
    }

    @discardableResult
    func addTask(
        noteID: NoteID,
        text: String,
        after tasks: [Task],
        indentLevel: Int? = nil
    ) async throws -> Task? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let initialUpperBound = try initialOrderUpperBound()
        let lastToken = tasks.last?.orderToken ?? OrderToken.before(initialUpperBound)
        let order = OrderToken.after(lastToken)
        let resolvedIndentLevel = max(0, indentLevel ?? tasks.last?.indentLevel ?? 0)
        let task = try await withRepository { repository in
            try await repository.addTask(
                id: TaskID(),
                to: noteID,
                createdAt: Date(),
                text: text,
                orderToken: order,
                indentLevel: resolvedIndentLevel
            )
        }
        try await didMutate()
        return task
    }

    @discardableResult
    func addTask(
        noteID: NoteID,
        text: String,
        before targetTaskID: TaskID
    ) async throws -> Task? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let task: Task? = try await withRepository { repository in
            let orderedTasks = try await repository.orderedTasks(in: noteID)
            guard let targetIndex = orderedTasks.firstIndex(where: { $0.id == targetTaskID }) else {
                return nil
            }
            let target = orderedTasks[targetIndex]
            let lowerBound = targetIndex > 0 ? orderedTasks[targetIndex - 1].orderToken : nil
            let order = try OrderToken.between(lowerBound, target.orderToken)
            return try await repository.addTask(
                id: TaskID(),
                to: noteID,
                createdAt: Date(),
                text: text,
                orderToken: order,
                indentLevel: target.indentLevel
            )
        }
        guard let task else { return nil }
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
        try await withRepository { repository in
            let task = try await repository.task(id: taskID, includingDeleted: false)
            let orderedTasks = try await repository.orderedTasks(in: task.noteID)
            guard let index = orderedTasks.firstIndex(where: { $0.id == taskID }) else {
                return try await repository.deleteTask(id: taskID)
            }
            for descendant in orderedTasks[TaskHierarchy.subtreeRange(startingAt: index, in: orderedTasks)] {
                try await repository.deleteTask(id: descendant.id)
            }
        }
        try await didMutate()
    }

    @discardableResult
    func changeIndentation(
        taskID: TaskID,
        in orderedTasks: [Task],
        outdent: Bool
    ) async throws -> Bool {
        guard let index = orderedTasks.firstIndex(where: { $0.id == taskID }) else { return false }
        let task = orderedTasks[index]
        let targetLevel: Int
        if outdent {
            guard task.indentLevel > 0 else { return false }
            targetLevel = task.indentLevel - 1
        } else {
            guard index > 0 else { return false }
            targetLevel = orderedTasks[index - 1].indentLevel + 1
        }
        let delta = targetLevel - task.indentLevel
        guard delta != 0 else { return false }

        let subtree = TaskHierarchy.subtreeRange(startingAt: index, in: orderedTasks)
        for descendant in orderedTasks[subtree] {
            _ = try await withRepository { repository in
                try await repository.setTaskIndentLevel(
                    id: descendant.id,
                    indentLevel: max(0, descendant.indentLevel + delta)
                )
            }
        }
        try await didMutate()
        return true
    }

    @discardableResult
    func move(
        taskID: TaskID,
        in orderedTasks: [Task],
        from source: IndexSet,
        to destination: Int
    ) async throws -> Bool {
        guard let originalIndex = orderedTasks.firstIndex(where: { $0.id == taskID }),
              source.contains(originalIndex),
              (0...orderedTasks.count).contains(destination) else {
            return false
        }
        let subtree = TaskHierarchy.subtreeRange(startingAt: originalIndex, in: orderedTasks)
        guard !subtree.isEmpty,
              destination < subtree.lowerBound || destination > subtree.upperBound else {
            return false
        }

        let originalParentID = TaskHierarchy.parentID(at: originalIndex, in: orderedTasks)
        var reordered = orderedTasks
        let movedTasks = Array(reordered[subtree])
        reordered.removeSubrange(subtree)
        let adjustedDestination = destination > subtree.upperBound
            ? destination - subtree.count
            : destination
        let insertionIndex = min(adjustedDestination, reordered.count)
        reordered.insert(contentsOf: movedTasks, at: insertionIndex)
        guard reordered.map(\.id) != orderedTasks.map(\.id),
              TaskHierarchy.isValidPreorder(reordered),
              let newIndex = reordered.firstIndex(where: { $0.id == taskID }),
              TaskHierarchy.parentID(at: newIndex, in: reordered) == originalParentID else {
            return false
        }

        var lower = insertionIndex > 0 ? reordered[insertionIndex - 1].orderToken : nil
        let upperIndex = insertionIndex + movedTasks.count
        let upper = upperIndex < reordered.count ? reordered[upperIndex].orderToken : nil
        for task in movedTasks {
            let token = try OrderToken.between(lower, upper)
            let moved = try await withRepository { repository in
                try await repository.moveTask(id: task.id, to: token)
            }
            lower = moved.orderToken
        }
        try await didMutate()
        return true
    }

    func openForTesting(workspaceID: UUID) async throws {
        await closeWorkspace(status: .disabled)
        repository = try repositoryFactory(.account(workspaceID))
        try await repository?.migrateMissingNoteColors(
            colorsByNoteID: [:],
            authority: .platformDefault
        )
        activeWorkspace = workspaceID
        transportState = transportStateStore.state(for: workspaceID)
        hasWorkspace = true
        isResolvingWorkspace = false
        try await reloadNotes()
    }

    var canControlTransport: Bool {
        synchronizationEnabled && activeWorkspace != nil
    }

    func pauseTransport() {
        guard canControlTransport,
              transportState == .active,
              let workspaceID = activeWorkspace,
              let repository else { return }
        transportStateStore.set(.paused, for: workspaceID)
        transportState = .paused
        statusTask?.cancel()
        statusTask = nil
        let coordinator = coordinator
        self.coordinator = nil
        let previousStatus = syncStatus
        let retainsAttention = Self.requiresAttention(previousStatus)
        if !retainsAttention {
            syncStatus = SyncStatus(
                availability: .available,
                activity: .paused,
                pendingMutationCount: previousStatus.pendingMutationCount,
                lastSuccessfulSyncAt: previousStatus.lastSuccessfulSyncAt,
                activeDeviceSummary: previousStatus.activeDeviceSummary,
                issue: previousStatus.issue
            )
        }
        Swift.Task { [weak self] in
            await coordinator?.pause()
            guard let self, self.activeWorkspace == workspaceID, self.transportState == .paused else {
                return
            }
            let pending = (try? await repository.pendingMutations().count) ?? syncStatus.pendingMutationCount
            syncStatus = SyncStatus(
                availability: retainsAttention ? previousStatus.availability : .available,
                activity: retainsAttention ? previousStatus.activity : .paused,
                pendingMutationCount: pending,
                lastSuccessfulSyncAt: previousStatus.lastSuccessfulSyncAt,
                activeDeviceSummary: previousStatus.activeDeviceSummary,
                issue: previousStatus.issue
            )
        }
    }

    func resumeTransport() {
        guard canControlTransport, transportState == .paused else { return }
        Swift.Task { [weak self] in await self?.resumeTransportNow() }
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

    private func resumeTransportNow() async {
        guard synchronizationEnabled,
              transportState == .paused,
              let workspaceID = activeWorkspace,
              let repository else { return }
        let account = await accountResolver()
        guard account.state == .available, account.workspaceID == workspaceID else {
            await closeWorkspace(status: SyncStatus(
                availability: .accountChanged,
                activity: .attentionNeeded,
                issue: .accountChanged
            ))
            return
        }
        transportStateStore.set(.active, for: workspaceID)
        transportState = .active
        do {
            try await startCoordinator(for: repository, workspaceID: workspaceID)
        } catch {
            syncStatus = SyncStatus(
                availability: .available,
                activity: .attentionNeeded,
                pendingMutationCount: (try? await repository.pendingMutations().count) ?? 0,
                lastSuccessfulSyncAt: syncStatus.lastSuccessfulSyncAt,
                issue: .unknown
            )
        }
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
        transportState = .active
        notes = []
        taskSummaries = [:]
        taskListTexts = [:]
        taskPreviews = [:]
        hasWorkspace = false
        syncStatus = status
    }

    private func reloadRemoteContent(for workspaceID: UUID) async {
        guard activeWorkspace == workspaceID, let repository else { return }
        do {
            try await repository.migrateMissingNoteColors(
                colorsByNoteID: [:],
                authority: .platformDefault
            )
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

    private static func requiresAttention(_ status: SyncStatus) -> Bool {
        status.activity == .attentionNeeded || [
            .adoptionRequired,
            .accountChanged,
            .zoneResetRequired,
            .incompatibleRemoteData
        ].contains(status.availability)
    }

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
    let indentLevel: Int

    init(_ task: Task) {
        id = task.id
        text = task.text
        isCompleted = task.isCompleted
        indentLevel = task.indentLevel
    }
}
