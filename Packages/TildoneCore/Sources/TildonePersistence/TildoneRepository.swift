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
            let workspaceMetadata: WorkspaceMetadata
            if metadata.isEmpty {
                let created = WorkspaceMetadata(
                    workspaceKindRawValue: descriptor.workspace.kindRawValue,
                    opaqueWorkspaceID: descriptor.workspace.opaqueID,
                    replicaID: replicaID.stringValue,
                    sharedSchemaVersion: Self.currentSharedSchemaVersion
                )
                context.insert(created)
                workspaceMetadata = created
            } else {
                guard metadata.count == 1 else { throw PersistenceError.workspaceMismatch }
                workspaceMetadata = metadata[0]
                if metadata[0].sharedSchemaVersion < Self.currentSharedSchemaVersion {
                    guard (1..<Self.currentSharedSchemaVersion).contains(
                        metadata[0].sharedSchemaVersion
                    ) else { throw PersistenceError.workspaceMismatch }
                    metadata[0].sharedSchemaVersion = Self.currentSharedSchemaVersion
                }
                let migrations = try context.fetch(FetchDescriptor<LegacyMigrationState>())
                guard migrations.count <= 1 else { throw PersistenceError.workspaceMismatch }
                if let migration = migrations.first,
                   migration.destinationSchemaVersion < Self.currentSharedSchemaVersion {
                    migration.destinationSchemaVersion = Self.currentSharedSchemaVersion
                }
            }
            try Self.validateWorkspaceMetadata(
                workspaceMetadata,
                expectedWorkspace: descriptor.workspace,
                in: context
            )
            try Self.migrateLegacyTaskSchemas(
                metadata: workspaceMetadata,
                createdAt: now(),
                in: context
            )
            try context.save()
            try Self.validateWorkspaceMetadata(
                workspaceMetadata,
                expectedWorkspace: descriptor.workspace,
                in: context
            )
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
        let schema = Schema(versionedSchema: TildoneSchemaV4.self)
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

    public func createNote(
        id: NoteID,
        createdAt: Date,
        title: String?,
        color: NoteColor = .yellow
    ) throws -> Note {
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
            color: color,
            colorVersion: stamp,
            lifecycleVersion: stamp,
            lastMeaningfulEditAt: createdAt,
            lastMeaningfulEditVersion: stamp
        )
        context.insert(try StoredDomainMapping.storedNote(from: note))
        context.insert(try StoredDomainMapping.storedNoteColor(from: note))
        try enqueue(.note, id: id.stringValue, sequence: stamp.logicalCounter, in: context)
        try saveMutation(context)
        return note
    }

    public func note(id: NoteID, includingDeleted: Bool = false) throws -> Note {
        let context = readContext()
        guard let stored = try storedNote(id: id, in: context) else {
            throw PersistenceError.missing(.note, id.stringValue)
        }
        let note = try mappedNote(from: stored, in: context)
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
        var note = try mappedNote(from: stored, in: context)
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

    public func setNoteColor(id: NoteID, color: NoteColor) throws -> Note {
        let context = mutationContext()
        let stored = try requireStoredNote(id: id, in: context)
        var note = try mappedNote(from: stored, in: context)
        guard note.lifecycle == .active else { throw PersistenceError.domainInvariant }
        if note.color == color, try storedNoteColor(noteID: id, in: context) != nil {
            return note
        }
        let metadata = try workspaceMetadata(in: context)
        let stamp = try nextStamp(metadata, observing: maxVersion(in: note))
        do { try note.setColor(color, version: stamp) }
        catch { throw PersistenceError.domainInvariant }
        let colorRow = try storedNoteColor(noteID: id, in: context)
        if let colorRow {
            try StoredDomainMapping.update(colorRow, from: note)
        } else {
            context.insert(try StoredDomainMapping.storedNoteColor(from: note))
        }
        stored.recordSchemaVersion = Note.currentSchemaVersion
        try enqueue(.note, id: id.stringValue, sequence: stamp.logicalCounter, in: context)
        try saveMutation(context)
        return note
    }

    /// Completes the additive V3 migration. Missing sidecars receive the
    /// caller's Mac-local value when available, otherwise the previous global
    /// default. Every migrated note and its outbox evidence are saved in the
    /// same transaction, making interruption safe and retries idempotent.
    public func migrateMissingNoteColors(
        colorsByNoteID: [NoteID: NoteColor],
        defaultColor: NoteColor = .yellow,
        authority: NoteColorMigrationAuthority = .platformDefault
    ) throws {
        let context = mutationContext()
        let notes = try context.fetch(FetchDescriptor<StoredNote>())
        let metadata = try workspaceMetadata(in: context)
        var storedColorsByNoteID: [String: StoredNoteColor] = [:]
        for color in try context.fetch(FetchDescriptor<StoredNoteColor>()) {
            guard storedColorsByNoteID.updateValue(color, forKey: color.noteStableID) == nil else {
                throw PersistenceError.duplicateID(.note, color.noteStableID)
            }
        }
        for stored in notes {
            guard let id = NoteID(string: stored.stableID) else {
                throw PersistenceError.malformedRepresentation(
                    .note, "invalid", field: "stableID"
                )
            }
            let storedColor = storedColorsByNoteID[id.stringValue]
            var note = try StoredDomainMapping.note(from: stored, color: storedColor)
            if storedColor != nil {
                // A platform-default migration may arrive before this Mac
                // reopens its legacy preferences. Permit only the stronger
                // legacy-Mac migration to replace that synthesized value.
                // Ordinary V2 colors and equal/stronger migration values are
                // already authoritative and must remain untouched.
                guard let existingAuthority = NoteColorMigrationAuthority.authority(
                    for: note.colorVersion.replicaID
                ), existingAuthority.rawValue < authority.rawValue else { continue }
            }
            let stamp = try nextColorMigrationStamp(
                metadata,
                observing: maxVersion(in: note),
                authority: authority
            )
            do {
                try note.setColor(colorsByNoteID[id] ?? defaultColor, version: stamp)
            } catch {
                throw PersistenceError.domainInvariant
            }
            stored.recordSchemaVersion = Note.currentSchemaVersion
            if let storedColor {
                try StoredDomainMapping.update(storedColor, from: note)
            } else {
                let inserted = try StoredDomainMapping.storedNoteColor(from: note)
                context.insert(inserted)
                storedColorsByNoteID[id.stringValue] = inserted
            }
            try enqueue(
                .note,
                id: id.stringValue,
                sequence: stamp.logicalCounter,
                in: context
            )
        }
        try saveMutation(context)
    }

    public func deleteNote(id: NoteID) throws {
        let context = mutationContext()
        let stored = try requireStoredNote(id: id, in: context)
        var note = try mappedNote(from: stored, in: context)
        guard note.lifecycle == .active else { return }
        let metadata = try workspaceMetadata(in: context)
        let noteStamp = try nextStamp(metadata, observing: note.lifecycleVersion)
        do { try note.delete(version: noteStamp) }
        catch { throw PersistenceError.domainInvariant }
        try StoredDomainMapping.update(stored, from: note)
        try enqueue(.note, id: id.stringValue, sequence: noteStamp.logicalCounter, in: context)

        for storedTask in try storedTasks(noteID: id, in: context) {
            var task = try mappedTask(from: storedTask, expectedNoteID: id, in: context)
            guard task.lifecycle == .active else { continue }
            let taskStamp = try nextStamp(metadata, observing: task.lifecycleVersion)
            do { try task.delete(version: taskStamp) }
            catch { throw PersistenceError.domainInvariant }
            try promoteTaskToCurrentSchema(&task, version: taskStamp)
            try StoredDomainMapping.update(storedTask, from: task)
            try upsertTaskIndentation(for: task, in: context)
            try enqueue(.task, id: task.id.stringValue, sequence: taskStamp.logicalCounter, in: context)
        }
        try saveMutation(context)
    }

    public func restoreNote(id: NoteID) throws -> Note {
        let context = mutationContext()
        let stored = try requireStoredNote(id: id, in: context)
        var note = try mappedNote(from: stored, in: context)
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
        orderToken: OrderToken,
        indentLevel: Int = 0
    ) throws -> Task {
        guard indentLevel >= 0 else {
            throw PersistenceError.domainInvariant
        }
        let context = mutationContext()
        guard try storedTask(id: id, in: context) == nil else {
            throw PersistenceError.duplicateID(.task, id.stringValue)
        }
        let storedNote = try requireStoredNote(id: noteID, in: context)
        var note = try mappedNote(from: storedNote, in: context)
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
            indentLevel: indentLevel,
            indentVersion: stamp,
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
        context.insert(try StoredDomainMapping.storedTaskIndentation(from: task))
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
        let task = try mappedTask(from: stored, in: context)
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

    public func setTaskIndentLevel(id: TaskID, indentLevel: Int) throws -> Task {
        try mutateTask(id: id) { task, stamp in
            try task.setIndentLevel(indentLevel, version: stamp)
        }
    }

    /// Applies a hierarchy edit in one transaction. This prevents a subtree
    /// from being durably visible in a partially indented or partially moved
    /// state and avoids one SQLite save per descendant.
    public func applyTaskStructureUpdates(
        in noteID: NoteID,
        updates: [TaskStructureUpdate]
    ) throws -> [Task] {
        guard !updates.isEmpty else { return try orderedTasks(in: noteID) }
        guard Set(updates.map(\.id)).count == updates.count else {
            throw PersistenceError.domainInvariant
        }

        let context = mutationContext()
        let ownerStored = try requireStoredNote(id: noteID, in: context)
        var owner = try mappedNote(from: ownerStored, in: context)
        guard owner.lifecycle == .active else { throw PersistenceError.domainInvariant }
        let metadata = try workspaceMetadata(in: context)
        var changedTasks: [Task] = []
        changedTasks.reserveCapacity(updates.count)

        for update in updates {
            let stored = try requireStoredTask(id: update.id, in: context)
            var task = try mappedTask(from: stored, expectedNoteID: noteID, in: context)
            guard task.lifecycle == .active else { throw PersistenceError.domainInvariant }
            let changesOrder = update.orderToken.map { $0 != task.orderToken } ?? false
            let changesIndent = update.indentLevel.map { $0 != task.indentLevel } ?? false
            let changesCompletion = update.completion.map { $0 != task.completion } ?? false
            guard changesOrder || changesIndent || changesCompletion else { continue }

            let stamp = try nextStamp(metadata, observing: maxVersion(in: task))
            do {
                if let orderToken = update.orderToken, changesOrder {
                    try task.move(to: orderToken, version: stamp)
                }
                if let indentLevel = update.indentLevel, changesIndent {
                    try task.setIndentLevel(indentLevel, version: stamp)
                }
                if let completion = update.completion, changesCompletion {
                    try task.setCompletion(completion, version: stamp)
                }
            } catch {
                throw PersistenceError.domainInvariant
            }
            try promoteTaskToCurrentSchema(&task, version: stamp)
            try StoredDomainMapping.update(stored, from: task)
            try upsertTaskIndentation(for: task, in: context)
            try enqueue(.task, id: task.id.stringValue, sequence: stamp.logicalCounter, in: context)
            changedTasks.append(task)
        }

        if !changedTasks.isEmpty {
            let meaningfulEditStamp = try nextStamp(
                metadata,
                observing: max(
                    owner.lastMeaningfulEditVersion,
                    changedTasks.map { maxVersion(in: $0) }.max()!
                )
            )
            do { try owner.recordMeaningfulEdit(at: now(), version: meaningfulEditStamp) }
            catch { throw PersistenceError.domainInvariant }
            try StoredDomainMapping.update(ownerStored, from: owner)
            try enqueue(
                .note,
                id: noteID.stringValue,
                sequence: meaningfulEditStamp.logicalCounter,
                in: context
            )
            try saveMutation(context)
        }
        return changedTasks
    }

    /// Deletes abandoned empty placeholders and inserts their replacement in
    /// one transaction. The caller supplies the order token it already used for
    /// its optimistic presentation snapshot.
    public func replaceEmptyTasksAndAddTask(
        deleting taskIDs: Set<TaskID>,
        id: TaskID,
        to noteID: NoteID,
        createdAt: Date,
        text: String,
        orderToken: OrderToken,
        indentLevel: Int
    ) throws -> Task {
        guard indentLevel >= 0, !taskIDs.contains(id) else {
            throw PersistenceError.domainInvariant
        }
        let context = mutationContext()
        guard try storedTask(id: id, in: context) == nil else {
            throw PersistenceError.duplicateID(.task, id.stringValue)
        }
        let ownerStored = try requireStoredNote(id: noteID, in: context)
        var owner = try mappedNote(from: ownerStored, in: context)
        guard owner.lifecycle == .active else { throw PersistenceError.domainInvariant }
        let metadata = try workspaceMetadata(in: context)

        for taskID in taskIDs.sorted() {
            let stored = try requireStoredTask(id: taskID, in: context)
            var task = try mappedTask(from: stored, expectedNoteID: noteID, in: context)
            guard task.lifecycle == .active, task.text.isEmpty else {
                throw PersistenceError.domainInvariant
            }
            let stamp = try nextStamp(metadata, observing: maxVersion(in: task))
            do { try task.delete(version: stamp) }
            catch { throw PersistenceError.domainInvariant }
            try promoteTaskToCurrentSchema(&task, version: stamp)
            try StoredDomainMapping.update(stored, from: task)
            try upsertTaskIndentation(for: task, in: context)
            try enqueue(.task, id: task.id.stringValue, sequence: stamp.logicalCounter, in: context)
        }

        let taskStamp = try nextStamp(metadata)
        let task = Task(
            id: id,
            noteID: noteID,
            createdAt: createdAt,
            text: text,
            textVersion: taskStamp,
            completionVersion: taskStamp,
            orderToken: orderToken,
            orderVersion: taskStamp,
            indentLevel: indentLevel,
            indentVersion: taskStamp,
            lifecycleVersion: taskStamp
        )
        context.insert(try StoredDomainMapping.storedTask(from: task))
        context.insert(try StoredDomainMapping.storedTaskIndentation(from: task))
        try enqueue(.task, id: id.stringValue, sequence: taskStamp.logicalCounter, in: context)

        let meaningfulEditStamp = try nextStamp(
            metadata,
            observing: max(owner.lastMeaningfulEditVersion, taskStamp)
        )
        do { try owner.recordMeaningfulEdit(at: createdAt, version: meaningfulEditStamp) }
        catch { throw PersistenceError.domainInvariant }
        try StoredDomainMapping.update(ownerStored, from: owner)
        try enqueue(
            .note,
            id: noteID.stringValue,
            sequence: meaningfulEditStamp.logicalCounter,
            in: context
        )
        try saveMutation(context)
        return task
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
        var task = try mappedTask(from: stored, in: context)
        let ownerStored = try requireStoredNote(id: task.noteID, in: context)
        var owner = try mappedNote(from: ownerStored, in: context)
        guard owner.lifecycle == .active, allowDeleted || task.lifecycle == .active else {
            throw PersistenceError.domainInvariant
        }
        let metadata = try workspaceMetadata(in: context)
        let stamp = try nextStamp(metadata, observing: maxVersion(in: task))
        do { try mutation(&task, stamp) }
        catch { throw PersistenceError.domainInvariant }
        try promoteTaskToCurrentSchema(&task, version: stamp)
        let meaningfulEditStamp = try nextStamp(
            metadata,
            observing: max(owner.lastMeaningfulEditVersion, stamp)
        )
        do { try owner.recordMeaningfulEdit(at: now(), version: meaningfulEditStamp) }
        catch { throw PersistenceError.domainInvariant }
        try StoredDomainMapping.update(ownerStored, from: owner)
        try StoredDomainMapping.update(stored, from: task)
        try upsertTaskIndentation(for: task, in: context)
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

    /// Atomically snapshots and marks the current active mutation as in flight.
    /// Local edits may replace an unattempted outbox row, so selecting the row,
    /// reading its domain value, and incrementing its attempt count must not be
    /// separated by actor reentrancy.
    public func preparePendingMutation(
        targetKind: PersistedEntityKind,
        targetStableID: String,
        at date: Date
    ) throws -> PreparedPendingMutation? {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw PersistenceError.domainInvariant
        }
        let context = mutationContext()
        let rows = try context.fetch(FetchDescriptor<PendingMutation>())
        try Self.validatePendingMutationRows(rows, in: context)
        guard let row = rows.first(where: {
            $0.targetKindRawValue == targetKind.rawValue
                && $0.targetStableID == targetStableID
                && $0.supersededByMutationID == nil
        }) else {
            return nil
        }
        let mutation = try Self.snapshot(row)
        let payload: PendingMutationPayload
        switch targetKind {
        case .note:
            guard let id = NoteID(string: targetStableID) else {
                throw PersistenceError.malformedRepresentation(
                    .note, "invalid", field: "pendingMutationTarget"
                )
            }
            payload = .note(try mappedNote(from: requireStoredNote(id: id, in: context), in: context))
        case .task:
            guard let id = TaskID(string: targetStableID) else {
                throw PersistenceError.malformedRepresentation(
                    .task, "invalid", field: "pendingMutationTarget"
                )
            }
            payload = .task(try mappedTask(from: requireStoredTask(id: id, in: context), in: context))
        }
        guard row.attemptCount < Int64.max else { throw PersistenceError.counterOverflow }
        row.attemptCount += 1
        row.lastAttemptAt = date
        try save(context)
        return PreparedPendingMutation(mutationID: mutation.id, payload: payload)
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
              metadata.sharedSchemaVersion == currentSharedSchemaVersion,
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
        let noteIDs = Set(try context.fetch(FetchDescriptor<StoredNote>()).map(\.stableID))
        var coloredNoteIDs: Set<String> = []
        for color in try context.fetch(FetchDescriptor<StoredNoteColor>()) {
            guard noteIDs.contains(color.noteStableID),
                  coloredNoteIDs.insert(color.noteStableID).inserted,
                  NoteColor(rawValue: color.colorRawValue) != nil,
                  color.colorVersionCounter >= 0,
                  let replica = ReplicaID(string: color.colorVersionReplicaID),
                  replica.stringValue == color.colorVersionReplicaID else {
                throw PersistenceError.workspaceMismatch
            }
            maximum = max(maximum, color.colorVersionCounter)
        }
        for task in try context.fetch(FetchDescriptor<StoredTask>()) {
            let counters = [
                task.textVersionCounter,
                task.completionVersionCounter,
                task.orderVersionCounter,
                task.lifecycleVersionCounter
            ]
            guard counters.allSatisfy({ $0 >= 0 }) else {
                throw PersistenceError.workspaceMismatch
            }
            maximum = max(maximum, counters.max() ?? 0)
        }
        for indentation in try context.fetch(FetchDescriptor<StoredTaskIndentation>()) {
            guard indentation.level >= 0, indentation.versionCounter >= 0 else {
                throw PersistenceError.workspaceMismatch
            }
            maximum = max(maximum, indentation.versionCounter)
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

    private func nextColorMigrationStamp(
        _ metadata: WorkspaceMetadata,
        observing stamp: VersionStamp,
        authority: NoteColorMigrationAuthority
    ) throws -> VersionStamp {
        let sourceReplica = try Self.validatedReplica(in: metadata)
        let ordinary = try nextStamp(metadata, observing: stamp)
        return VersionStamp(
            logicalCounter: ordinary.logicalCounter,
            replicaID: authority.migrationReplicaID(sourceReplicaID: sourceReplica)
        )
    }

    private func enqueue(
        _ kind: PersistedEntityKind,
        id: String,
        sequence: UInt64,
        in context: ModelContext
    ) throws {
        try Self.enqueue(kind, id: id, sequence: sequence, createdAt: now(), in: context)
    }

    private nonisolated static func enqueue(
        _ kind: PersistedEntityKind,
        id: String,
        sequence: UInt64,
        createdAt: Date,
        in context: ModelContext
    ) throws {
        guard sequence <= UInt64(Int64.max) else { throw PersistenceError.counterOverflow }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PersistenceError.domainInvariant
        }
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
            createdAt: createdAt
        ))
    }

    /// Replaces one active mutation while preserving the acknowledgement chain
    /// of older in-flight mutations. An unsent active row may already be the
    /// successor of an attempted ancestor; deleting it without retargeting that
    /// ancestor leaves a dangling supersession link.
    nonisolated static func supersedeActiveMutation(
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
        case .client:
            let prefix = "client-"
            guard value.hasPrefix(prefix),
                  let id = UUID(uuidString: String(value.dropFirst(prefix.count))) else { return false }
            return value == prefix + id.uuidString.lowercased()
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

    func storedNoteColor(noteID: NoteID, in context: ModelContext) throws -> StoredNoteColor? {
        let value = noteID.stringValue
        let rows = try context.fetch(FetchDescriptor<StoredNoteColor>(
            predicate: #Predicate { $0.noteStableID == value }
        ))
        guard rows.count <= 1 else { throw PersistenceError.duplicateID(.note, value) }
        return rows.first
    }

    func mappedNote(from stored: StoredNote, in context: ModelContext) throws -> Note {
        guard let id = NoteID(string: stored.stableID) else {
            throw PersistenceError.malformedRepresentation(.note, "invalid", field: "stableID")
        }
        return try StoredDomainMapping.note(
            from: stored,
            color: storedNoteColor(noteID: id, in: context)
        )
    }

    private func mappedUniqueNotes(in context: ModelContext) throws -> [Note] {
        var identifiers: Set<NoteID> = []
        return try context.fetch(FetchDescriptor<StoredNote>()).map { stored in
            let note = try mappedNote(from: stored, in: context)
            guard identifiers.insert(note.id).inserted else {
                throw PersistenceError.duplicateID(.note, note.id.stringValue)
            }
            return note
        }
    }

    private func mappedUniqueTasks(noteID: NoteID, in context: ModelContext) throws -> [Task] {
        var identifiers: Set<TaskID> = []
        return try storedTasks(noteID: noteID, in: context).map { stored in
            let task = try mappedTask(from: stored, expectedNoteID: noteID, in: context)
            guard identifiers.insert(task.id).inserted else {
                throw PersistenceError.duplicateID(.task, task.id.stringValue)
            }
            return task
        }
    }

    func maxVersion(in task: Task) -> VersionStamp {
        [
            task.textVersion, task.completionVersion, task.orderVersion, task.indentVersion,
            task.lifecycleVersion
        ].max()!
    }

    func mappedTask(
        from stored: StoredTask,
        expectedNoteID: NoteID? = nil,
        in context: ModelContext
    ) throws -> Task {
        try StoredDomainMapping.task(
            from: stored,
            indentation: try taskIndentation(for: stored.stableID, in: context),
            expectedNoteID: expectedNoteID
        )
    }

    func taskIndentation(for stableID: String, in context: ModelContext) throws -> StoredTaskIndentation? {
        let rows = try context.fetch(FetchDescriptor<StoredTaskIndentation>(
            predicate: #Predicate { $0.taskStableID == stableID }
        ))
        guard rows.count <= 1 else { throw PersistenceError.duplicateID(.task, stableID) }
        return rows.first
    }

    func requireTaskIndentation(for id: TaskID, in context: ModelContext) throws -> StoredTaskIndentation {
        guard let indentation = try taskIndentation(for: id.stringValue, in: context) else {
            throw PersistenceError.missing(.task, id.stringValue)
        }
        return indentation
    }

    func promoteTaskToCurrentSchema(_ task: inout Task, version: VersionStamp) throws {
        guard task.schemaVersion < Task.currentSchemaVersion else { return }
        if version > task.indentVersion {
            do { try task.setIndentLevel(task.indentLevel, version: version) }
            catch { throw PersistenceError.domainInvariant }
        }
        task = Self.taskByPromotingToCurrentSchema(task)
    }

    private nonisolated static func taskByPromotingToCurrentSchema(_ task: Task) -> Task {
        Task(
            id: task.id,
            noteID: task.noteID,
            createdAt: task.createdAt,
            text: task.text,
            textVersion: task.textVersion,
            completion: task.completion,
            completionVersion: task.completionVersion,
            orderToken: task.orderToken,
            orderVersion: task.orderVersion,
            indentLevel: task.indentLevel,
            indentVersion: task.indentVersion,
            lifecycle: task.lifecycle,
            lifecycleVersion: task.lifecycleVersion,
            schemaVersion: Task.currentSchemaVersion
        )
    }

    func upsertTaskIndentation(for task: Task, in context: ModelContext) throws {
        if let indentation = try taskIndentation(for: task.id.stringValue, in: context) {
            try StoredDomainMapping.update(indentation, from: task)
        } else {
            context.insert(try StoredDomainMapping.storedTaskIndentation(from: task))
        }
    }

    private nonisolated static func migrateLegacyTaskSchemas(
        metadata: WorkspaceMetadata,
        createdAt: Date,
        in context: ModelContext
    ) throws {
        let tasks = try context.fetch(FetchDescriptor<StoredTask>())
        var indentationsByTaskID: [String: StoredTaskIndentation] = [:]
        for indentation in try context.fetch(FetchDescriptor<StoredTaskIndentation>()) {
            guard indentationsByTaskID.updateValue(
                indentation,
                forKey: indentation.taskStableID
            ) == nil else {
                throw PersistenceError.duplicateID(.task, indentation.taskStableID)
            }
        }
        let replica = try validatedReplica(in: metadata)
        for stored in tasks {
            let indentation = indentationsByTaskID[stored.stableID]
            var task = try StoredDomainMapping.task(from: stored, indentation: indentation)
            guard task.schemaVersion < Task.currentSchemaVersion || indentation == nil else {
                continue
            }
            let maximum = [
                task.textVersion, task.completionVersion, task.orderVersion,
                task.indentVersion, task.lifecycleVersion
            ].max()!
            let current = max(UInt64(metadata.logicalCounter), maximum.logicalCounter)
            guard current < UInt64(Int64.max) else { throw PersistenceError.counterOverflow }
            let stamp = VersionStamp(logicalCounter: current + 1, replicaID: replica)
            metadata.logicalCounter = Int64(stamp.logicalCounter)
            if stamp > task.indentVersion {
                do { try task.setIndentLevel(task.indentLevel, version: stamp) }
                catch { throw PersistenceError.domainInvariant }
            }
            if task.schemaVersion < Task.currentSchemaVersion {
                task = taskByPromotingToCurrentSchema(task)
            }
            try StoredDomainMapping.update(stored, from: task)
            if let indentation {
                try StoredDomainMapping.update(indentation, from: task)
            } else {
                let inserted = try StoredDomainMapping.storedTaskIndentation(from: task)
                context.insert(inserted)
                indentationsByTaskID[stored.stableID] = inserted
            }
            try enqueue(
                .task,
                id: task.id.stringValue,
                sequence: stamp.logicalCounter,
                createdAt: createdAt,
                in: context
            )
        }
    }

    func maxVersion(in note: Note) -> VersionStamp {
        [
            note.titleVersion, note.colorVersion, note.lifecycleVersion,
            note.lastMeaningfulEditVersion
        ].max()!
    }

    /// Deterministic save interruption used only by `@testable` persistence tests.
    func failNextSaveForTesting() { failNextSave = true }
}
