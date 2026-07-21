//
//  TildoneiOSRootView.swift
//  Tildone
//
//  The iPhone presentation layer deliberately works with immutable domain
//  snapshots. CloudKit and SwiftData remain behind TildoneRepository and the
//  Stage 8 coordinator.
//
import SwiftUI
import TildoneDomain
import TildonePersistence
import TildoneSync

@MainActor
final class TildoneiOSApplicationModel: ObservableObject {
    typealias RepositoryFactory = (WorkspaceIdentity) throws -> TildoneRepository

    @Published private(set) var notes: [Note] = []
    @Published private(set) var syncStatus: SyncStatus = .disabled
    @Published private(set) var isResolvingWorkspace = true
    @Published private(set) var hasWorkspace = false
    /// Advances for every successful repository reload, even when the note
    /// values themselves are unchanged. A remote task can arrive in a
    /// different CKSyncEngine batch than its owning note.
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
        // Re-resolve the account identity before resuming an existing
        // coordinator. This independently enforces the account-workspace
        // privacy boundary if an account-change event was delayed while the
        // application was suspended.
        start()
    }

    /// Requests an immediate transport checkpoint. Local editing never waits
    /// for this operation and remains available if the network is unavailable.
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
        notes = try await repository.visibleNotes()
        contentRevision &+= 1
    }

    func tasks(in noteID: NoteID) async throws -> [Task] {
        guard let repository else { return [] }
        return try await repository.orderedTasks(in: noteID)
    }

    @discardableResult
    func createNote(title: String? = nil) async throws -> Note {
        let note = try await withRepository { repository in
            try await repository.createNote(id: NoteID(), createdAt: Date(), title: title)
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

    // MARK: Test and lifecycle support

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
        if status.availability == .accountChanged { hasWorkspace = false; notes = [] }
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
        hasWorkspace = false
        syncStatus = status
    }

    private func reloadRemoteContent(for workspaceID: UUID) async {
        guard activeWorkspace == workspaceID else { return }
        do {
            try await reloadNotes()
        } catch {
            // Keep the last complete snapshots visible. A subsequent
            // foreground checkpoint retries the repository reload.
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

enum TildoneiOSPresentationError: Error { case noWorkspace }

struct TildoneiOSRootView: View {
    @ObservedObject var appModel: TildoneiOSApplicationModel

    var body: some View {
        Group {
            if appModel.hasWorkspace {
                NotesListView(appModel: appModel)
            } else if appModel.isResolvingWorkspace {
                ProgressView("Opening Tildone…")
            } else {
                WorkspaceStatusView(status: appModel.syncStatus) {
                    appModel.start()
                }
            }
        }
    }
}

private struct NotesListView: View {
    @ObservedObject var appModel: TildoneiOSApplicationModel
    @State private var path: [NoteID] = []
    @State private var noteToRename: Note?
    @State private var renamedTitle = ""
    @State private var noteToDelete: Note?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if appModel.notes.isEmpty {
                    ContentUnavailableView {
                        Label("No Notes Yet", systemImage: "checklist")
                    } description: {
                        Text("Create a note to keep a small checklist close at hand.")
                    } actions: {
                        Button("Create Note", action: createNote)
                    }
                } else {
                    List {
                        ForEach(appModel.notes, id: \.id) { note in
                            NavigationLink(value: note.id) {
                                NoteListRow(note: note)
                            }
                            .contextMenu {
                                Button("Rename") { beginRename(note) }
                                Button("Delete", role: .destructive) { noteToDelete = note }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { noteToDelete = note }
                                Button("Rename") { beginRename(note) }.tint(.orange)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SyncStatusMenu(status: appModel.syncStatus, syncNow: appModel.syncNow)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createNote) { Label("New Note", systemImage: "plus") }
                        .accessibilityLabel("Create note")
                }
            }
            .navigationDestination(for: NoteID.self) { noteID in
                ChecklistView(appModel: appModel, noteID: noteID)
            }
        }
        .alert("Rename Note", isPresented: Binding(
            get: { noteToRename != nil }, set: { if !$0 { noteToRename = nil } }
        )) {
            TextField("Title", text: $renamedTitle)
            Button("Cancel", role: .cancel) { noteToRename = nil }
            Button("Save") {
                guard let note = noteToRename else { return }
                Swift.Task { try? await appModel.rename(noteID: note.id, title: renamedTitle) }
                noteToRename = nil
            }
        }
        .confirmationDialog("Delete this note?", isPresented: Binding(
            get: { noteToDelete != nil }, set: { if !$0 { noteToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) {
                guard let note = noteToDelete else { return }
                Swift.Task { try? await appModel.delete(noteID: note.id) }
                noteToDelete = nil
            }
        } message: { Text("Its checklist will be removed from your active notes.") }
    }

    private func createNote() {
        Swift.Task {
            guard let note = try? await appModel.createNote() else { return }
            path.append(note.id)
        }
    }

    private func beginRename(_ note: Note) {
        noteToRename = note
        renamedTitle = note.title ?? ""
    }
}

private struct NoteListRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? note.title! : "Untitled Note")
                .font(.body.weight(.medium))
                .lineLimit(2)
            Text(note.lastMeaningfulEditAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(note.title?.isEmpty == false ? note.title! : "Untitled Note")
    }
}

private struct ChecklistView: View {
    @ObservedObject var appModel: TildoneiOSApplicationModel
    let noteID: NoteID
    @Environment(\.dismiss) private var dismiss
    @State private var note: Note?
    @State private var tasks: [Task] = []
    @State private var newTaskText = ""
    @State private var title = ""
    @State private var titleBaseline: String?
    @FocusState private var focusedTask: TaskID?
    @FocusState private var isAddingTask: Bool
    @FocusState private var isEditingTitle: Bool

    var body: some View {
        Group {
            if let note {
                List {
                    Section {
                        TextField("Note title", text: $title)
                            .focused($isEditingTitle)
                            .font(.title2.weight(.semibold))
                            .submitLabel(.done)
                            .onSubmit { saveTitle() }
                            .onChange(of: isEditingTitle) { wasEditing, isEditing in
                                guard wasEditing, !isEditing else { return }
                                finishTitleEditing()
                            }
                    }
                    Section("Checklist") {
                        ForEach(tasks, id: \.id) { task in
                            TaskRow(
                                task: task,
                                focusedTask: $focusedTask,
                                onCommit: { value in
                                    try? await appModel.edit(taskID: task.id, text: value)
                                    await reload()
                                },
                                onToggle: {
                                    try? await appModel.setCompletion(taskID: task.id, completed: !task.isCompleted)
                                    await reload()
                                },
                                onDelete: {
                                    try? await appModel.delete(taskID: task.id)
                                    await reload()
                                },
                                onMoveUp: {
                                    await move(taskID: task.id, by: -1)
                                },
                                onMoveDown: {
                                    await move(taskID: task.id, by: 1)
                                }
                            )
                            .swipeActions(edge: .trailing) {
                                Button("Delete", role: .destructive) {
                                    Swift.Task { await delete(taskID: task.id) }
                                }
                            }
                        }
                        .onMove(perform: move)

                        TextField("New task", text: $newTaskText)
                            .focused($isAddingTask)
                            .submitLabel(.next)
                            .onSubmit { addTask() }
                            .accessibilityLabel("New task")
                    }
                }
                .navigationTitle(note.title?.isEmpty == false ? note.title! : "Untitled Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { EditButton() }
                .onDisappear { saveTitle() }
            } else {
                ContentUnavailableView("This note was deleted", systemImage: "trash")
            }
        }
        .task {
            await reload()
            let isUntitled = note?.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            isEditingTitle = isUntitled
            isAddingTask = !isUntitled && tasks.isEmpty
        }
        .onChange(of: appModel.contentRevision) { _, _ in
            if !appModel.notes.contains(where: { $0.id == noteID }) { dismiss() }
            else { Swift.Task { await reload() } }
        }
    }

    private func reload() async {
        note = appModel.notes.first(where: { $0.id == noteID })
        guard note != nil else { return }
        tasks = (try? await appModel.tasks(in: noteID)) ?? []
        if !isEditingTitle || titleBaseline == nil {
            title = note?.title ?? ""
            titleBaseline = Self.normalizedTitle(note?.title)
        }
    }

    private func saveTitle() {
        let normalized = Self.normalizedTitle(title)
        guard normalized != titleBaseline else { return }
        titleBaseline = normalized
        Swift.Task {
            try? await appModel.rename(noteID: noteID, title: normalized)
            await reload()
        }
    }

    private func finishTitleEditing() {
        if Self.normalizedTitle(title) == titleBaseline {
            title = note?.title ?? ""
            titleBaseline = Self.normalizedTitle(note?.title)
        } else {
            saveTitle()
        }
    }

    private static func normalizedTitle(_ title: String?) -> String? {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return nil }
        return title
    }

    private func addTask() {
        let text = newTaskText
        newTaskText = ""
        Swift.Task {
            _ = try? await appModel.addTask(noteID: noteID, text: text, after: tasks)
            await reload()
            isAddingTask = true
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let task = source.first.map({ tasks[$0] }) else { return }
        Swift.Task { try? await appModel.move(taskID: task.id, in: tasks, from: source, to: destination); await reload() }
    }

    private func move(taskID: TaskID, by offset: Int) async {
        guard let sourceIndex = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let destination = sourceIndex + offset
        guard tasks.indices.contains(destination) else { return }
        try? await appModel.move(
            taskID: taskID,
            in: tasks,
            from: IndexSet(integer: sourceIndex),
            to: offset < 0 ? destination : destination + 1
        )
        await reload()
    }

    private func delete(taskID: TaskID) async {
        try? await appModel.delete(taskID: taskID)
        await reload()
    }
}

private struct TaskRow: View {
    let task: Task
    var focusedTask: FocusState<TaskID?>.Binding
    let onCommit: (String) async -> Void
    let onToggle: () async -> Void
    let onDelete: () async -> Void
    let onMoveUp: () async -> Void
    let onMoveDown: () async -> Void
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Swift.Task { await onToggle() }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? Color.accentColor : Color.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark task incomplete" : "Complete task")

            TextField("Task", text: $draft, axis: .vertical)
                .focused(focusedTask, equals: task.id)
                .lineLimit(1...5)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .submitLabel(.done)
                .onSubmit { commit() }
                .onChange(of: focusedTask.wrappedValue) { oldValue, newValue in
                    if oldValue == task.id, newValue != task.id { commit() }
                }
                .onChange(of: task.text) { _, remoteText in
                    // Do not overwrite a focused local draft. A remote update to an
                    // unrelated row never touches this state because identity is stable.
                    if focusedTask.wrappedValue != task.id { draft = remoteText }
                }
        }
        .onAppear { draft = task.text }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: task.isCompleted ? "Mark incomplete" : "Complete") {
            Swift.Task { await onToggle() }
        }
        .accessibilityAction(named: "Delete") { Swift.Task { await onDelete() } }
        .accessibilityAction(named: "Move Up") { Swift.Task { await onMoveUp() } }
        .accessibilityAction(named: "Move Down") { Swift.Task { await onMoveDown() } }
    }

    private func commit() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != task.text else { return }
        Swift.Task { await onCommit(value) }
    }
}

