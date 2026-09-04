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
    typealias RepositoryFactory = (WorkspaceIdentity) async throws -> TildoneRepository

    let overviewPresentation = TildoneiOSOverviewPresentation()
    let syncPresentation = TildoneiOSSyncPresentation()
    let undoPresentation = TildoneiOSUndoPresentation()
    @Published private(set) var isResolvingWorkspace = true
    @Published private(set) var hasWorkspace = false
    @Published private(set) var isCheckingCloudForNotes = true
    @Published private(set) var isEmptyStateConfirmed = false
    @Published private(set) var isUsingLocalWorkspace = false
    @Published private(set) var shouldOfferCloudAdoption = false
    @Published private(set) var isWorkspaceTransitionInProgress = false
    @Published private(set) var workspaceTransitionFailed = false
    private(set) var contentRevision: UInt64 = 0

    var notes: [Note] { overviewPresentation.snapshot.notes }
    var taskSummaries: [NoteID: NoteTaskSummary] { overviewPresentation.snapshot.taskSummaries }
    var taskListTexts: [NoteID: String] { overviewPresentation.snapshot.taskListTexts }
    var taskPreviews: [NoteID: [NoteTaskPreview]] { overviewPresentation.snapshot.taskPreviews }
    private(set) var syncStatus: SyncStatus {
        get { syncPresentation.status }
        set {
            syncPresentation.update(status: newValue)
            if Self.requiresUndoInvalidation(newValue) { discardUndo() }
        }
    }
    private(set) var transportState: SyncTransportState {
        get { syncPresentation.transportState }
        set { syncPresentation.update(transportState: newValue) }
    }

    private let repositoryFactory: RepositoryFactory
    private let accountResolver: () async -> CloudAccountSnapshot
    private let synchronizationEnabled: Bool
    private let transportStateStore: SyncTransportStateStore
    private let defaults: UserDefaults
    private var repository: TildoneRepository?
    private var localRepository: TildoneRepository?
    private var accountRepository: TildoneRepository?
    private var undoController: ConsequentialActionUndoController?
    private var coordinator: TildoneSyncCoordinator?
    private var statusTask: Swift.Task<Void, Never>?
    private var workspaceResolutionTask: Swift.Task<Void, Never>?
    private var activeWorkspace: UUID?
    private var accountWorkspaceID: UUID?
    private var notePresentations: [NoteID: TildoneiOSNotePresentation] = [:]
    private var nextPresentationRevision: UInt64 = 0
    private var latestPresentationMutationRevisions: [NoteID: UInt64] = [:]
    private var pendingPresentationMutationRevisions: [NoteID: UInt64] = [:]
    private var latestFullReloadRevision: UInt64 = 0
    private var latestNoteReloadRevisions: [NoteID: UInt64] = [:]
    private var remoteReloadTask: Swift.Task<Void, Never>?
    private var remoteReloadRequested = false

    init(
        repositoryFactory: @escaping RepositoryFactory = TildoneiOSApplicationModel.makeRepository,
        accountResolver: @escaping () async -> CloudAccountSnapshot = {
            await CloudAccountResolver().resolve()
        },
        synchronizationEnabled: Bool = TildoneiOSSyncBootstrapper.featureEnabled,
        transportStateStore: SyncTransportStateStore = SyncTransportStateStore(),
        defaults: UserDefaults = .standard
    ) {
        self.repositoryFactory = repositoryFactory
        self.accountResolver = accountResolver
        self.synchronizationEnabled = synchronizationEnabled
        self.transportStateStore = transportStateStore
        self.defaults = defaults
    }

    deinit {
        statusTask?.cancel()
        remoteReloadTask?.cancel()
    }

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
            let checkpointStatus = await coordinator.statusModel.snapshot()
            if checkpointStatus.lastSuccessfulSyncAt != nil {
                isEmptyStateConfirmed = true
            }
        }
    }

    func resolveAndOpenCurrentWorkspace() async {
        let isInitialOpen = repository == nil
        isResolvingWorkspace = true
        if isInitialOpen {
            isCheckingCloudForNotes = true
            isEmptyStateConfirmed = false
        }
        let account = await accountResolver()
        guard account.state == .available, let workspaceID = account.workspaceID else {
            if [.temporarilyUnavailable, .couldNotDetermine].contains(account.state),
               repository != nil {
                syncStatus = Self.status(for: account.state)
                isResolvingWorkspace = false
                isCheckingCloudForNotes = false
                return
            }
            if !isUsingLocalWorkspace || repository == nil {
                await closeWorkspace(status: Self.status(for: account.state))
                do {
                    try await openLocalWorkspace(status: Self.status(for: account.state))
                } catch {
                    await closeWorkspace(status: SyncStatus(
                        availability: .temporarilyUnavailable,
                        activity: .attentionNeeded,
                        issue: .unknown
                    ))
                }
            } else {
                syncStatus = Self.status(for: account.state)
            }
            isResolvingWorkspace = false
            isCheckingCloudForNotes = false
            return
        }

        if activeWorkspace == workspaceID, repository != nil {
            isResolvingWorkspace = false
            isCheckingCloudForNotes = false
            syncNow()
            return
        }

        if isUsingLocalWorkspace, accountWorkspaceID == workspaceID {
            isResolvingWorkspace = false
            isCheckingCloudForNotes = false
            return
        }

        if isUsingLocalWorkspace { isCheckingCloudForNotes = true }
        await closeWorkspace(status: .disabled)
        do {
            let localRepository = try await repositoryFactory(.localOnly)
            try await localRepository.migrateMissingNoteColors(
                colorsByNoteID: [:],
                authority: .platformDefault
            )
            let accountRepository = try await repositoryFactory(.account(workspaceID))
            try await accountRepository.migrateMissingNoteColors(
                colorsByNoteID: [:],
                authority: .platformDefault
            )
            self.localRepository = localRepository
            self.accountRepository = accountRepository
            accountWorkspaceID = workspaceID

            let localHasContent = try await localRepository.hasSyncContent()
            switch localWorkspaceChoice(for: workspaceID) {
            case .useICloud:
                try await activateAccountWorkspace(accountRepository, workspaceID: workspaceID)
            case _ where !localHasContent:
                try await activateAccountWorkspace(accountRepository, workspaceID: workspaceID)
            case .stayLocal:
                try await activateLocalWorkspace(localRepository, status: .disabled)
            case .none:
                try await activateLocalWorkspace(
                    localRepository,
                    status: SyncStatus(availability: .adoptionRequired, activity: .attentionNeeded)
                )
                shouldOfferCloudAdoption = true
            }
        } catch {
            await closeWorkspace(status: SyncStatus(
                availability: .temporarilyUnavailable,
                activity: .attentionNeeded,
                issue: .unknown
            ))
        }
        isResolvingWorkspace = false
        isCheckingCloudForNotes = false
    }

    func keepNotesOnThisIPhone() {
        guard let workspaceID = accountWorkspaceID else { return }
        setLocalWorkspaceChoice(.stayLocal, for: workspaceID)
        shouldOfferCloudAdoption = false
        workspaceTransitionFailed = false
        syncStatus = .disabled
    }

    func offerCloudAdoption() {
        guard isUsingLocalWorkspace, accountWorkspaceID != nil else { return }
        shouldOfferCloudAdoption = true
        workspaceTransitionFailed = false
    }

    func dismissCloudAdoptionOffer() {
        shouldOfferCloudAdoption = false
    }

    func dismissWorkspaceTransitionError() {
        workspaceTransitionFailed = false
    }

    var canOfferCloudAdoption: Bool {
        isUsingLocalWorkspace && accountWorkspaceID != nil
    }

    func useICloudAndCombineNotes() {
        guard !isWorkspaceTransitionInProgress,
              let localRepository,
              let accountRepository,
              let workspaceID = accountWorkspaceID else { return }
        isWorkspaceTransitionInProgress = true
        workspaceTransitionFailed = false
        Swift.Task { [weak self] in
            guard let self else { return }
            do {
                let notes = try await localRepository.allSyncNotes()
                let tasks = try await localRepository.allSyncTasks()
                try await accountRepository.adoptSyncContent(notes: notes, tasks: tasks, at: Date())
                try await localRepository.markCloudSeedingBegun(at: Date())
                try await activateAccountWorkspace(accountRepository, workspaceID: workspaceID)
                setLocalWorkspaceChoice(.useICloud, for: workspaceID)
                shouldOfferCloudAdoption = false
            } catch {
                workspaceTransitionFailed = true
            }
            isWorkspaceTransitionInProgress = false
        }
    }

    func reloadNotes() async throws {
        guard let repository else { return }
        let reloadRevision = nextRevision()
        latestFullReloadRevision = reloadRevision
        let visibleSnapshots = try await repository.visibleNoteSnapshots()
        let snapshots = visibleSnapshots.map {
            TildoneiOSNoteSnapshot(note: $0.note, tasks: $0.tasks)
        }
        publishFullReload(snapshots, revision: reloadRevision)
    }

    func presentation(for noteID: NoteID) -> TildoneiOSNotePresentation {
        if let presentation = notePresentations[noteID] { return presentation }
        let presentation = TildoneiOSNotePresentation()
        notePresentations[noteID] = presentation
        return presentation
    }

    func tasks(in noteID: NoteID) async throws -> [Task] {
        if let snapshot = notePresentations[noteID]?.snapshot, snapshot.note != nil {
            return snapshot.tasks
        }
        guard let repository else { return [] }
        return try await repository.orderedTasks(in: noteID)
    }

    /// Used by the create button so navigation can start in the same run-loop
    /// turn as the tap while persistence continues asynchronously.
    @discardableResult
    func createNoteAndPresent(title: String? = nil, id: NoteID = NoteID()) -> NoteID {
        let staged = stageNoteCreation(title: title, id: id)
        Swift.Task { [weak self] in
            try? await self?.commitNoteCreation(staged.note, revision: staged.revision)
        }
        return id
    }

    @discardableResult
    func createNote(title: String? = nil, id: NoteID = NoteID()) async throws -> Note {
        let staged = stageNoteCreation(title: title, id: id)
        return try await commitNoteCreation(staged.note, revision: staged.revision)
    }

    func rename(noteID: NoteID, title: String?) async throws {
        let title = Self.normalizedTitle(title)
        guard let snapshot = notePresentations[noteID]?.snapshot,
              let note = snapshot.note else { throw TildoneiOSPresentationError.noWorkspace }
        let revision = stage(TildoneiOSNoteSnapshot(
            note: Self.presentationNote(note, title: title, meaningfulEditAt: Date()),
            tasks: snapshot.tasks
        ))
        do {
            let persisted = try await withRepository { repository in
                try await repository.renameNote(id: noteID, to: title, editedAt: Date())
            }
            publishPersistedNote(persisted, ifCurrentRevision: revision)
            scheduleSyncNotification()
        } catch {
            await rollback(noteID, revision: revision)
            throw error
        }
    }

    func setColor(noteID: NoteID, color: NoteColor) async throws {
        guard let snapshot = notePresentations[noteID]?.snapshot,
              let note = snapshot.note else { throw TildoneiOSPresentationError.noWorkspace }
        let revision = stage(TildoneiOSNoteSnapshot(
            note: Self.presentationNote(note, color: color),
            tasks: snapshot.tasks
        ))
        do {
            let persisted = try await withRepository { repository in
                try await repository.setNoteColor(id: noteID, color: color)
            }
            publishPersistedNote(persisted, ifCurrentRevision: revision)
            undoController?.recordNoteColor(
                noteID: noteID,
                previousColor: note.color,
                newColor: color
            )
            publishUndoAvailability()
            scheduleSyncNotification()
        } catch {
            await rollback(noteID, revision: revision)
            throw error
        }
    }

    func delete(noteID: NoteID) async throws {
        guard let snapshot = notePresentations[noteID]?.snapshot,
              let note = snapshot.note else { return }
        let revision = nextRevision()
        latestPresentationMutationRevisions[noteID] = revision
        pendingPresentationMutationRevisions[noteID] = revision
        removePresentation(for: noteID)
        do {
            try await withRepository { repository in try await repository.deleteNote(id: noteID) }
            undoController?.recordNoteDeletion(note: note, tasks: snapshot.tasks)
            publishUndoAvailability()
            finishPendingMutation(noteID, revision: revision)
            scheduleSyncNotification()
        } catch {
            await rollback(noteID, revision: revision)
            throw error
        }
    }

    @discardableResult
    func addTask(
        noteID: NoteID,
        text: String,
        after _: [Task],
        indentLevel: Int? = nil
    ) async throws -> Task? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let initialUpperBound = try initialOrderUpperBound()
        let snapshot = try requireSnapshot(noteID)
        let presentedTasks = snapshot.tasks
        let lastToken = presentedTasks.last?.orderToken ?? OrderToken.before(initialUpperBound)
        let order = OrderToken.after(lastToken)
        let resolvedIndentLevel = max(0, indentLevel ?? presentedTasks.last?.indentLevel ?? 0)
        let stagedTask = Self.presentationTask(
            id: TaskID(), noteID: noteID, createdAt: Date(), text: text,
            orderToken: order, indentLevel: resolvedIndentLevel, basedOn: snapshot.note!
        )
        let revision = stageTaskInsertion(stagedTask, in: snapshot)
        do {
            let task = try await withRepository { repository in
                try await repository.addTask(
                    id: stagedTask.id,
                    to: noteID,
                    createdAt: stagedTask.createdAt,
                    text: text,
                    orderToken: order,
                    indentLevel: resolvedIndentLevel
                )
            }
            await reconcileSuccessfulMutation(noteID, revision: revision)
            scheduleSyncNotification()
            return task
        } catch {
            await rollback(noteID, revision: revision)
            throw error
        }
    }

    @discardableResult
    func addTask(
        noteID: NoteID,
        text: String,
        before targetTaskID: TaskID
    ) async throws -> Task? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let snapshot = try requireSnapshot(noteID)
        guard let targetIndex = snapshot.tasks.firstIndex(where: { $0.id == targetTaskID }) else {
            return nil
        }
        let target = snapshot.tasks[targetIndex]
        let lowerBound = targetIndex > 0 ? snapshot.tasks[targetIndex - 1].orderToken : nil
        let order = try OrderToken.between(lowerBound, target.orderToken)
        let stagedTask = Self.presentationTask(
            id: TaskID(), noteID: noteID, createdAt: Date(), text: text,
            orderToken: order, indentLevel: target.indentLevel, basedOn: snapshot.note!
        )
        let revision = stageTaskInsertion(stagedTask, in: snapshot)
        do {
            let task = try await withRepository { repository in
                try await repository.addTask(
                    id: stagedTask.id,
                    to: noteID,
                    createdAt: stagedTask.createdAt,
                    text: text,
                    orderToken: order,
                    indentLevel: target.indentLevel
                )
            }
            await reconcileSuccessfulMutation(noteID, revision: revision)
            scheduleSyncNotification()
            return task
        } catch {
            await rollback(noteID, revision: revision)
            throw error
        }
    }

    func edit(taskID: TaskID, text: String) async throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let (snapshot, task) = try requireSnapshot(containing: taskID)
        let revision = stageTaskUpdates(
            [TaskStructureUpdate(id: taskID)],
            in: snapshot,
            textOverrides: [taskID: text]
        )
        do {
            _ = try await withRepository { repository in
                try await repository.editTask(id: taskID, text: text)
            }
            await reconcileSuccessfulMutation(task.noteID, revision: revision)
            scheduleSyncNotification()
        } catch {
            await rollback(task.noteID, revision: revision)
            throw error
        }
    }

    func setCompletion(taskID: TaskID, completed: Bool) async throws {
        let (snapshot, task) = try requireSnapshot(containing: taskID)
        let completion: CompletionState = completed ? .completed(at: Date()) : .incomplete
        let updates = [TaskStructureUpdate(id: taskID, completion: completion)]
        let revision = stageTaskUpdates(updates, in: snapshot)
        do {
            _ = try await withRepository { repository in
                try await repository.setTaskCompletion(id: taskID, completion: completion)
            }
            await reconcileSuccessfulMutation(task.noteID, revision: revision)
            let after = try await withRepository { repository in
                try await repository.orderedTasks(in: task.noteID)
            }
            undoController?.recordTaskCompletion(
                before: snapshot.tasks,
                after: after,
                taskID: taskID
            )
            publishUndoAvailability()
            scheduleSyncNotification()
        } catch {
            await rollback(task.noteID, revision: revision)
            throw error
        }
    }

    func delete(taskID: TaskID) async throws {
        let (snapshot, task) = try requireSnapshot(containing: taskID)
        guard let index = snapshot.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let subtree = TaskHierarchy.subtreeRange(startingAt: index, in: snapshot.tasks)
        let deletedIDs = Set(snapshot.tasks[subtree].map(\.id))
        let deletedTasks = Array(snapshot.tasks[subtree])
        let revision = stage(TildoneiOSNoteSnapshot(
            note: Self.presentationNote(snapshot.note!, meaningfulEditAt: Date()),
            tasks: snapshot.tasks.filter { !deletedIDs.contains($0.id) }
        ))
        do {
            let owner = try await withRepository { repository in
                try await repository.deleteTasks(deletedIDs, in: task.noteID)
            }
            undoController?.recordTaskDeletion(noteID: task.noteID, tasks: deletedTasks)
            publishUndoAvailability()
            publishPersistedNote(owner, ifCurrentRevision: revision)
            scheduleSyncNotification()
        } catch {
            await rollback(task.noteID, revision: revision)
            throw error
        }
    }

    @discardableResult
    func changeIndentation(
        taskID: TaskID,
        in orderedTasks: [Task],
        outdent: Bool
    ) async throws -> Bool {
        guard let index = orderedTasks.firstIndex(where: { $0.id == taskID }) else { return false }
        let task = orderedTasks[index]
        if outdent {
            guard task.indentLevel > 0 else { return false }
        } else {
            guard index > 0,
                  orderedTasks[index - 1].indentLevel >= task.indentLevel else {
                return false
            }
        }
        let delta = outdent ? -1 : 1
        let subtree = TaskHierarchy.subtreeRange(startingAt: index, in: orderedTasks)
        let updates = orderedTasks[subtree].map {
            TaskStructureUpdate(id: $0.id, indentLevel: $0.indentLevel + delta)
        }
        let snapshot = try requireSnapshot(task.noteID)
        let revision = stageTaskUpdates(updates, in: snapshot)
        do {
            _ = try await withRepository { repository in
                try await repository.applyTaskStructureUpdates(in: task.noteID, updates: updates)
            }
            await reconcileSuccessfulMutation(task.noteID, revision: revision)
            let after = try await withRepository { repository in
                try await repository.orderedTasks(in: task.noteID)
            }
            undoController?.recordTaskIndentation(
                before: orderedTasks,
                after: after,
                performedOutdent: outdent
            )
            publishUndoAvailability()
            scheduleSyncNotification()
            return true
        } catch {
            await rollback(task.noteID, revision: revision)
            throw error
        }
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
        let noteID = orderedTasks[originalIndex].noteID
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
        var updates: [TaskStructureUpdate] = []
        updates.reserveCapacity(movedTasks.count)
        for task in movedTasks {
            let token = try OrderToken.between(lower, upper)
            updates.append(TaskStructureUpdate(id: task.id, orderToken: token))
            lower = token
        }
        let snapshot = try requireSnapshot(noteID)
        let revision = stageTaskUpdates(updates, in: snapshot)
        do {
            _ = try await withRepository { repository in
                try await repository.applyTaskStructureUpdates(in: noteID, updates: updates)
            }
            await reconcileSuccessfulMutation(noteID, revision: revision)
            let after = try await withRepository { repository in
                try await repository.orderedTasks(in: noteID)
            }
            undoController?.recordTaskReorder(before: orderedTasks, after: after)
            publishUndoAvailability()
            scheduleSyncNotification()
            return true
        } catch {
            await rollback(noteID, revision: revision)
            throw error
        }
    }

    func openForTesting(workspaceID: UUID) async throws {
        await closeWorkspace(status: .disabled)
        let openedRepository = try await repositoryFactory(.account(workspaceID))
        repository = openedRepository
        undoController = ConsequentialActionUndoController(repository: openedRepository)
        try await openedRepository.migrateMissingNoteColors(
            colorsByNoteID: [:],
            authority: .platformDefault
        )
        activeWorkspace = workspaceID
        transportState = transportStateStore.state(for: workspaceID)
        hasWorkspace = true
        isResolvingWorkspace = false
        isCheckingCloudForNotes = false
        isEmptyStateConfirmed = true
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
            clearPresentationState()
        }
    }

    func undoLatestAction() async throws {
        guard let undoController else { throw ConsequentialActionUndoError.unavailable }
        _ = try await undoController.undo()
        undoPresentation.clear()
        try await reloadNotes()
        scheduleSyncNotification()
    }

    func discardUndo() {
        undoController?.discard()
        undoPresentation.clear()
    }

    func discardUndoIfAffected(by records: Set<DomainRecordID>) {
        undoController?.discardIfAffected(by: records)
        if undoController?.availableAction == nil { undoPresentation.clear() }
    }

    private func nextRevision() -> UInt64 {
        nextPresentationRevision &+= 1
        return nextPresentationRevision
    }

    private func stageNoteCreation(
        title: String?,
        id: NoteID
    ) -> (note: Note, revision: UInt64) {
        let createdAt = Date()
        let stamp = VersionStamp(logicalCounter: 0, replicaID: ReplicaID())
        let note = Note(
            id: id,
            createdAt: createdAt,
            title: Self.normalizedTitle(title),
            titleVersion: stamp,
            lifecycleVersion: stamp,
            lastMeaningfulEditAt: createdAt,
            lastMeaningfulEditVersion: stamp
        )
        let revision = stage(TildoneiOSNoteSnapshot(note: note, tasks: []))
        return (note, revision)
    }

    private func commitNoteCreation(_ staged: Note, revision: UInt64) async throws -> Note {
        do {
            let persisted = try await withRepository { repository in
                try await repository.createNote(
                    id: staged.id,
                    createdAt: staged.createdAt,
                    title: staged.title,
                    color: staged.color
                )
            }
            publishPersistedNote(persisted, ifCurrentRevision: revision)
            scheduleSyncNotification()
            return persisted
        } catch {
            if latestPresentationMutationRevisions[staged.id] == revision {
                finishPendingMutation(staged.id, revision: revision)
                removePresentation(for: staged.id)
            }
            throw error
        }
    }

    @discardableResult
    private func stage(_ snapshot: TildoneiOSNoteSnapshot) -> UInt64 {
        guard let note = snapshot.note else { return nextRevision() }
        let revision = nextRevision()
        latestPresentationMutationRevisions[note.id] = revision
        pendingPresentationMutationRevisions[note.id] = revision
        updatePresentation(snapshot)
        refreshOverview(for: note.id)
        return revision
    }

    private func stageTaskInsertion(
        _ task: Task,
        in snapshot: TildoneiOSNoteSnapshot
    ) -> UInt64 {
        var tasks = snapshot.tasks
        tasks.append(task)
        tasks.sort(by: Task.orderedBefore)
        return stage(TildoneiOSNoteSnapshot(
            note: Self.presentationNote(snapshot.note!, meaningfulEditAt: task.createdAt),
            tasks: tasks
        ))
    }

    private func stageTaskUpdates(
        _ updates: [TaskStructureUpdate],
        in snapshot: TildoneiOSNoteSnapshot,
        textOverrides: [TaskID: String] = [:]
    ) -> UInt64 {
        let updatesByID = Dictionary(uniqueKeysWithValues: updates.map { ($0.id, $0) })
        let tasks = snapshot.tasks.map { task in
            Self.presentationTask(
                task,
                applying: updatesByID[task.id],
                text: textOverrides[task.id]
            )
        }.sorted(by: Task.orderedBefore)
        return stage(TildoneiOSNoteSnapshot(
            note: Self.presentationNote(snapshot.note!, meaningfulEditAt: Date()),
            tasks: tasks
        ))
    }

    private func publishPersistedNote(_ note: Note, ifCurrentRevision revision: UInt64) {
        guard latestPresentationMutationRevisions[note.id] == revision,
              let snapshot = notePresentations[note.id]?.snapshot else { return }
        updatePresentation(TildoneiOSNoteSnapshot(note: note, tasks: snapshot.tasks))
        finishPendingMutation(note.id, revision: revision)
        refreshOverview(for: note.id)
    }

    private func reconcileSuccessfulMutation(_ noteID: NoteID, revision: UInt64) async {
        guard latestPresentationMutationRevisions[noteID] == revision else { return }
        do {
            try await reloadNote(noteID, ifCurrentMutationRevision: revision)
        } catch {
            finishPendingMutation(noteID, revision: revision)
        }
    }

    private func rollback(_ noteID: NoteID, revision: UInt64) async {
        guard latestPresentationMutationRevisions[noteID] == revision else { return }
        do {
            try await reloadNote(noteID, ifCurrentMutationRevision: revision)
        } catch let error as PersistenceError {
            finishPendingMutation(noteID, revision: revision)
            if case .missing(.note, _) = error { removePresentation(for: noteID) }
        } catch {
            finishPendingMutation(noteID, revision: revision)
        }
    }

    private func reloadNote(_ noteID: NoteID, ifCurrentMutationRevision revision: UInt64) async throws {
        guard latestPresentationMutationRevisions[noteID] == revision,
              let repository else { return }
        let reloadRevision = nextRevision()
        latestNoteReloadRevisions[noteID] = reloadRevision
        let note = try await repository.note(id: noteID)
        let tasks = try await repository.orderedTasks(in: noteID)
        guard latestPresentationMutationRevisions[noteID] == revision,
              latestNoteReloadRevisions[noteID] == reloadRevision else { return }
        updatePresentation(TildoneiOSNoteSnapshot(note: note, tasks: tasks))
        finishPendingMutation(noteID, revision: revision)
        refreshOverview(for: noteID)
    }

    private func publishFullReload(
        _ snapshots: [TildoneiOSNoteSnapshot],
        revision: UInt64
    ) {
        guard latestFullReloadRevision == revision else { return }
        let incomingIDs = Set(snapshots.compactMap { $0.note?.id })
        let removalIDs = notePresentations.keys.filter { !incomingIDs.contains($0) }
        for noteID in removalIDs {
            guard pendingPresentationMutationRevisions[noteID] == nil,
                  (latestNoteReloadRevisions[noteID] ?? 0) <= revision,
                  (latestPresentationMutationRevisions[noteID] ?? 0) <= revision else { continue }
            notePresentations[noteID]?.update(.empty)
            notePresentations[noteID] = nil
        }
        for snapshot in snapshots {
            guard let noteID = snapshot.note?.id,
                  pendingPresentationMutationRevisions[noteID] == nil,
                  (latestNoteReloadRevisions[noteID] ?? 0) <= revision,
                  (latestPresentationMutationRevisions[noteID] ?? 0) <= revision else { continue }
            updatePresentation(snapshot)
        }
        refreshOverview()
    }

    private func updatePresentation(_ snapshot: TildoneiOSNoteSnapshot) {
        guard let noteID = snapshot.note?.id else { return }
        presentation(for: noteID).update(snapshot)
    }

    private func removePresentation(for noteID: NoteID) {
        notePresentations[noteID]?.update(.empty)
        notePresentations[noteID] = nil
        refreshOverview(for: noteID)
    }

    private func clearPresentationState() {
        for presentation in notePresentations.values { presentation.update(.empty) }
        notePresentations = [:]
        latestPresentationMutationRevisions = [:]
        pendingPresentationMutationRevisions = [:]
        latestNoteReloadRevisions = [:]
        overviewPresentation.update(.init())
        contentRevision &+= 1
    }

    private func refreshOverview(for noteID: NoteID? = nil) {
        if let noteID {
            var updated = overviewPresentation.snapshot
            updated.notes.removeAll { $0.id == noteID }
            updated.taskSummaries[noteID] = nil
            updated.taskListTexts[noteID] = nil
            updated.taskPreviews[noteID] = nil
            if let snapshot = notePresentations[noteID]?.snapshot,
               let note = snapshot.note {
                updated.notes.append(note)
                Self.populateOverview(&updated, note: note, tasks: snapshot.tasks)
            }
            updated.notes.sort(by: Self.noteOverviewOrder)
            overviewPresentation.update(updated)
            contentRevision &+= 1
            return
        }

        var updated = TildoneiOSOverviewSnapshot()
        let snapshots = notePresentations.values.map(\.snapshot).filter { $0.note != nil }
        updated.notes = snapshots.compactMap(\.note).sorted(by: Self.noteOverviewOrder)
        for snapshot in snapshots {
            guard let note = snapshot.note else { continue }
            Self.populateOverview(&updated, note: note, tasks: snapshot.tasks)
        }
        overviewPresentation.update(updated)
        contentRevision &+= 1
    }

    private static func noteOverviewOrder(_ lhs: Note, _ rhs: Note) -> Bool {
        if lhs.lastMeaningfulEditAt != rhs.lastMeaningfulEditAt {
            return lhs.lastMeaningfulEditAt > rhs.lastMeaningfulEditAt
        }
        return lhs.id < rhs.id
    }

    private static func populateOverview(
        _ overview: inout TildoneiOSOverviewSnapshot,
        note: Note,
        tasks: [Task]
    ) {
        overview.taskSummaries[note.id] = NoteTaskSummary(
            noteID: note.id,
            tasks: TaskHierarchy.leafTasks(in: tasks)
        )
        let oldestTasksFirst = tasks.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }
        let listText = oldestTasksFirst.map(\.text).joined(separator: ", ")
        if !listText.isEmpty { overview.taskListTexts[note.id] = listText }
        let subtaskProgresses = TaskHierarchy.subtaskProgresses(in: tasks)
        overview.taskPreviews[note.id] = tasks.map {
            NoteTaskPreview($0, subtaskProgress: subtaskProgresses[$0.id])
        }
    }

    private func requireSnapshot(_ noteID: NoteID) throws -> TildoneiOSNoteSnapshot {
        guard let snapshot = notePresentations[noteID]?.snapshot, snapshot.note != nil else {
            throw TildoneiOSPresentationError.noWorkspace
        }
        return snapshot
    }

    private func requireSnapshot(
        containing taskID: TaskID
    ) throws -> (TildoneiOSNoteSnapshot, Task) {
        for presentation in notePresentations.values {
            let snapshot = presentation.snapshot
            if let task = snapshot.tasks.first(where: { $0.id == taskID }) {
                return (snapshot, task)
            }
        }
        throw PersistenceError.missing(.task, taskID.stringValue)
    }

    private func scheduleSyncNotification() {
        guard let coordinator else { return }
        Swift.Task { await coordinator.notifyLocalChanges() }
    }

    private func finishPendingMutation(_ noteID: NoteID, revision: UInt64) {
        guard pendingPresentationMutationRevisions[noteID] == revision else { return }
        pendingPresentationMutationRevisions[noteID] = nil
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

    private func openLocalWorkspace(status: SyncStatus) async throws {
        let localRepository = try await repositoryFactory(.localOnly)
        try await localRepository.migrateMissingNoteColors(
            colorsByNoteID: [:],
            authority: .platformDefault
        )
        self.localRepository = localRepository
        try await activateLocalWorkspace(localRepository, status: status)
    }

    private func activateLocalWorkspace(
        _ localRepository: TildoneRepository,
        status: SyncStatus
    ) async throws {
        repository = localRepository
        undoController = ConsequentialActionUndoController(repository: localRepository)
        activeWorkspace = nil
        isUsingLocalWorkspace = true
        hasWorkspace = true
        transportState = .active
        syncStatus = status
        isEmptyStateConfirmed = true
        clearPresentationState()
        try await reloadNotes()
    }

    private func activateAccountWorkspace(
        _ accountRepository: TildoneRepository,
        workspaceID: UUID
    ) async throws {
        repository = accountRepository
        undoController = ConsequentialActionUndoController(repository: accountRepository)
        activeWorkspace = workspaceID
        accountWorkspaceID = workspaceID
        isUsingLocalWorkspace = false
        hasWorkspace = true
        transportState = transportStateStore.state(for: workspaceID)
        clearPresentationState()
        if !synchronizationEnabled {
            syncStatus = .disabled
            isEmptyStateConfirmed = true
        } else if transportState == .paused {
            syncStatus = SyncStatus(
                availability: .available,
                activity: .paused,
                pendingMutationCount: try await accountRepository.pendingMutations().count
            )
            isEmptyStateConfirmed = true
        } else {
            syncStatus = SyncStatus(availability: .available, activity: .idle)
            isEmptyStateConfirmed = false
        }
        try await reloadNotes()
        await Swift.Task.yield()
        if SyncTransportActivationPolicy.shouldActivate(
            enabledByDefault: synchronizationEnabled,
            persistedState: transportState
        ) {
            let checkpointStatus = try await startCoordinator(
                for: accountRepository,
                workspaceID: workspaceID
            )
            try await reloadNotes()
            isEmptyStateConfirmed = checkpointStatus.lastSuccessfulSyncAt != nil
        }
    }

    private enum LocalWorkspaceChoice: String {
        case stayLocal
        case useICloud
    }

    private func localWorkspaceChoice(for workspaceID: UUID) -> LocalWorkspaceChoice? {
        let key = "iOSLocalWorkspaceChoice.\(workspaceID.uuidString.lowercased())"
        return defaults.string(forKey: key).flatMap(LocalWorkspaceChoice.init(rawValue:))
    }

    private func setLocalWorkspaceChoice(_ choice: LocalWorkspaceChoice, for workspaceID: UUID) {
        let key = "iOSLocalWorkspaceChoice.\(workspaceID.uuidString.lowercased())"
        defaults.set(choice.rawValue, forKey: key)
    }

    private func startCoordinator(
        for repository: TildoneRepository,
        workspaceID: UUID
    ) async throws -> SyncStatus {
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
            onRemoteChange: { [weak self] remoteChange in
                await self?.requestRemoteContentReload(
                    for: workspaceID,
                    changedRecords: remoteChange.changedRecords
                )
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
                    self?.present(status: status)
                }
            }
        }
        await coordinator.start()
        let checkpointStatus = await coordinator.statusModel.snapshot()
        present(status: checkpointStatus)
        return checkpointStatus
    }

    private func closeWorkspace(status: SyncStatus) async {
        statusTask?.cancel()
        statusTask = nil
        remoteReloadTask?.cancel()
        remoteReloadTask = nil
        remoteReloadRequested = false
        if let coordinator { await coordinator.stop() }
        coordinator = nil
        repository = nil
        localRepository = nil
        accountRepository = nil
        undoController = nil
        undoPresentation.clear()
        activeWorkspace = nil
        accountWorkspaceID = nil
        isUsingLocalWorkspace = false
        shouldOfferCloudAdoption = false
        transportState = .active
        clearPresentationState()
        hasWorkspace = false
        isEmptyStateConfirmed = false
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

    private func requestRemoteContentReload(
        for workspaceID: UUID,
        changedRecords: Set<DomainRecordID>
    ) async {
        guard activeWorkspace == workspaceID else { return }
        discardUndoIfAffected(by: changedRecords)
        remoteReloadRequested = true
        let task: Swift.Task<Void, Never>
        if let remoteReloadTask {
            task = remoteReloadTask
        } else {
            task = Swift.Task { [weak self] in
                await Swift.Task.yield()
                await self?.drainRemoteContentReloads(for: workspaceID)
            }
            remoteReloadTask = task
        }
        await task.value
    }

    private func drainRemoteContentReloads(for workspaceID: UUID) async {
        while remoteReloadRequested,
              !Swift.Task.isCancelled,
              activeWorkspace == workspaceID {
            remoteReloadRequested = false
            await reloadRemoteContent(for: workspaceID)
        }
        remoteReloadTask = nil
    }

    private nonisolated static func makeRepository(
        workspace: WorkspaceIdentity
    ) async throws -> TildoneRepository {
        try await Swift.Task.detached(priority: .userInitiated) {
            guard let baseDirectory = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first else { throw PersistenceError.invalidStoreLocation }
            return try TildoneRepository(
                descriptor: .persistent(baseDirectory: baseDirectory, workspace: workspace)
            )
        }.value
    }

    private func publishUndoAvailability() {
        guard !Self.requiresUndoInvalidation(syncStatus) else {
            discardUndo()
            return
        }
        guard let action = undoController?.availableAction else {
            undoPresentation.clear()
            return
        }
        undoPresentation.present(action)
    }

    private static func requiresUndoInvalidation(_ status: SyncStatus) -> Bool {
        status.activity == .attentionNeeded || [
            .adoptionRequired,
            .accountChanged,
            .zoneResetRequired,
            .incompatibleRemoteData,
        ].contains(status.availability)
    }

    private static func normalizedTitle(_ title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
        return title
    }

    private static func presentationNote(
        _ note: Note,
        title: String?,
        meaningfulEditAt: Date
    ) -> Note {
        Note(
            id: note.id,
            createdAt: note.createdAt,
            title: title,
            titleVersion: note.titleVersion,
            color: note.color,
            colorVersion: note.colorVersion,
            lifecycle: note.lifecycle,
            lifecycleVersion: note.lifecycleVersion,
            lastMeaningfulEditAt: meaningfulEditAt,
            lastMeaningfulEditVersion: note.lastMeaningfulEditVersion,
            schemaVersion: note.schemaVersion
        )
    }

    private static func presentationNote(_ note: Note, color: NoteColor) -> Note {
        Note(
            id: note.id,
            createdAt: note.createdAt,
            title: note.title,
            titleVersion: note.titleVersion,
            color: color,
            colorVersion: note.colorVersion,
            lifecycle: note.lifecycle,
            lifecycleVersion: note.lifecycleVersion,
            lastMeaningfulEditAt: note.lastMeaningfulEditAt,
            lastMeaningfulEditVersion: note.lastMeaningfulEditVersion,
            schemaVersion: note.schemaVersion
        )
    }

    private static func presentationNote(_ note: Note, meaningfulEditAt: Date) -> Note {
        presentationNote(note, title: note.title, meaningfulEditAt: meaningfulEditAt)
    }

    private static func presentationTask(
        id: TaskID,
        noteID: NoteID,
        createdAt: Date,
        text: String,
        orderToken: OrderToken,
        indentLevel: Int,
        basedOn note: Note
    ) -> Task {
        let stamp = note.lastMeaningfulEditVersion
        return Task(
            id: id,
            noteID: noteID,
            createdAt: createdAt,
            text: text,
            textVersion: stamp,
            completionVersion: stamp,
            orderToken: orderToken,
            orderVersion: stamp,
            indentLevel: indentLevel,
            indentVersion: stamp,
            lifecycleVersion: stamp
        )
    }

    private static func presentationTask(
        _ task: Task,
        applying update: TaskStructureUpdate?,
        text: String?
    ) -> Task {
        Task(
            id: task.id,
            noteID: task.noteID,
            createdAt: task.createdAt,
            text: text ?? task.text,
            textVersion: task.textVersion,
            completion: update?.completion ?? task.completion,
            completionVersion: task.completionVersion,
            orderToken: update?.orderToken ?? task.orderToken,
            orderVersion: task.orderVersion,
            indentLevel: update?.indentLevel ?? task.indentLevel,
            indentVersion: task.indentVersion,
            lifecycle: task.lifecycle,
            lifecycleVersion: task.lifecycleVersion,
            schemaVersion: task.schemaVersion
        )
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
