//
//  LegacyStoreReader.swift
//  Tildone
//
//  Created by OpenAI Codex on 7/13/26.
//
import Foundation
import SwiftData
import TildonePersistence

enum LegacyStoreReaderError: Error, Equatable {
    case openFailure
    case incompatibleSchema
    case invalidPersistentIdentifier
    case invalidDate
    case invalidRelationship
}

struct LegacyTaskSnapshot: Hashable, Sendable {
    let legacyKey: String
    let ownerLegacyKey: String
    let createdAt: Date
    let text: String
    let originalIndex: Int?
    let normalizedLegacyIndex: Int
    let completedAt: Date?
    let visibleOrder: Int
    let classification: LegacyMigrationClassification
}

struct LegacyNoteSnapshot: Hashable, Sendable {
    let legacyKey: String
    let createdAt: Date
    let title: String?
    let lastMeaningfulEditAt: Date
    let classification: LegacyMigrationClassification
    let tasks: [LegacyTaskSnapshot]
}

@MainActor
final class LegacyStoreReader {
    let storeURL: URL
    private let isolatedSnapshot: LegacyStoreSnapshot
    private var container: ModelContainer!
    private var context: ModelContext!

    init(isolatedSnapshot: LegacyStoreSnapshot) throws {
        self.isolatedSnapshot = isolatedSnapshot
        storeURL = isolatedSnapshot.mainStoreURL.standardizedFileURL
        let schema = Schema([Todo.self, TodoList.self])
        let configuration = ModelConfiguration(
            "ReleasedTildoneLegacyReadOnly",
            schema: schema,
            url: storeURL,
            // A WAL-mode database whose sidecars were absent at snapshot time
            // must initialize them. This permission applies only to the
            // throwaway private copy; the original source is never opened.
            allowsSave: isolatedSnapshot.requiresWritableWALRecovery,
            cloudKitDatabase: .none
        )
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
            context = ModelContext(container)
            context.autosaveEnabled = false
        } catch {
            throw LegacyStoreReaderError.openFailure
        }
    }

    deinit {
        // Release SQLite handles before the owned snapshot removes its files.
        context = nil
        container = nil
    }

    func inspect(batchSize: Int) throws -> LegacyMigrationCounts {
        guard batchSize > 0 else { throw LegacyStoreReaderError.incompatibleSchema }
        try validateNoOrphans(batchSize: batchSize)
        var eligibleNotes = 0
        var eligibleTasks = 0
        var systemNotes = 0
        var systemTasks = 0
        var transientTasks = 0
        try forEachNoteBatch(batchSize: batchSize) { notes in
            for note in notes {
                if note.classification == .excludedSystemNote {
                    systemNotes += 1
                } else {
                    eligibleNotes += 1
                }
                for task in note.tasks {
                    switch task.classification {
                    case .userContent: eligibleTasks += 1
                    case .excludedSystemTask: systemTasks += 1
                    case .excludedTransientEmptyTask: transientTasks += 1
                    case .excludedSystemNote: throw LegacyStoreReaderError.incompatibleSchema
                    }
                }
            }
        }
        return LegacyMigrationCounts(
            eligibleNotes: eligibleNotes,
            eligibleTasks: eligibleTasks,
            excludedSystemNotes: systemNotes,
            excludedSystemTasks: systemTasks,
            excludedTransientTasks: transientTasks
        )
    }

    func forEachNoteBatch(
        batchSize: Int,
        _ body: ([LegacyNoteSnapshot]) throws -> Void
    ) throws {
        guard batchSize > 0 else { throw LegacyStoreReaderError.incompatibleSchema }
        var offset = 0
        while true {
            let notes = try noteBatch(offset: offset, batchSize: batchSize)
            if notes.isEmpty { break }
            try body(notes)
            offset += notes.count
        }
    }

    func noteBatch(offset: Int, batchSize: Int) throws -> [LegacyNoteSnapshot] {
        guard offset >= 0, batchSize > 0 else { throw LegacyStoreReaderError.incompatibleSchema }
        var descriptor = FetchDescriptor<TodoList>(sortBy: [SortDescriptor(\.created)])
        descriptor.fetchLimit = batchSize
        descriptor.fetchOffset = offset
        do { return try context.fetch(descriptor).map(snapshot) }
        catch let error as LegacyStoreReaderError { throw error }
        catch { throw LegacyStoreReaderError.incompatibleSchema }
    }

    private func snapshot(_ list: TodoList) throws -> LegacyNoteSnapshot {
        try validate(list.created)
        let noteKey = try legacyKey(list.persistentModelID)
        let isSystem = list.systemContent != nil || list.systemURL != nil
        let ordered = list.items.enumerated().sorted { lhs, rhs in
            let lhsIndex = lhs.element.index ?? Int.max
            let rhsIndex = rhs.element.index ?? Int.max
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            if lhs.element.created != rhs.element.created {
                return lhs.element.created < rhs.element.created
            }
            return lhs.offset < rhs.offset
        }
        var lastMeaningfulEditAt = list.created
        var tasks: [LegacyTaskSnapshot] = []
        tasks.reserveCapacity(ordered.count)
        for (visibleOrder, entry) in ordered.enumerated() {
            let task = entry.element
            try validate(task.created)
            if let done = task.done { try validate(done) }
            guard let owner = task.list,
                  try legacyKey(owner.persistentModelID) == noteKey else {
                throw LegacyStoreReaderError.invalidRelationship
            }
            let classification: LegacyMigrationClassification
            if isSystem {
                classification = .excludedSystemTask
            } else if task.what.isEmpty {
                classification = .excludedTransientEmptyTask
            } else {
                classification = .userContent
                lastMeaningfulEditAt = max(
                    lastMeaningfulEditAt,
                    max(task.created, task.done ?? task.created)
                )
            }
            tasks.append(LegacyTaskSnapshot(
                legacyKey: try legacyKey(task.persistentModelID),
                ownerLegacyKey: noteKey,
                createdAt: task.created,
                text: task.what,
                originalIndex: task.index,
                normalizedLegacyIndex: task.index ?? visibleOrder,
                completedAt: task.done,
                visibleOrder: visibleOrder,
                classification: classification
            ))
        }
        return LegacyNoteSnapshot(
            legacyKey: noteKey,
            createdAt: list.created,
            title: list.topic,
            lastMeaningfulEditAt: lastMeaningfulEditAt,
            classification: isSystem ? .excludedSystemNote : .userContent,
            tasks: tasks
        )
    }

    private func validateNoOrphans(batchSize: Int) throws {
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<Todo>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let tasks: [Todo]
            do { tasks = try context.fetch(descriptor) }
            catch { throw LegacyStoreReaderError.incompatibleSchema }
            if tasks.isEmpty { return }
            for task in tasks {
                guard task.list != nil else { throw LegacyStoreReaderError.invalidRelationship }
                _ = try legacyKey(task.persistentModelID)
            }
            offset += tasks.count
        }
    }

    private func legacyKey(_ identifier: PersistentIdentifier) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(identifier) else {
            throw LegacyStoreReaderError.invalidPersistentIdentifier
        }
        var hasher = TildoneSHA256()
        hasher.update(Data(identifier.entityName.utf8))
        hasher.update(Data([0]))
        hasher.update(data)
        return hasher.finalizeHex()
    }

    private func validate(_ date: Date) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw LegacyStoreReaderError.invalidDate
        }
    }
}
