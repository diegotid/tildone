//
//  LegacyMigrationCoordinator.swift
//  Tildone
//
//  Created by OpenAI Codex on 7/13/26.
//
import Foundation
import TildoneDomain
import TildonePersistence

enum LegacyMigrationCheckpoint: Hashable, Sendable {
    case afterSourceSnapshot
    case afterMarker
    case afterMapping
    case afterNoteBatch(Int)
    case afterTaskBatch(Int)
    case beforeVerification
    case duringVerification(Int)
    case afterVerified
}

enum LegacyMigrationCoordinatorError: Error, Equatable {
    case missingSource
    case sourceDestinationCollision
    case sourceChanged
    case sourceOpen
    case incompatibleSource
    case invalidRelationship
    case destinationOpen
    case destinationWrite
    case destinationNotEmpty
    case differentSource
    case migrationVersionMismatch
    case priorFailedDestination
    case verificationMismatch
    case interrupted(LegacyMigrationCheckpoint)
}

struct LegacyMigrationResult: Hashable, Sendable {
    let phase: LegacyMigrationPhase
    let eligibleForCutover: Bool
    let activated: Bool
    let cloudSeedingEverBegun: Bool
    let sourceCounts: LegacyMigrationCounts
    let destinationNoteCount: Int
    let destinationTaskCount: Int
    let mappingCount: Int
    let migrationReplicaID: ReplicaID
    let logicalCounterProgress: UInt64
}

struct LegacyMigrationOptions: Sendable {
    static let currentFormatVersion = 1

    let batchSize: Int
    let resumeFailedMigration: Bool
    let snapshotRootURL: URL?
    let now: @Sendable () -> Date
    let checkpoint: @Sendable (LegacyMigrationCheckpoint) throws -> Void

    init(
        batchSize: Int = 128,
        resumeFailedMigration: Bool = false,
        snapshotRootURL: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        checkpoint: @escaping @Sendable (LegacyMigrationCheckpoint) throws -> Void = { _ in }
    ) {
        self.batchSize = batchSize
        self.resumeFailedMigration = resumeFailedMigration
        self.snapshotRootURL = snapshotRootURL
        self.now = now
        self.checkpoint = checkpoint
    }
}

@MainActor
final class LegacyMigrationCoordinator {
    let sourceURL: URL
    let destinationURL: URL
    let options: LegacyMigrationOptions

    init(sourceURL: URL, destinationURL: URL, options: LegacyMigrationOptions = .init()) {
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.options = options
    }

