//
//  DomainModels.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
import Foundation

public enum LifecycleState: String, Codable, Hashable, Sendable {
    case active
    case deleted
}

public enum CompletionState: Codable, Hashable, Sendable {
    case incomplete
    case completed(at: Date)

    public var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }

    public var completedAt: Date? {
        if case let .completed(date) = self { return date }
        return nil
    }
}

public enum DomainMutationError: Error, Equatable, Sendable {
    case versionMustAdvance
}

public struct Note: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let id: NoteID
    public let createdAt: Date
    public private(set) var title: String?
    public private(set) var titleVersion: VersionStamp
    public private(set) var lifecycle: LifecycleState
    public private(set) var lifecycleVersion: VersionStamp
    /// Display/sort metadata only. This date is not a conflict authority.
    public private(set) var lastMeaningfulEditAt: Date
    public let schemaVersion: Int

    public init(
        id: NoteID,
        createdAt: Date,
        title: String?,
        titleVersion: VersionStamp,
        lifecycle: LifecycleState = .active,
        lifecycleVersion: VersionStamp,
        lastMeaningfulEditAt: Date,
        schemaVersion: Int = Note.currentSchemaVersion
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.titleVersion = titleVersion
        self.lifecycle = lifecycle
        self.lifecycleVersion = lifecycleVersion
        self.lastMeaningfulEditAt = lastMeaningfulEditAt
        self.schemaVersion = schemaVersion
    }

    public mutating func rename(to title: String?, version: VersionStamp, editedAt: Date) throws {
        guard version > titleVersion else { throw DomainMutationError.versionMustAdvance }
        self.title = title
        titleVersion = version
        lastMeaningfulEditAt = max(lastMeaningfulEditAt, editedAt)
    }

    public mutating func delete(version: VersionStamp) throws {
        try setLifecycle(.deleted, version: version)
    }

    /// Restoring is explicit and requires a lifecycle version newer than deletion.
    public mutating func restore(version: VersionStamp) throws {
        try setLifecycle(.active, version: version)
    }

    /// Records display/sort metadata without making wall-clock time a conflict
    /// authority. Persistence calls this for meaningful child-task changes.
    public mutating func recordMeaningfulEdit(at date: Date) {
        lastMeaningfulEditAt = max(lastMeaningfulEditAt, date)
    }

    private mutating func setLifecycle(_ state: LifecycleState, version: VersionStamp) throws {
        guard version > lifecycleVersion else { throw DomainMutationError.versionMustAdvance }
        lifecycle = state
        lifecycleVersion = version
    }
}

public struct Task: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let id: TaskID
    public let noteID: NoteID
    public let createdAt: Date
    public private(set) var text: String
    public private(set) var textVersion: VersionStamp
    public private(set) var completion: CompletionState
    public private(set) var completionVersion: VersionStamp
    public private(set) var orderToken: OrderToken
    public private(set) var orderVersion: VersionStamp
    public private(set) var lifecycle: LifecycleState
    public private(set) var lifecycleVersion: VersionStamp
    public let schemaVersion: Int

    public var isCompleted: Bool { completion.isCompleted }
    public var completedAt: Date? { completion.completedAt }

    public init(
        id: TaskID,
        noteID: NoteID,
        createdAt: Date,
        text: String,
        textVersion: VersionStamp,
        completion: CompletionState = .incomplete,
        completionVersion: VersionStamp,
        orderToken: OrderToken,
        orderVersion: VersionStamp,
        lifecycle: LifecycleState = .active,
        lifecycleVersion: VersionStamp,
        schemaVersion: Int = Task.currentSchemaVersion
    ) {
        self.id = id
        self.noteID = noteID
        self.createdAt = createdAt
        self.text = text
        self.textVersion = textVersion
        self.completion = completion
        self.completionVersion = completionVersion
        self.orderToken = orderToken
        self.orderVersion = orderVersion
        self.lifecycle = lifecycle
        self.lifecycleVersion = lifecycleVersion
        self.schemaVersion = schemaVersion
    }

    public mutating func editText(_ text: String, version: VersionStamp) throws {
        guard version > textVersion else { throw DomainMutationError.versionMustAdvance }
        self.text = text
        textVersion = version
    }

    public mutating func setCompletion(_ completion: CompletionState, version: VersionStamp) throws {
        guard version > completionVersion else { throw DomainMutationError.versionMustAdvance }
        self.completion = completion
        completionVersion = version
    }

    public mutating func move(to orderToken: OrderToken, version: VersionStamp) throws {
        guard version > orderVersion else { throw DomainMutationError.versionMustAdvance }
        self.orderToken = orderToken
        orderVersion = version
    }

    public mutating func delete(version: VersionStamp) throws {
        try setLifecycle(.deleted, version: version)
    }

    public mutating func restore(version: VersionStamp) throws {
        try setLifecycle(.active, version: version)
    }

    public static func orderedBefore(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.orderToken != rhs.orderToken {
            return lhs.orderToken < rhs.orderToken
        }
        return lhs.id < rhs.id
    }

    private mutating func setLifecycle(_ state: LifecycleState, version: VersionStamp) throws {
        guard version > lifecycleVersion else { throw DomainMutationError.versionMustAdvance }
        lifecycle = state
        lifecycleVersion = version
    }
}

public struct NoteTaskSummary: Codable, Hashable, Sendable {
    public let totalCount: Int
    public let completedCount: Int

    public var pendingCount: Int { totalCount - completedCount }
    public var isEmpty: Bool { totalCount == 0 }
    public var isComplete: Bool { totalCount > 0 && pendingCount == 0 }

    public init<S: Sequence>(noteID: NoteID, tasks: S) where S.Element == Task {
        let activeTasks = tasks.filter { $0.noteID == noteID && $0.lifecycle == .active }
        totalCount = activeTasks.count
        completedCount = activeTasks.lazy.filter(\.isCompleted).count
    }
}
