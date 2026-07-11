import Foundation
import SwiftData
import TildoneDomain

public actor TildoneRepository: TildoneRepositoryProtocol {
    private let container: ModelContainer
    private let workspace: WorkspaceIdentity
    private let now: @Sendable () -> Date
    private var failNextSave = false

    public init(
        descriptor: PersistenceStoreDescriptor,
        replicaID: ReplicaID = ReplicaID(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        self.workspace = descriptor.workspace
        self.now = now
        do {
            container = try Self.makeContainer(descriptor: descriptor)
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.openFailure
        }

        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let metadata = try context.fetch(FetchDescriptor<WorkspaceMetadata>())
            if metadata.isEmpty {
                context.insert(WorkspaceMetadata(
                    workspaceKindRawValue: descriptor.workspace.kindRawValue,
                    opaqueWorkspaceID: descriptor.workspace.opaqueID,
                    replicaID: replicaID.stringValue
                ))
                try context.save()
            } else {
                guard metadata.count == 1,
                      metadata[0].workspaceKindRawValue == descriptor.workspace.kindRawValue,
                      metadata[0].opaqueWorkspaceID == descriptor.workspace.opaqueID,
                      ReplicaID(string: metadata[0].replicaID) != nil,
                      metadata[0].logicalCounter >= 0,
                      metadata[0].sharedSchemaVersion == 1 else {
                    throw PersistenceError.workspaceMismatch
                }
            }
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.openFailure
        }
    }

    public nonisolated static func storeURL(for descriptor: PersistenceStoreDescriptor) throws -> URL? {
        guard descriptor.kind != .inMemory else { return nil }
        guard let base = descriptor.baseDirectory, base.isFileURL else {
            throw PersistenceError.invalidStoreLocation
        }

        let rootName: String
        switch descriptor.kind {
        case .persistent: rootName = "TildoneSharedStore-v1"
        case .preview: rootName = "TildoneSharedPreview-(descriptor.identifier.uuidString.lowercased())"
        case .temporaryMigration: rootName = "TildoneSharedMigration-(descriptor.identifier.uuidString.lowercased())"
        case .inMemory: return nil
        }
        var directory = base.appendingPathComponent(rootName, isDirectory: true)
        switch descriptor.workspace {
        case .localOnly:
            directory.appendPathComponent("local-only", isDirectory: true)
        case let .account(accountID):
            directory.appendPathComponent("accounts", isDirectory: true)
            directory.appendPathComponent(accountID.uuidString.lowercased(), isDirectory: true)
        }
        return directory.appendingPathComponent("tildone-shared.sqlite", isDirectory: false)
    }

    private nonisolated static func makeContainer(
        descriptor: PersistenceStoreDescriptor
    ) throws -> ModelContainer {
        let schema = Schema(versionedSchema: TildoneSchemaV1.self)
        let configuration: ModelConfiguration
        if descriptor.kind == .inMemory {
            configuration = ModelConfiguration(
                "TildoneSharedMemory-(descriptor.identifier.uuidString.lowercased())",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                groupContainer: .none,
                cloudKitDatabase: .none
            )
        } else {
            guard let url = try storeURL(for: descriptor) else {
                throw PersistenceError.invalidStoreLocation
            }
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                throw PersistenceError.invalidStoreLocation
            }
            configuration = ModelConfiguration(
                "TildoneSharedDisk-(descriptor.identifier.uuidString.lowercased())",
                schema: schema,
                url: url,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        }
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: TildoneSchemaMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            throw PersistenceError.openFailure
        }
    }

    // MARK: Notes

    public func createNote(id: NoteID, createdAt: Date, title: String?) throws -> Note {
        let context = mutationContext()
        guard try storedNote(id: id, in: context) == nil else {
            throw PersistenceError.duplicateID(.note, id.stringValue)
        }
        let metadata = try workspaceMetadata(in: context)
        let stamp = try nextStamp(metadata)
        let note = Note(
            id: id,
            createdAt: createdAt,
            title: title,
            titleVersion: stamp,
            lifecycleVersion: stamp,
            lastMeaningfulEditAt: createdAt
        )
        context.insert(try StoredDomainMapping.storedNote(from: note))
        try enqueue(.note, id: id.stringValue, sequence: stamp.logicalCounter, in: context)
        try saveMutation(context)
        return note
    }

    public func note(id: NoteID, includingDeleted: Bool = false) throws -> Note {
        let context = readContext()
        guard let stored = try storedNote(id: id, in: context) else {
            throw PersistenceError.missing(.note, id.stringValue)
        }
        let note = try StoredDomainMapping.note(from: stored)
        guard includingDeleted || note.lifecycle == .active else {
            throw PersistenceError.missing(.note, id.stringValue)
        }
        return note
    }

    public func visibleNotes() throws -> [Note] {
        let notes = try readContext().fetch(FetchDescriptor<StoredNote>()).map(StoredDomainMapping.note)
        return notes.filter { $0.lifecycle == .active }.sorted {
            if $0.lastMeaningfulEditAt != $1.lastMeaningfulEditAt {
                return $0.lastMeaningfulEditAt > $1.lastMeaningfulEditAt
            }
            return $0.id < $1.id
        }
    }

    public func notesMeaningfullyEdited(since date: Date) throws -> [Note] {
        try visibleNotes().filter { $0.lastMeaningfulEditAt >= date }
    }

    public func renameNote(id: NoteID, to title: String?, editedAt: Date) throws -> Note {
        let context = mutationContext()
        let stored = try requireStoredNote(id: id, in: context)
        var note = try StoredDomainMapping.note(from: stored)
        guard note.lifecycle == .active else { throw PersistenceError.domainInvariant }
        let stamp = try nextStamp(try workspaceMetadata(in: context), observing: note.titleVersion)
        do { try note.rename(to: title, version: stamp, editedAt: editedAt) }
        catch { throw PersistenceError.domainInvariant }
        try StoredDomainMapping.update(stored, from: note)
        try enqueue(.note, id: id.stringValue, sequence: stamp.logicalCounter, in: context)
        try saveMutation(context)
        return note
    }

    public func deleteNote(id: NoteID) throws {
        let context = mutationContext()
        let stored = try requireStoredNote(id: id, in: context)
        var note = try StoredDomainMapping.note(from: stored)
        guard note.lifecycle == .active else { return }
        let metadata = try workspaceMetadata(in: context)
        let noteStamp = try nextStamp(metadata, observing: note.lifecycleVersion)
        do { try note.delete(version: noteStamp) }
        catch { throw PersistenceError.domainInvariant }
        try StoredDomainMapping.update(stored, from: note)
        try enqueue(.note, id: id.stringValue, sequence: noteStamp.logicalCounter, in: context)

        for storedTask in try storedTasks(noteID: id, in: context) {
            var task = try StoredDomainMapping.task(from: storedTask, expectedNoteID: id)
            guard task.lifecycle == .active else { continue }
            let taskStamp = try nextStamp(metadata, observing: task.lifecycleVersion)
            do { try task.delete(version: taskStamp) }
            catch { throw PersistenceError.domainInvariant }
            try StoredDomainMapping.update(storedTask, from: task)
            try enqueue(.task, id: task.id.stringValue, sequence: taskStamp.logicalCounter, in: context)
        }
        try saveMutation(context)
    }

    public func restoreNote(id: NoteID) throws -> Note {
        let context = mutationContext()
        let stored = try requireStoredNote(id: id, in: context)
        var note = try StoredDomainMapping.note(from: stored)
        guard note.lifecycle == .deleted else { return note }
        let stamp = try nextStamp(try workspaceMetadata(in: context), observing: note.lifecycleVersion)
        do { try note.restore(version: stamp) }
        catch { throw PersistenceError.domainInvariant }
        try StoredDomainMapping.update(stored, from: note)
        try enqueue(.note, id: id.stringValue, sequence: stamp.logicalCounter, in: context)
        try saveMutation(context)
        return note
    }

    // MARK: Tasks

    public func addTask(
        id: TaskID,
        to noteID: NoteID,
        createdAt: Date,
        text: String,
        orderToken: OrderToken
    ) throws -> Task {
        let context = mutationContext()
        guard try storedTask(id: id, in: context) == nil else {
            throw PersistenceError.duplicateID(.task, id.stringValue)
        }
        let storedNote = try requireStoredNote(id: noteID, in: context)
        var note = try StoredDomainMapping.note(from: storedNote)
        guard note.lifecycle == .active else { throw PersistenceError.domainInvariant }
        let stamp = try nextStamp(try workspaceMetadata(in: context))
        let task = Task(
            id: id,
            noteID: noteID,
            createdAt: createdAt,
            text: text,
            textVersion: stamp,
            completionVersion: stamp,
            orderToken: orderToken,
            orderVersion: stamp,
            lifecycleVersion: stamp
        )
        note.recordMeaningfulEdit(at: createdAt)
        try StoredDomainMapping.update(storedNote, from: note)
        context.insert(try StoredDomainMapping.storedTask(from: task))
        try enqueue(.task, id: id.stringValue, sequence: stamp.logicalCounter, in: context)
        try saveMutation(context)
        return task
    }

    public func task(id: TaskID, includingDeleted: Bool = false) throws -> Task {
        let context = readContext()
        guard let stored = try storedTask(id: id, in: context) else {
            throw PersistenceError.missing(.task, id.stringValue)
        }
        let task = try StoredDomainMapping.task(from: stored)
        guard includingDeleted || task.lifecycle == .active else {
            throw PersistenceError.missing(.task, id.stringValue)
        }
        if !includingDeleted {
            let owner = try note(id: task.noteID, includingDeleted: true)
            guard owner.lifecycle == .active else {
                throw PersistenceError.missing(.task, id.stringValue)
            }
        }
        return task
    }

    public func orderedTasks(in noteID: NoteID) throws -> [Task] {
        let owner = try note(id: noteID, includingDeleted: true)
        guard owner.lifecycle == .active else { return [] }
        return try storedTasks(noteID: noteID, in: readContext())
            .map { try StoredDomainMapping.task(from: $0, expectedNoteID: noteID) }
            .filter { $0.lifecycle == .active }
            .sorted(by: Task.orderedBefore)
    }

    public func editTask(id: TaskID, text: String) throws -> Task {
        try mutateTask(id: id) { task, stamp in try task.editText(text, version: stamp) }
    }

    public func setTaskCompletion(id: TaskID, completion: CompletionState) throws -> Task {
        try mutateTask(id: id) { task, stamp in try task.setCompletion(completion, version: stamp) }
    }

    public func moveTask(id: TaskID, to orderToken: OrderToken) throws -> Task {
        try mutateTask(id: id) { task, stamp in try task.move(to: orderToken, version: stamp) }
    }

    public func deleteTask(id: TaskID) throws {
        let existing = try task(id: id, includingDeleted: true)
        guard existing.lifecycle == .active else { return }
        _ = try mutateTask(id: id, allowDeleted: true) { task, stamp in
            try task.delete(version: stamp)
        }
    }

    public func restoreTask(id: TaskID) throws -> Task {
        let existing = try task(id: id, includingDeleted: true)
        guard existing.lifecycle == .deleted else { return existing }
        try mutateTask(id: id, allowDeleted: true) { task, stamp in
            try task.restore(version: stamp)
        }
    }

    public func taskSummary(in noteID: NoteID) throws -> NoteTaskSummary {
        NoteTaskSummary(noteID: noteID, tasks: try orderedTasks(in: noteID))
    }

    private func mutateTask(
        id: TaskID,
        allowDeleted: Bool = false,
        mutation: (inout Task, VersionStamp) throws -> Void
    ) throws -> Task {
        let context = mutationContext()
        let stored = try requireStoredTask(id: id, in: context)
        var task = try StoredDomainMapping.task(from: stored)
        let ownerStored = try requireStoredNote(id: task.noteID, in: context)
        var owner = try StoredDomainMapping.note(from: ownerStored)
        guard owner.lifecycle == .active, allowDeleted || task.lifecycle == .active else {
            throw PersistenceError.domainInvariant
        }
        let metadata = try workspaceMetadata(in: context)
        let stamp = try nextStamp(metadata, observing: maxVersion(in: task))
        do { try mutation(&task, stamp) }
        catch { throw PersistenceError.domainInvariant }
        owner.recordMeaningfulEdit(at: now())
        try StoredDomainMapping.update(ownerStored, from: owner)
        try StoredDomainMapping.update(stored, from: task)
        try enqueue(.task, id: id.stringValue, sequence: stamp.logicalCounter, in: context)
        try saveMutation(context)
        return task
    }

    // MARK: Durable outbox and workspace state

    public func pendingMutations(includeSuperseded: Bool = false) throws -> [PendingMutationSnapshot] {
        let rows = try readContext().fetch(FetchDescriptor<PendingMutation>())
        return try rows
            .filter { includeSuperseded || $0.supersededByMutationID == nil }
            .map(Self.snapshot)
            .sorted { ($0.sequence, $0.id.uuidString) < ($1.sequence, $1.id.uuidString) }
    }

    public func recordMutationAttempt(id: UUID, at date: Date) throws {
        let context = mutationContext()
        let idString = id.uuidString.lowercased()
        let rows = try context.fetch(FetchDescriptor<PendingMutation>(
            predicate: #Predicate { $0.mutationID == idString }
        ))
        guard rows.count == 1, let row = rows.first else {
            throw PersistenceError.missing(.task, idString)
        }
        guard row.attemptCount < Int64.max else { throw PersistenceError.counterOverflow }
        row.attemptCount += 1
        row.lastAttemptAt = date
        try save(context)
    }

    public func acknowledgeMutations(ids: Set<UUID>) throws {
        let context = mutationContext()
        let strings = Set(ids.map { $0.uuidString.lowercased() })
        for row in try context.fetch(FetchDescriptor<PendingMutation>()) where strings.contains(row.mutationID) {
            context.delete(row)
        }
        try save(context)
    }

    public func workspaceSnapshot() throws -> WorkspaceSnapshot {
        let metadata = try workspaceMetadata(in: readContext())
        guard metadata.logicalCounter >= 0,
              let replica = ReplicaID(string: metadata.replicaID) else {
            throw PersistenceError.workspaceMismatch
        }
        return WorkspaceSnapshot(
            identityKind: metadata.workspaceKindRawValue,
            opaqueWorkspaceID: metadata.opaqueWorkspaceID,
            replicaID: replica,
            logicalCounter: UInt64(metadata.logicalCounter),
            sharedSchemaVersion: metadata.sharedSchemaVersion,
            futureSyncEngineState: metadata.futureSyncEngineState
        )
    }

    public func storeFutureSyncEngineState(_ state: Data?) throws {
        let context = mutationContext()
        try workspaceMetadata(in: context).futureSyncEngineState = state
        try save(context)
    }

    // MARK: Internal transaction machinery

    private func readContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func mutationContext() -> ModelContext { readContext() }

    private func saveMutation(_ context: ModelContext) throws {
        do { try save(context) }
        catch { throw PersistenceError.atomicMutationFailure }
    }

    private func save(_ context: ModelContext) throws {
        if failNextSave {
            failNextSave = false
            throw PersistenceError.saveFailure
        }
        do { try context.save() }
        catch { throw PersistenceError.saveFailure }
    }

    private func workspaceMetadata(in context: ModelContext) throws -> WorkspaceMetadata {
        let rows = try context.fetch(FetchDescriptor<WorkspaceMetadata>())
        guard rows.count == 1, let metadata = rows.first,
              metadata.workspaceKindRawValue == workspace.kindRawValue,
              metadata.opaqueWorkspaceID == workspace.opaqueID else {
            throw PersistenceError.workspaceMismatch
        }
        return metadata
    }

    private func nextStamp(
        _ metadata: WorkspaceMetadata,
        observing stamp: VersionStamp? = nil
    ) throws -> VersionStamp {
        guard metadata.logicalCounter >= 0,
              let replica = ReplicaID(string: metadata.replicaID) else {
            throw PersistenceError.workspaceMismatch
        }
        let observed = stamp?.logicalCounter ?? 0
        let current = max(UInt64(metadata.logicalCounter), observed)
        guard current < UInt64(Int64.max) else { throw PersistenceError.counterOverflow }
        let next = current + 1
        metadata.logicalCounter = Int64(next)
        return VersionStamp(logicalCounter: next, replicaID: replica)
    }

    private func enqueue(
        _ kind: PersistedEntityKind,
        id: String,
        sequence: UInt64,
        in context: ModelContext
    ) throws {
        guard sequence <= UInt64(Int64.max) else { throw PersistenceError.counterOverflow }
        let kindRaw = kind.rawValue
        let active = try context.fetch(FetchDescriptor<PendingMutation>(
            predicate: #Predicate {
                $0.targetKindRawValue == kindRaw &&
                $0.targetStableID == id &&
                $0.supersededByMutationID == nil
            }
        ))
        let newID = UUID().uuidString.lowercased()
        for row in active { row.supersededByMutationID = newID }
        context.insert(PendingMutation(
            mutationID: newID,
            targetKindRawValue: kindRaw,
            targetStableID: id,
            sequence: Int64(sequence),
            createdAt: now()
        ))
    }

    private static func snapshot(_ row: PendingMutation) throws -> PendingMutationSnapshot {
        guard let id = UUID(uuidString: row.mutationID),
              let kind = PersistedEntityKind(rawValue: row.targetKindRawValue),
              row.sequence >= 0, row.attemptCount >= 0,
              row.supersededByMutationID == nil || UUID(uuidString: row.supersededByMutationID!) != nil else {
            throw PersistenceError.malformedRepresentation(.task, row.targetStableID, field: "pendingMutation")
        }
        return PendingMutationSnapshot(
            id: id,
            targetKind: kind,
            targetStableID: row.targetStableID,
            sequence: UInt64(row.sequence),
            createdAt: row.createdAt,
            attemptCount: UInt64(row.attemptCount),
            lastAttemptAt: row.lastAttemptAt,
            supersededBy: row.supersededByMutationID.flatMap(UUID.init(uuidString:))
        )
    }

    private func storedNote(id: NoteID, in context: ModelContext) throws -> StoredNote? {
        let value = id.stringValue
        let rows = try context.fetch(FetchDescriptor<StoredNote>(
            predicate: #Predicate { $0.stableID == value }
        ))
        guard rows.count <= 1 else { throw PersistenceError.duplicateID(.note, value) }
        return rows.first
    }

    private func requireStoredNote(id: NoteID, in context: ModelContext) throws -> StoredNote {
        guard let stored = try storedNote(id: id, in: context) else {
            throw PersistenceError.missing(.note, id.stringValue)
        }
        return stored
    }

    private func storedTask(id: TaskID, in context: ModelContext) throws -> StoredTask? {
        let value = id.stringValue
        let rows = try context.fetch(FetchDescriptor<StoredTask>(
            predicate: #Predicate { $0.stableID == value }
        ))
        guard rows.count <= 1 else { throw PersistenceError.duplicateID(.task, value) }
        return rows.first
    }

    private func requireStoredTask(id: TaskID, in context: ModelContext) throws -> StoredTask {
        guard let stored = try storedTask(id: id, in: context) else {
            throw PersistenceError.missing(.task, id.stringValue)
        }
        return stored
    }

    private func storedTasks(noteID: NoteID, in context: ModelContext) throws -> [StoredTask] {
        let value = noteID.stringValue
        return try context.fetch(FetchDescriptor<StoredTask>(
            predicate: #Predicate { $0.noteStableID == value }
        ))
    }

    private func maxVersion(in task: Task) -> VersionStamp {
        [task.textVersion, task.completionVersion, task.orderVersion, task.lifecycleVersion].max()!
    }

    /// Deterministic save interruption used only by `@testable` persistence tests.
    func failNextSaveForTesting() { failNextSave = true }
}