    func migrate() async throws -> LegacyMigrationResult {
        guard options.batchSize > 0 else { throw LegacyMigrationCoordinatorError.incompatibleSource }
        let sourceFiles: LegacyStoreFileSet
        do {
            sourceFiles = try LegacyStoreFileSet.inspect(
                sourceURL: sourceURL,
                destinationURL: destinationURL
            )
        } catch {
            throw Self.mapDiscoveryError(error)
        }

        var activeRepository: TildoneRepository?
        do {
            let snapshot = try sourceFiles.makeReadOnlySnapshot(in: options.snapshotRootURL)
            try runCheckpoint(.afterSourceSnapshot)
            let reader = try LegacyStoreReader(isolatedSnapshot: snapshot)
            let counts = try reader.inspect(batchSize: options.batchSize)
            let descriptor = PersistenceStoreDescriptor.temporaryMigration(storeURL: destinationURL)
            do {
            do {
                activeRepository = try TildoneRepository(descriptor: descriptor)
            } catch {
                throw LegacyMigrationCoordinatorError.destinationOpen
            }
            guard let repository = activeRepository else {
                throw LegacyMigrationCoordinatorError.destinationOpen
            }

            var state = try await existingOrPreparedState(
                repository: repository,
                fingerprint: sourceFiles.fingerprint,
                counts: counts
            )
            if state.phase == .failed {
                guard options.resumeFailedMigration else {
                    throw LegacyMigrationCoordinatorError.priorFailedDestination
                }
                try await repository.resumeFailedLegacyMigration(at: options.now())
                state = try await repository.legacyMigrationSnapshot()
            }
            if state.phase == .notStarted {
                try await repository.advanceLegacyMigration(to: .sourceInspected, at: options.now())
                state = try await repository.legacyMigrationSnapshot()
            }
            if state.phase == .sourceInspected {
                try await repository.advanceLegacyMigration(to: .destinationPrepared, at: options.now())
                state = try await repository.legacyMigrationSnapshot()
            }
            try runCheckpoint(.afterMarker)

            if [.destinationPrepared, .copyInProgress].contains(state.phase) {
                if state.phase == .destinationPrepared {
                    try await repository.advanceLegacyMigration(to: .copyInProgress, at: options.now())
                }
                try await copy(reader: reader, to: repository)
                let currentSource = try LegacyStoreFileSet.inspect(sourceURL: sourceURL)
                guard currentSource.fingerprint == sourceFiles.fingerprint else {
                    throw LegacyMigrationCoordinatorError.sourceChanged
                }
                let audit = try await repository.legacyMigrationAudit()
                guard audit.noteCount == counts.eligibleNotes,
                      audit.taskCount == counts.eligibleTasks,
                      audit.pendingMutationCount == 0,
                      !audit.duplicateNoteIDs,
                      !audit.duplicateTaskIDs,
                      !audit.duplicateMappedStableIDs else {
                    throw LegacyMigrationCoordinatorError.verificationMismatch
                }
                try await repository.advanceLegacyMigration(to: .copyCompleted, at: options.now())
            }
            activeRepository = nil
            }

            try runCheckpoint(.beforeVerification)
            let verified: LegacyMigrationSnapshot
            do {
                verified = try await verify(
                    sourceFiles: sourceFiles,
                    expectedCounts: counts,
                    descriptor: descriptor
                )
            } catch let error as LegacyMigrationCoordinatorError {
                switch error {
                case .interrupted, .sourceChanged, .destinationOpen:
                    throw error
                default:
                    throw LegacyMigrationCoordinatorError.verificationMismatch
                }
            } catch {
                throw LegacyMigrationCoordinatorError.verificationMismatch
            }
            return Self.result(verified)
        } catch let error as LegacyMigrationCoordinatorError {
            if case .interrupted = error {
                activeRepository = nil
                throw error
            }
            let category = Self.failureCategory(for: error)
            if let activeRepository {
                try? await activeRepository.recordLegacyMigrationFailure(category, at: options.now())
            } else if let repository = try? TildoneRepository(
                descriptor: .temporaryMigration(storeURL: destinationURL)
            ) {
                try? await repository.recordLegacyMigrationFailure(category, at: options.now())
            }
            activeRepository = nil
            throw error
        } catch {
            if let activeRepository {
                try? await activeRepository.recordLegacyMigrationFailure(.destinationWrite, at: options.now())
            }
            activeRepository = nil
            throw Self.mapUnexpectedError(error)
        }
    }

    private func existingOrPreparedState(
        repository: TildoneRepository,
        fingerprint: LegacySourceFingerprint,
        counts: LegacyMigrationCounts
    ) async throws -> LegacyMigrationSnapshot {
        do {
            let state = try await repository.legacyMigrationSnapshot()
            guard state.migrationFormatVersion == LegacyMigrationOptions.currentFormatVersion else {
                throw LegacyMigrationCoordinatorError.migrationVersionMismatch
            }
            guard state.sourceFingerprint.identityDigest == fingerprint.identityDigest else {
                throw LegacyMigrationCoordinatorError.differentSource
            }
            guard state.sourceFingerprint == fingerprint, state.sourceCounts == counts else {
                throw LegacyMigrationCoordinatorError.sourceChanged
            }
            guard state.destinationSchemaVersion == TildoneRepository.currentSharedSchemaVersion,
                  !state.cloudSeedingEverBegun,
                  state.activationState != .activated else {
                throw LegacyMigrationCoordinatorError.verificationMismatch
            }
            return state
        } catch LegacyMigrationPersistenceError.stateMissing {
            do {
                return try await repository.prepareLegacyMigration(
                    formatVersion: LegacyMigrationOptions.currentFormatVersion,
                    sourceFingerprint: fingerprint,
                    sourceCounts: counts,
                    at: options.now()
                )
            } catch LegacyMigrationPersistenceError.destinationNotEmpty {
                throw LegacyMigrationCoordinatorError.destinationNotEmpty
            }
        }
    }

