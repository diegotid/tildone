//
//  TildoneRepository.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
import Foundation
import SwiftData
import TildoneDomain

public actor TildoneRepository: TildoneRepositoryProtocol {
    let container: ModelContainer
    private let ownership: WorkspaceOwnershipLease?
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
        let ownership = try WorkspaceOwnershipLease.acquire(for: Self.storeURL(for: descriptor))
        do {
            container = try Self.makeContainer(descriptor: descriptor)
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.openFailure
        }
        self.ownership = ownership

        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let metadata = try context.fetch(FetchDescriptor<WorkspaceMetadata>())
            if metadata.isEmpty {
                context.insert(WorkspaceMetadata(
                    workspaceKindRawValue: descriptor.workspace.kindRawValue,
                    opaqueWorkspaceID: descriptor.workspace.opaqueID,
                    replicaID: replicaID.stringValue,
                    sharedSchemaVersion: 2
                ))
                try context.save()
            } else {
                guard metadata.count == 1 else { throw PersistenceError.workspaceMismatch }
                if metadata[0].sharedSchemaVersion == 1 {
                    metadata[0].sharedSchemaVersion = 2
                    try context.save()
                }
                try Self.validateWorkspaceMetadata(
                    metadata[0],
                    expectedWorkspace: descriptor.workspace,
                    in: context
                )
            }
        } catch let error as PersistenceError {
            throw error
        } catch {
            throw PersistenceError.openFailure
        }
    }

    public nonisolated static func storeURL(for descriptor: PersistenceStoreDescriptor) throws -> URL? {
        guard descriptor.kind != .inMemory else { return nil }
        if let explicit = descriptor.explicitStoreURL {
            guard explicit.isFileURL else { throw PersistenceError.invalidStoreLocation }
            return explicit.standardizedFileURL
        }
        guard let base = descriptor.baseDirectory, base.isFileURL else {
            throw PersistenceError.invalidStoreLocation
        }

        let rootName: String
        switch descriptor.kind {
        case .persistent: rootName = "TildoneSharedStore-v1"
        case .preview: rootName = "TildoneSharedPreview-\(descriptor.identifier.uuidString.lowercased())"
        case .temporaryMigration: rootName = "TildoneSharedMigration-\(descriptor.identifier.uuidString.lowercased())"
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
        let schema = Schema(versionedSchema: TildoneSchemaV2.self)
        let configuration: ModelConfiguration
        if descriptor.kind == .inMemory {
            configuration = ModelConfiguration(
                "TildoneSharedMemory-\(descriptor.identifier.uuidString.lowercased())",
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
                "TildoneSharedDisk-\(descriptor.identifier.uuidString.lowercased())",
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
            lastMeaningfulEditAt: createdAt,
            lastMeaningfulEditVersion: stamp
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
        let notes = try mappedUniqueNotes(in: readContext())
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
        let metadata = try workspaceMetadata(in: context)
        let titleStamp = try nextStamp(metadata, observing: note.titleVersion)
        let meaningfulEditStamp = try nextStamp(
            metadata,
            observing: max(note.lastMeaningfulEditVersion, titleStamp)
        )
        do {
            try note.rename(
                to: title,
                version: titleStamp,
                editedAt: editedAt,
                meaningfulEditVersion: meaningfulEditStamp
            )
        }
        catch { throw PersistenceError.domainInvariant }
        try StoredDomainMapping.update(stored, from: note)
        try enqueue(.note, id: id.stringValue, sequence: meaningfulEditStamp.logicalCounter, in: context)
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
        let metadata = try workspaceMetadata(in: context)
        let stamp = try nextStamp(metadata)
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
        let meaningfulEditStamp = try nextStamp(
            metadata,
            observing: max(note.lastMeaningfulEditVersion, stamp)
        )
        do { try note.recordMeaningfulEdit(at: createdAt, version: meaningfulEditStamp) }
        catch { throw PersistenceError.domainInvariant }
        try StoredDomainMapping.update(storedNote, from: note)
        context.insert(try StoredDomainMapping.storedTask(from: task))
        try enqueue(.task, id: id.stringValue, sequence: stamp.logicalCounter, in: context)
        try enqueue(.note, id: noteID.stringValue, sequence: meaningfulEditStamp.logicalCounter, in: context)
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
        return try mappedUniqueTasks(noteID: noteID, in: readContext())
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
        return try mutateTask(id: id, allowDeleted: true) { task, stamp in
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
        let meaningfulEditStamp = try nextStamp(
            metadata,
            observing: max(owner.lastMeaningfulEditVersion, stamp)
        )
        do { try owner.recordMeaningfulEdit(at: now(), version: meaningfulEditStamp) }
        catch { throw PersistenceError.domainInvariant }
        try StoredDomainMapping.update(ownerStored, from: owner)
        try StoredDomainMapping.update(stored, from: task)
        try enqueue(.task, id: id.stringValue, sequence: stamp.logicalCounter, in: context)
        try enqueue(
            .note,
            id: owner.id.stringValue,
            sequence: meaningfulEditStamp.logicalCounter,
            in: context
        )
        try saveMutation(context)
        return task
    }

    // MARK: Durable outbox and workspace state

    public func pendingMutations(includeSuperseded: Bool = false) throws -> [PendingMutationSnapshot] {
        let context = readContext()
        let rows = try context.fetch(FetchDescriptor<PendingMutation>())
        try Self.validatePendingMutationRows(rows, in: context)
        return try rows
            .filter { includeSuperseded || $0.supersededByMutationID == nil }
            .map(Self.snapshot)
            .sorted { ($0.sequence, $0.id.uuidString) < ($1.sequence, $1.id.uuidString) }
    }

    public func recordMutationAttempt(id: UUID, at date: Date) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw PersistenceError.domainInvariant
        }
        let context = mutationContext()
        let idString = id.uuidString.lowercased()
        let allRows = try context.fetch(FetchDescriptor<PendingMutation>())
        try Self.validatePendingMutationRows(allRows, in: context)
        let rows = allRows.filter { $0.mutationID == idString }
        guard rows.count == 1, let row = rows.first else {
            throw PersistenceError.missingPendingMutation(idString)
        }
        guard row.supersededByMutationID == nil else { throw PersistenceError.domainInvariant }
        guard row.attemptCount < Int64.max else { throw PersistenceError.counterOverflow }
        row.attemptCount += 1
        row.lastAttemptAt = date
        try save(context)
    }

    public func acknowledgeMutations(ids: Set<UUID>) throws {
        let context = mutationContext()
        let strings = Set(ids.map { $0.uuidString.lowercased() })
        let rows = try context.fetch(FetchDescriptor<PendingMutation>())
        try Self.validatePendingMutationRows(rows, in: context)
        var reconciledIDs = strings
        var changed = true
        while changed {
            changed = false
            for row in rows where row.supersededByMutationID.map(reconciledIDs.contains) == true {
                if reconciledIDs.insert(row.mutationID).inserted { changed = true }
            }
        }
        for row in rows where reconciledIDs.contains(row.mutationID) {
            context.delete(row)
        }
        try save(context)
    }

    public func workspaceSnapshot() throws -> WorkspaceSnapshot {
        let metadata = try workspaceMetadata(in: readContext())
        let replica = try Self.validatedReplica(in: metadata)
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

    public func quarantine(
        recordKind: QuarantinedRecordKind,
        opaqueRecordID: String,
        category: QuarantineCategory,
        recordSchemaVersion: Int?,
        at date: Date
    ) throws {
        guard Self.isContentFreeQuarantineIdentifier(opaqueRecordID, kind: recordKind),
              recordSchemaVersion == nil || recordSchemaVersion! > 0,
              date.timeIntervalSinceReferenceDate.isFinite else {
            throw PersistenceError.invalidQuarantineMetadata
        }
        let context = mutationContext()
        context.insert(QuarantinedRecord(
            recordKind: recordKind.rawValue,
            opaqueRecordID: opaqueRecordID,
            errorCategory: category.rawValue,
            recordSchemaVersion: recordSchemaVersion,
            quarantinedAt: date
        ))
        try save(context)
    }

    public func quarantinedRecords() throws -> [QuarantinedRecordSnapshot] {
        var identifiers: Set<UUID> = []
        return try readContext().fetch(FetchDescriptor<QuarantinedRecord>()).map { row in
            guard let id = UUID(uuidString: row.quarantineID),
                  row.quarantineID == id.uuidString.lowercased(),
                  identifiers.insert(id).inserted,
                  let kind = QuarantinedRecordKind(rawValue: row.recordKind),
                  let category = QuarantineCategory(rawValue: row.errorCategory),
                  Self.isContentFreeQuarantineIdentifier(row.opaqueRecordID, kind: kind),
                  row.recordSchemaVersion == nil || row.recordSchemaVersion! > 0,
                  row.quarantinedAt.timeIntervalSinceReferenceDate.isFinite else {
                throw PersistenceError.malformedRepresentation(
                    .note, "invalid", field: "quarantineMetadata"
                )
            }
            return QuarantinedRecordSnapshot(
                id: id,
                recordKind: kind,
                opaqueRecordID: row.opaqueRecordID,
                category: category,
                recordSchemaVersion: row.recordSchemaVersion,
                quarantinedAt: row.quarantinedAt
            )
        }.sorted { $0.quarantinedAt < $1.quarantinedAt }
    }

    // MARK: Internal transaction machinery

    func readContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    func mutationContext() -> ModelContext { readContext() }

    private func saveMutation(_ context: ModelContext) throws {
        do { try save(context) }
        catch { throw PersistenceError.atomicMutationFailure }
    }

    func save(_ context: ModelContext) throws {
        if failNextSave {
            failNextSave = false
            throw PersistenceError.saveFailure
        }
        do { try context.save() }
        catch { throw PersistenceError.saveFailure }
    }

    func workspaceMetadata(in context: ModelContext) throws -> WorkspaceMetadata {
        let rows = try context.fetch(FetchDescriptor<WorkspaceMetadata>())
        guard rows.count == 1, let metadata = rows.first else {
            throw PersistenceError.workspaceMismatch
        }
        try Self.validateWorkspaceMetadata(metadata, expectedWorkspace: workspace, in: context)
        return metadata
    }

    private nonisolated static func validateWorkspaceMetadata(
        _ metadata: WorkspaceMetadata,
        expectedWorkspace workspace: WorkspaceIdentity,
        in context: ModelContext
    ) throws {
        guard metadata.singletonKey == "workspace",
              metadata.workspaceKindRawValue == workspace.kindRawValue,
              metadata.opaqueWorkspaceID == workspace.opaqueID,
              metadata.sharedSchemaVersion == 2,
              metadata.logicalCounter >= 0 else {
            throw PersistenceError.workspaceMismatch
        }
        _ = try validatedReplica(in: metadata)
        switch workspace {
        case .localOnly:
            guard metadata.opaqueWorkspaceID == nil else { throw PersistenceError.workspaceMismatch }
        case let .account(id):
            guard metadata.opaqueWorkspaceID == id.uuidString.lowercased() else {
                throw PersistenceError.workspaceMismatch
            }
        }
        try validateCounterFloor(metadata, in: context)
        let pending = try context.fetch(FetchDescriptor<PendingMutation>())
        try validatePendingMutationRows(pending, in: context)
    }

    private nonisolated static func validateCounterFloor(
        _ metadata: WorkspaceMetadata,
        in context: ModelContext
    ) throws {
        var maximum: Int64 = 0
        for note in try context.fetch(FetchDescriptor<StoredNote>()) {
            let counters = [
                note.titleVersionCounter,
                note.lifecycleVersionCounter,
                note.lastMeaningfulEditVersionCounter
            ]
            guard counters.allSatisfy({ $0 >= 0 }) else { throw PersistenceError.workspaceMismatch }
            maximum = max(maximum, counters.max() ?? 0)
        }
        for task in try context.fetch(FetchDescriptor<StoredTask>()) {
            let counters = [
                task.textVersionCounter,
                task.completionVersionCounter,
                task.orderVersionCounter,
                task.lifecycleVersionCounter
            ]
            guard counters.allSatisfy({ $0 >= 0 }) else { throw PersistenceError.workspaceMismatch }
            maximum = max(maximum, counters.max() ?? 0)
        }
        for mutation in try context.fetch(FetchDescriptor<PendingMutation>()) {
            guard mutation.sequence >= 0 else { throw PersistenceError.workspaceMismatch }
            maximum = max(maximum, mutation.sequence)
        }
        guard metadata.logicalCounter >= maximum else { throw PersistenceError.workspaceMismatch }
    }

    private nonisolated static func validatedReplica(in metadata: WorkspaceMetadata) throws -> ReplicaID {
        guard let replica = ReplicaID(string: metadata.replicaID),
              metadata.replicaID == replica.stringValue else {
            throw PersistenceError.workspaceMismatch
        }
        return replica
    }

    private func nextStamp(
        _ metadata: WorkspaceMetadata,
        observing stamp: VersionStamp? = nil
    ) throws -> VersionStamp {
        let replica = try Self.validatedReplica(in: metadata)
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
        for row in active {
            try supersedeActiveMutation(row, with: newID, in: context)
        }
        context.insert(PendingMutation(
            mutationID: newID,
            targetKindRawValue: kindRaw,
            targetStableID: id,
            sequence: Int64(sequence),
            createdAt: now()
        ))
    }

    /// Replaces one active mutation while preserving the acknowledgement chain
    /// of older in-flight mutations. An unsent active row may already be the
    /// successor of an attempted ancestor; deleting it without retargeting that
    /// ancestor leaves a dangling supersession link.
    func supersedeActiveMutation(
        _ row: PendingMutation,
        with newMutationID: String,
        in context: ModelContext
    ) throws {
        if row.attemptCount == 0 {
            let removedID = row.mutationID
            let predecessors = try context.fetch(FetchDescriptor<PendingMutation>(
                predicate: #Predicate { $0.supersededByMutationID == removedID }
            ))
            for predecessor in predecessors {
                predecessor.supersededByMutationID = newMutationID
            }
            context.delete(row)
        } else {
            row.supersededByMutationID = newMutationID
        }
    }

    private static func snapshot(_ row: PendingMutation) throws -> PendingMutationSnapshot {
        guard let id = UUID(uuidString: row.mutationID),
              row.mutationID == id.uuidString.lowercased(),
              let kind = PersistedEntityKind(rawValue: row.targetKindRawValue),
              isCanonicalTargetID(row.targetStableID, kind: kind),
              row.sequence > 0, row.attemptCount >= 0,
              row.createdAt.timeIntervalSinceReferenceDate.isFinite,
              row.lastAttemptAt?.timeIntervalSinceReferenceDate.isFinite != false,
              (row.attemptCount == 0) == (row.lastAttemptAt == nil),
              row.supersededByMutationID == nil || UUID(uuidString: row.supersededByMutationID!) != nil else {
            throw PersistenceError.malformedRepresentation(.task, "invalid", field: "pendingMutation")
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

    private static func validatePendingMutationRows(
        _ rows: [PendingMutation],
        in context: ModelContext
    ) throws {
        let noteIDs = Set(try context.fetch(FetchDescriptor<StoredNote>()).map(\.stableID))
        let taskIDs = Set(try context.fetch(FetchDescriptor<StoredTask>()).map(\.stableID))
        var byID: [String: PendingMutation] = [:]
        var activeTargets: Set<String> = []
        for row in rows {
            let snapshot = try snapshot(row)
            let targetExists = switch snapshot.targetKind {
            case .note: noteIDs.contains(snapshot.targetStableID)
            case .task: taskIDs.contains(snapshot.targetStableID)
            }
            guard targetExists else {
                throw PersistenceError.malformedRepresentation(
                    snapshot.targetKind, "invalid", field: "pendingMutationTarget"
                )
            }
            guard byID.updateValue(row, forKey: row.mutationID) == nil else {
                throw PersistenceError.malformedRepresentation(.task, "invalid", field: "pendingMutationID")
            }
            if row.supersededByMutationID == nil {
                let target = row.targetKindRawValue + ":" + row.targetStableID
                guard activeTargets.insert(target).inserted else {
                    throw PersistenceError.malformedRepresentation(.task, "invalid", field: "activeMutation")
                }
            }
        }
        for row in rows {
            guard let successorID = row.supersededByMutationID else { continue }
            guard successorID != row.mutationID,
                  let successor = byID[successorID],
                  successor.targetKindRawValue == row.targetKindRawValue,
                  successor.targetStableID == row.targetStableID,
                  successor.sequence > row.sequence else {
                throw PersistenceError.malformedRepresentation(.task, "invalid", field: "supersession")
            }
        }
    }

    private static func isCanonicalTargetID(_ value: String, kind: PersistedEntityKind) -> Bool {
        switch kind {
        case .note:
            guard let id = NoteID(string: value) else { return false }
            return value == id.stringValue
        case .task:
            guard let id = TaskID(string: value) else { return false }
            return value == id.stringValue
        }
    }

    private static func isContentFreeQuarantineIdentifier(
        _ value: String,
        kind: QuarantinedRecordKind
    ) -> Bool {
        switch kind {
        case .note:
            guard let id = NoteID(recordName: value) else { return false }
            return value == id.recordName
        case .task:
            guard let id = TaskID(recordName: value) else { return false }
            return value == id.recordName
        case .schemaMarker, .unknown:
            let prefix = kind == .schemaMarker ? "schema-" : "unknown-"
            guard value.hasPrefix(prefix),
                  let id = UUID(uuidString: String(value.dropFirst(prefix.count))) else { return false }
            return value == prefix + id.uuidString.lowercased()
        }
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

    private func mappedUniqueNotes(in context: ModelContext) throws -> [Note] {
        var identifiers: Set<NoteID> = []
        return try context.fetch(FetchDescriptor<StoredNote>()).map { stored in
            let note = try StoredDomainMapping.note(from: stored)
            guard identifiers.insert(note.id).inserted else {
                throw PersistenceError.duplicateID(.note, note.id.stringValue)
            }
            return note
        }
    }

    private func mappedUniqueTasks(noteID: NoteID, in context: ModelContext) throws -> [Task] {
        var identifiers: Set<TaskID> = []
        return try storedTasks(noteID: noteID, in: context).map { stored in
            let task = try StoredDomainMapping.task(from: stored, expectedNoteID: noteID)
            guard identifiers.insert(task.id).inserted else {
                throw PersistenceError.duplicateID(.task, task.id.stringValue)
            }
            return task
        }
    }

    private func maxVersion(in task: Task) -> VersionStamp {
        [task.textVersion, task.completionVersion, task.orderVersion, task.lifecycleVersion].max()!
    }

    /// Deterministic save interruption used only by `@testable` persistence tests.
    func failNextSaveForTesting() { failNextSave = true }
}