private struct SyncStatusMenu: View {
    let status: SyncStatus
    let syncNow: () -> Void

    var body: some View {
        Menu {
            Text(SyncStatusPresentation.title(for: status))
            if let detail = SyncStatusPresentation.detail(for: status) { Text(detail) }
            if status.pendingMutationCount > 0 { Text("\(status.pendingMutationCount) local changes waiting") }
            if status.availability == .available {
                Divider()
                Button("Sync Now", systemImage: "arrow.triangle.2.circlepath", action: syncNow)
            }
        } label: {
            Image(systemName: SyncStatusPresentation.symbol(for: status))
                .accessibilityLabel(SyncStatusPresentation.title(for: status))
        }
    }
}

private struct WorkspaceStatusView: View {
    let status: SyncStatus
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(SyncStatusPresentation.title(for: status), systemImage: SyncStatusPresentation.symbol(for: status))
        } description: {
            Text(SyncStatusPresentation.detail(for: status) ?? "Tildone cannot open a workspace right now.")
        } actions: {
            if status.availability == .temporarilyUnavailable {
                Button("Try Again", action: retry)
            }
        }
        .padding()
    }
}

enum SyncStatusPresentation {
    static func title(for status: SyncStatus) -> String {
        switch status.availability {
        case .disabled: "Sync is disabled"
        case .available where status.activity == .syncing: "Updating iCloud"
        case .available where status.activity == .offline: "Working offline"
        case .available where status.activity == .attentionNeeded: "iCloud needs attention"
        case .available: "iCloud is ready"
        case .noAccount: "Sign in to iCloud"
        case .restricted: "iCloud is restricted"
        case .temporarilyUnavailable: "iCloud is unavailable"
        case .adoptionRequired: "Workspace needs attention"
        case .accountChanged: "iCloud account changed"
        case .zoneResetRequired: "Sync needs attention"
        case .incompatibleRemoteData: "Update Tildone to continue"
        }
    }