    private func copy(reader: LegacyStoreReader, to repository: TildoneRepository) async throws {
        var offset = 0
        var noteBatchNumber = 0
        var taskBatchNumber = 0
        while true {
            let notes = try reader.noteBatch(offset: offset, batchSize: options.batchSize)
            if notes.isEmpty { break }
            for note in notes {
                _ = try await repository.prepareLegacyMappings([
                    LegacyMappingRequest(
                        legacyKey: note.legacyKey,
                        entityKind: .note,
                        classification: note.classification
                    )
                ], at: options.now())
                try runCheckpoint(.afterMapping)
                if note.classification == .userContent {
                    try await repository.importLegacyNotes([
                        LegacyImportedNote(
                            legacyKey: note.legacyKey,
                            createdAt: note.createdAt,
                            title: note.title,
                            lastMeaningfulEditAt: note.lastMeaningfulEditAt
                        )
                    ], at: options.now())
                }

                for taskSlice in note.tasks.chunked(maximumCount: options.batchSize) {
                    let requests = taskSlice.map {
                        LegacyMappingRequest(
                            legacyKey: $0.legacyKey,
                            entityKind: .task,
                            classification: $0.classification,
                            ownerLegacyKey: $0.ownerLegacyKey,
                            visibleOrder: $0.visibleOrder
                        )
                    }
                    _ = try await repository.prepareLegacyMappings(requests, at: options.now())
                    try runCheckpoint(.afterMapping)
                    let imports = try taskSlice.filter { $0.classification == .userContent }.map {
                        LegacyImportedTask(
                            legacyKey: $0.legacyKey,
                            ownerLegacyKey: $0.ownerLegacyKey,
                            createdAt: $0.createdAt,
                            text: $0.text,
                            completedAt: $0.completedAt,
                            orderToken: try Self.orderToken(for: $0.visibleOrder)
                        )
                    }
                    if !imports.isEmpty {
                        try await repository.importLegacyTasks(imports, at: options.now())
                    }
                    taskBatchNumber += 1
                    try runCheckpoint(.afterTaskBatch(taskBatchNumber))
                }
            }
            offset += notes.count
            noteBatchNumber += 1
            try runCheckpoint(.afterNoteBatch(noteBatchNumber))
        }
    }

    private func verify(
        sourceFiles: LegacyStoreFileSet,
        expectedCounts: LegacyMigrationCounts,
        descriptor: PersistenceStoreDescriptor
    ) async throws -> LegacyMigrationSnapshot {
        let currentSource = try LegacyStoreFileSet.inspect(sourceURL: sourceURL)
        guard currentSource.fingerprint == sourceFiles.fingerprint else {
            throw LegacyMigrationCoordinatorError.sourceChanged
        }
        let snapshot = try currentSource.makeReadOnlySnapshot(in: options.snapshotRootURL)
        let reader = try LegacyStoreReader(isolatedSnapshot: snapshot)
        var repository: TildoneRepository?
        do { repository = try TildoneRepository(descriptor: descriptor) }
        catch { throw LegacyMigrationCoordinatorError.destinationOpen }
        guard let repository else { throw LegacyMigrationCoordinatorError.destinationOpen }
        var state = try await repository.legacyMigrationSnapshot()
        if state.phase == .copyCompleted {
            try await repository.advanceLegacyMigration(to: .verificationInProgress, at: options.now())
            state = try await repository.legacyMigrationSnapshot()
        }
        guard [.verificationInProgress, .verified, .eligibleForCutover].contains(state.phase) else {
            throw LegacyMigrationCoordinatorError.verificationMismatch
        }

        var offset = 0
        var verificationBatch = 0
        var expectedMappingCount = 0
        while true {
            let notes = try reader.noteBatch(offset: offset, batchSize: options.batchSize)
            if notes.isEmpty { break }
            for note in notes {
                expectedMappingCount += 1 + note.tasks.count
                let noteMapping = try await repository.legacyMapping(for: note.legacyKey)
                guard noteMapping.classification == note.classification else {
                    throw LegacyMigrationCoordinatorError.verificationMismatch
                }
                if note.classification == .userContent {
                    let expected = try Self.expectedNote(note, mapping: noteMapping, replica: state.migrationReplicaID)
                    let actual = try await repository.note(id: expected.id, includingDeleted: true)
                    guard actual == expected else { throw LegacyMigrationCoordinatorError.verificationMismatch }
                } else if noteMapping.stableID != nil {
                    throw LegacyMigrationCoordinatorError.verificationMismatch
                }

                var expectedOrderedTaskIDs: [TaskID] = []
                for task in note.tasks {
                    let taskMapping = try await repository.legacyMapping(for: task.legacyKey)
                    guard taskMapping.classification == task.classification,
                          taskMapping.ownerLegacyKey == task.ownerLegacyKey,
                          taskMapping.visibleOrder == task.visibleOrder else {
                        throw LegacyMigrationCoordinatorError.verificationMismatch
                    }
                    if task.classification == .userContent {
                        let expected = try Self.expectedTask(task, mapping: taskMapping, noteMapping: noteMapping, replica: state.migrationReplicaID)
                        let actual = try await repository.task(id: expected.id, includingDeleted: true)
                        guard actual == expected else { throw LegacyMigrationCoordinatorError.verificationMismatch }
                        expectedOrderedTaskIDs.append(expected.id)
                    } else if taskMapping.stableID != nil {
                        throw LegacyMigrationCoordinatorError.verificationMismatch
                    }
                }
                if note.classification == .userContent {
                    guard try await repository.orderedTasks(in: try Self.noteID(noteMapping)).map(\.id) == expectedOrderedTaskIDs else {
                        throw LegacyMigrationCoordinatorError.verificationMismatch
                    }
                }
            }
            offset += notes.count
            verificationBatch += 1
            try runCheckpoint(.duringVerification(verificationBatch))
        }

        let audit = try await repository.legacyMigrationAudit()
        guard audit.noteCount == expectedCounts.eligibleNotes,
              audit.taskCount == expectedCounts.eligibleTasks,
              audit.mappingCount == expectedMappingCount,
              audit.pendingMutationCount == 0,
              audit.destinationSchemaVersion == TildoneRepository.currentSharedSchemaVersion,
              !audit.duplicateNoteIDs,
              !audit.duplicateTaskIDs,
              !audit.duplicateMappedStableIDs else {
            throw LegacyMigrationCoordinatorError.verificationMismatch
        }
        let finalSource = try LegacyStoreFileSet.inspect(sourceURL: sourceURL)
        guard finalSource.fingerprint == sourceFiles.fingerprint else {
            throw LegacyMigrationCoordinatorError.sourceChanged
        }

        state = try await repository.legacyMigrationSnapshot()
        if state.phase == .verificationInProgress {
            try await repository.advanceLegacyMigration(to: .verified, at: options.now())
            state = try await repository.legacyMigrationSnapshot()
        }
        try runCheckpoint(.afterVerified)
        if state.phase == .verified {
            try await repository.advanceLegacyMigration(to: .eligibleForCutover, at: options.now())
            state = try await repository.legacyMigrationSnapshot()
        }
        guard state.phase == .eligibleForCutover,
              state.activationState == .verifiedNotActivated,
              !state.cloudSeedingEverBegun else {
            throw LegacyMigrationCoordinatorError.verificationMismatch
        }
        return state
    }

    private func runCheckpoint(_ checkpoint: LegacyMigrationCheckpoint) throws {
        do { try options.checkpoint(checkpoint) }
        catch { throw LegacyMigrationCoordinatorError.interrupted(checkpoint) }
    }

    private static func orderToken(for visibleOrder: Int) throws -> OrderToken {
        guard visibleOrder >= 0 else { throw LegacyMigrationCoordinatorError.incompatibleSource }
        let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        var value = visibleOrder + 1
        var encoded = ""
        repeat {
            encoded.insert(digits[value % digits.count], at: encoded.startIndex)
            value /= digits.count
        } while value > 0
        let padded = String(repeating: "0", count: max(0, 13 - encoded.count)) + encoded + "h"
        return try OrderToken(rawValue: padded)
    }

    private static func noteID(_ mapping: LegacyMappingSnapshot) throws -> NoteID {
        guard let value = mapping.stableID, let id = NoteID(string: value) else {
            throw LegacyMigrationCoordinatorError.verificationMismatch
        }
        return id
    }

    private static func expectedNote(
        _ source: LegacyNoteSnapshot,
        mapping: LegacyMappingSnapshot,
        replica: ReplicaID
    ) throws -> TildoneDomain.Note {
        guard let first = mapping.firstVersionCounter, mapping.versionCount == 3 else {
            throw LegacyMigrationCoordinatorError.verificationMismatch
        }
        return TildoneDomain.Note(
            id: try noteID(mapping),
            createdAt: source.createdAt,
            title: source.title,
            titleVersion: VersionStamp(logicalCounter: first, replicaID: replica),
            lifecycle: .active,
            lifecycleVersion: VersionStamp(logicalCounter: first + 1, replicaID: replica),
            lastMeaningfulEditAt: source.lastMeaningfulEditAt,
            lastMeaningfulEditVersion: VersionStamp(logicalCounter: first + 2, replicaID: replica)
        )
    }