    static func detail(for status: SyncStatus) -> String? {
        switch status.availability {
        case .disabled: "Changes stay on this iPhone while development sync is disabled."
        case .available where status.activity == .offline: "You can keep editing. Changes will sync when iCloud is available."
        case .available where status.activity == .attentionNeeded:
            switch status.issue {
            case .quotaExceeded: "iCloud storage or service quota needs attention. Local editing is still available."
            case .permission: "Tildone cannot access iCloud. Check iCloud access in Settings."
            case .malformedRemoteRecord: "Some synchronized data could not be read. Local editing is still available."
            case .futureSchema: "Synced data was created by a newer version of Tildone."
            case .network: "The network is unavailable. Local editing is still available."
            case .service: "iCloud is temporarily unavailable. Local editing is still available."
            case .accountChanged: "The iCloud account changed. Relaunch Tildone before continuing."
            case .zoneReset: "The synchronized workspace needs attention before syncing can continue."
            case .unknown, nil: "Synchronization could not finish. Local editing is still available; try again."
            }
        case .available: nil
        case .noAccount: "Sign in to iCloud in Settings to use your Tildone notes here."
        case .restricted: "This iPhone is not permitted to use iCloud for Tildone."
        case .temporarilyUnavailable: "Your notes stay safe on this iPhone. Try again when iCloud is available."
        case .adoptionRequired: "This local workspace cannot be uploaded until its adoption policy is approved."
        case .accountChanged: "For privacy, notes from the previous account are no longer shown. Relaunch after changing accounts."
        case .zoneResetRequired: "Synchronization is paused until this workspace is reviewed."
        case .incompatibleRemoteData: "This workspace contains data from a newer version of Tildone."
        }
    }

    static func symbol(for status: SyncStatus) -> String {
        switch status.availability {
        case .available where status.activity == .syncing: "arrow.triangle.2.circlepath"
        case .available: "icloud"
        case .disabled: "icloud.slash"
        case .noAccount, .restricted: "person.crop.circle.badge.exclamationmark"
        case .temporarilyUnavailable: "wifi.exclamationmark"
        case .adoptionRequired, .accountChanged, .zoneResetRequired, .incompatibleRemoteData: "exclamationmark.triangle"
        }
    }
}

#Preview {
    TildoneiOSRootView(appModel: TildoneiOSApplicationModel(
        repositoryFactory: { _ in try TildoneRepository(descriptor: .inMemory(workspace: .account(UUID()))) },
        accountResolver: { CloudAccountSnapshot(state: .noAccount, workspaceID: nil) }
    ))
}