    private static func expectedTask(
        _ source: LegacyTaskSnapshot,
        mapping: LegacyMappingSnapshot,
        noteMapping: LegacyMappingSnapshot,
        replica: ReplicaID
    ) throws -> TildoneDomain.Task {
        guard let value = mapping.stableID, let id = TaskID(string: value),
              let first = mapping.firstVersionCounter, mapping.versionCount == 4 else {
            throw LegacyMigrationCoordinatorError.verificationMismatch
        }
        return TildoneDomain.Task(
            id: id,
            noteID: try noteID(noteMapping),
            createdAt: source.createdAt,
            text: source.text,
            textVersion: VersionStamp(logicalCounter: first, replicaID: replica),
            completion: source.completedAt.map(CompletionState.completed) ?? .incomplete,
            completionVersion: VersionStamp(logicalCounter: first + 1, replicaID: replica),
            orderToken: try orderToken(for: source.visibleOrder),
            orderVersion: VersionStamp(logicalCounter: first + 2, replicaID: replica),
            lifecycle: .active,
            lifecycleVersion: VersionStamp(logicalCounter: first + 3, replicaID: replica)
        )
    }

    private static func result(_ state: LegacyMigrationSnapshot) -> LegacyMigrationResult {
        LegacyMigrationResult(
            phase: state.phase,
            eligibleForCutover: state.phase == .eligibleForCutover,
            activated: state.activationState == .activated,
            cloudSeedingEverBegun: state.cloudSeedingEverBegun,
            sourceCounts: state.sourceCounts,
            destinationNoteCount: state.destinationNoteCount,
            destinationTaskCount: state.destinationTaskCount,
            mappingCount: state.mappingCount,
            migrationReplicaID: state.migrationReplicaID,
            logicalCounterProgress: state.logicalCounterProgress
        )
    }

    private static func mapDiscoveryError(_ error: Error) -> LegacyMigrationCoordinatorError {
        switch error as? LegacyStoreDiscoveryError {
        case .missingSource: .missingSource
        case .sourceDestinationCollision: .sourceDestinationCollision
        case .sourceChanged: .sourceChanged
        default: .incompatibleSource
        }
    }

    private static func mapUnexpectedError(_ error: Error) -> LegacyMigrationCoordinatorError {
        switch error {
        case let error as LegacyMigrationCoordinatorError: error
        case LegacyStoreReaderError.openFailure: .sourceOpen
        case LegacyStoreReaderError.invalidRelationship: .invalidRelationship
        case is LegacyStoreReaderError: .incompatibleSource
        case LegacyMigrationPersistenceError.destinationNotEmpty: .destinationNotEmpty
        case LegacyMigrationPersistenceError.saveFailure: .destinationWrite
        case let LegacyMigrationPersistenceError.incompatibleExistingState(category):
            switch category {
            case .differentSource: .differentSource
            case .sourceChanged: .sourceChanged
            case .migrationVersionMismatch: .migrationVersionMismatch
            case .priorFailedDestination: .priorFailedDestination
            default: .destinationWrite
            }
        default: .destinationWrite
        }
    }

    private static func failureCategory(for error: LegacyMigrationCoordinatorError) -> LegacyMigrationFailureCategory {
        switch error {
        case .missingSource: .missingSource
        case .sourceDestinationCollision: .sourceDestinationCollision
        case .sourceChanged: .sourceChanged
        case .sourceOpen: .sourceOpen
        case .incompatibleSource: .incompatibleSource
        case .invalidRelationship: .invalidRelationship
        case .destinationOpen: .destinationOpen
        case .destinationWrite: .destinationWrite
        case .destinationNotEmpty: .destinationNotEmpty
        case .differentSource: .differentSource
        case .migrationVersionMismatch: .migrationVersionMismatch
        case .priorFailedDestination: .priorFailedDestination
        case .verificationMismatch: .verificationMismatch
        case .interrupted: .destinationWrite
        }
    }
}

private extension Array {
    func chunked(maximumCount: Int) -> [ArraySlice<Element>] {
        guard maximumCount > 0 else { return [] }
        var chunks: [ArraySlice<Element>] = []
        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: maximumCount, limitedBy: endIndex) ?? endIndex
            chunks.append(self[start..<end])
            start = end
        }
        return chunks
    }
}
