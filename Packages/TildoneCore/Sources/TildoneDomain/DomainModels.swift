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

/// A stable, transport-neutral palette shared by every Tildone client.
/// Platform targets own the concrete AppKit/UIKit/SwiftUI color conversion.
public enum NoteColor: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case yellow
    case green
    case blue
    case pink
    case purple
    case orange

    public var id: Self { self }
}

public enum NoteKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case checklist
    case singleTask

    public var id: Self { self }
}

/// A stable font choice for the single-memo presentation. Raw values are part
/// of the local and CloudKit contracts; platform targets map them to bundled
/// PostScript font names.
public enum SingleMemoFont: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case overlock
    case coveredByYourGrace
    case craftyGirls
    case lacquer
    case meowScript
    case permanentMarker
    case seaweedScript

    public var id: Self { self }
}

public struct Note: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 4
    public static let oldestSupportedSchemaVersion = 1

    public let id: NoteID
    public let createdAt: Date
    public private(set) var title: String?
    public private(set) var titleVersion: VersionStamp
    public private(set) var color: NoteColor
    public private(set) var colorVersion: VersionStamp
    public private(set) var kind: NoteKind
    public private(set) var kindVersion: VersionStamp
    public private(set) var singleMemoFont: SingleMemoFont
    public private(set) var singleMemoFontVersion: VersionStamp
    public private(set) var lifecycle: LifecycleState
    public private(set) var lifecycleVersion: VersionStamp
    /// Display/sort metadata only. This date is not a conflict authority.
    public private(set) var lastMeaningfulEditAt: Date
    public private(set) var lastMeaningfulEditVersion: VersionStamp
    public let schemaVersion: Int

    public init(
        id: NoteID,
        createdAt: Date,
        title: String?,
        titleVersion: VersionStamp,
        color: NoteColor = .yellow,
        colorVersion: VersionStamp? = nil,
        kind: NoteKind = .checklist,
        kindVersion: VersionStamp? = nil,
        singleMemoFont: SingleMemoFont = .overlock,
        singleMemoFontVersion: VersionStamp? = nil,
        lifecycle: LifecycleState = .active,
        lifecycleVersion: VersionStamp,
        lastMeaningfulEditAt: Date,
        lastMeaningfulEditVersion: VersionStamp,
        schemaVersion: Int = Note.currentSchemaVersion
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.titleVersion = titleVersion
        self.color = color
        self.colorVersion = colorVersion ?? titleVersion
        self.kind = kind
        self.kindVersion = kindVersion ?? titleVersion
        self.singleMemoFont = singleMemoFont
        self.singleMemoFontVersion = singleMemoFontVersion ?? titleVersion
        self.lifecycle = lifecycle
        self.lifecycleVersion = lifecycleVersion
        self.lastMeaningfulEditAt = lastMeaningfulEditAt
        self.lastMeaningfulEditVersion = lastMeaningfulEditVersion
        self.schemaVersion = schemaVersion
    }

    public mutating func rename(
        to title: String?,
        version: VersionStamp,
        editedAt: Date,
        meaningfulEditVersion: VersionStamp
    ) throws {
        guard version > titleVersion else { throw DomainMutationError.versionMustAdvance }
        guard meaningfulEditVersion > lastMeaningfulEditVersion else {
            throw DomainMutationError.versionMustAdvance
        }
        self.title = title
        titleVersion = version
        lastMeaningfulEditAt = editedAt
        lastMeaningfulEditVersion = meaningfulEditVersion
    }

    public mutating func setColor(_ color: NoteColor, version: VersionStamp) throws {
        guard version > colorVersion else { throw DomainMutationError.versionMustAdvance }
        self.color = color
        colorVersion = version
    }

    public mutating func setKind(_ kind: NoteKind, version: VersionStamp) throws {
        guard version > kindVersion else { throw DomainMutationError.versionMustAdvance }
        self.kind = kind
        kindVersion = version
    }

    public mutating func setSingleMemoFont(
        _ font: SingleMemoFont,
        version: VersionStamp
    ) throws {
        guard version > singleMemoFontVersion else {
            throw DomainMutationError.versionMustAdvance
        }
        singleMemoFont = font
        singleMemoFontVersion = version
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
    public mutating func recordMeaningfulEdit(at date: Date, version: VersionStamp) throws {
        guard version > lastMeaningfulEditVersion else {
            throw DomainMutationError.versionMustAdvance
        }
        lastMeaningfulEditAt = date
        lastMeaningfulEditVersion = version
    }

    private mutating func setLifecycle(_ state: LifecycleState, version: VersionStamp) throws {
        guard version > lifecycleVersion else { throw DomainMutationError.versionMustAdvance }
        lifecycle = state
        lifecycleVersion = version
    }


    private enum CodingKeys: String, CodingKey {
        case id, createdAt, title, titleVersion, color, colorVersion, kind, kindVersion,
             singleMemoFont, singleMemoFontVersion, lifecycle,
             lifecycleVersion, lastMeaningfulEditAt, lastMeaningfulEditVersion,
             schemaVersion
    }

    /// Domain payloads written before note colors existed remain readable. A
    /// V1 payload deterministically starts as yellow at its title version; the
    /// first explicit color mutation necessarily advances beyond that stamp.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(NoteID.self, forKey: .id)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        titleVersion = try values.decode(VersionStamp.self, forKey: .titleVersion)
        color = try values.decodeIfPresent(NoteColor.self, forKey: .color) ?? .yellow
        colorVersion = try values.decodeIfPresent(VersionStamp.self, forKey: .colorVersion)
            ?? titleVersion
        kind = try values.decodeIfPresent(NoteKind.self, forKey: .kind) ?? .checklist
        kindVersion = try values.decodeIfPresent(VersionStamp.self, forKey: .kindVersion)
            ?? titleVersion
        singleMemoFont = try values.decodeIfPresent(
            SingleMemoFont.self,
            forKey: .singleMemoFont
        ) ?? .overlock
        singleMemoFontVersion = try values.decodeIfPresent(
            VersionStamp.self,
            forKey: .singleMemoFontVersion
        ) ?? titleVersion
        lifecycle = try values.decode(LifecycleState.self, forKey: .lifecycle)
        lifecycleVersion = try values.decode(VersionStamp.self, forKey: .lifecycleVersion)
        lastMeaningfulEditAt = try values.decode(Date.self, forKey: .lastMeaningfulEditAt)
        lastMeaningfulEditVersion = try values.decode(
            VersionStamp.self,
            forKey: .lastMeaningfulEditVersion
        )
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encodeIfPresent(title, forKey: .title)
        try values.encode(titleVersion, forKey: .titleVersion)
        try values.encode(color, forKey: .color)
        try values.encode(colorVersion, forKey: .colorVersion)
        try values.encode(kind, forKey: .kind)
        try values.encode(kindVersion, forKey: .kindVersion)
        try values.encode(singleMemoFont, forKey: .singleMemoFont)
        try values.encode(singleMemoFontVersion, forKey: .singleMemoFontVersion)
        try values.encode(lifecycle, forKey: .lifecycle)
        try values.encode(lifecycleVersion, forKey: .lifecycleVersion)
        try values.encode(lastMeaningfulEditAt, forKey: .lastMeaningfulEditAt)
        try values.encode(lastMeaningfulEditVersion, forKey: .lastMeaningfulEditVersion)
        try values.encode(schemaVersion, forKey: .schemaVersion)
    }
}

public struct Task: Codable, Hashable, Sendable {
    public static let oldestSupportedSchemaVersion = 1
    public static let currentSchemaVersion = 3

    public let id: TaskID
    public let noteID: NoteID
    public let createdAt: Date
    public private(set) var richText: RichText
    public private(set) var textVersion: VersionStamp
    public private(set) var completion: CompletionState
    public private(set) var completionVersion: VersionStamp
    public private(set) var orderToken: OrderToken
    public private(set) var orderVersion: VersionStamp
    /// A preorder depth. The preceding task at a lower depth is this task's
    /// visual parent; zero is a top-level task.
    public private(set) var indentLevel: Int
    public private(set) var indentVersion: VersionStamp
    public private(set) var lifecycle: LifecycleState
    public private(set) var lifecycleVersion: VersionStamp
    public let schemaVersion: Int

    public var text: String { richText.text }
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
        indentLevel: Int = 0,
        indentVersion: VersionStamp? = nil,
        lifecycle: LifecycleState = .active,
        lifecycleVersion: VersionStamp,
        schemaVersion: Int = Task.currentSchemaVersion
    ) {
        self.id = id
        self.noteID = noteID
        self.createdAt = createdAt
        self.richText = RichText(text: text)
        self.textVersion = textVersion
        self.completion = completion
        self.completionVersion = completionVersion
        self.orderToken = orderToken
        self.orderVersion = orderVersion
        self.indentLevel = indentLevel
        self.indentVersion = indentVersion ?? orderVersion
        self.lifecycle = lifecycle
        self.lifecycleVersion = lifecycleVersion
        self.schemaVersion = schemaVersion
    }

    public init(
        id: TaskID,
        noteID: NoteID,
        createdAt: Date,
        richText: RichText,
        textVersion: VersionStamp,
        completion: CompletionState = .incomplete,
        completionVersion: VersionStamp,
        orderToken: OrderToken,
        orderVersion: VersionStamp,
        indentLevel: Int = 0,
        indentVersion: VersionStamp? = nil,
        lifecycle: LifecycleState = .active,
        lifecycleVersion: VersionStamp,
        schemaVersion: Int = Task.currentSchemaVersion
    ) {
        self.id = id
        self.noteID = noteID
        self.createdAt = createdAt
        self.richText = richText
        self.textVersion = textVersion
        self.completion = completion
        self.completionVersion = completionVersion
        self.orderToken = orderToken
        self.orderVersion = orderVersion
        self.indentLevel = indentLevel
        self.indentVersion = indentVersion ?? orderVersion
        self.lifecycle = lifecycle
        self.lifecycleVersion = lifecycleVersion
        self.schemaVersion = schemaVersion
    }

    public mutating func editText(_ text: String, version: VersionStamp) throws {
        try editRichText(RichText(text: text), version: version)
    }

    public mutating func editRichText(_ richText: RichText, version: VersionStamp) throws {
        guard version > textVersion else { throw DomainMutationError.versionMustAdvance }
        self.richText = richText
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

    public mutating func setIndentLevel(_ indentLevel: Int, version: VersionStamp) throws {
        guard indentLevel >= 0, version > indentVersion else {
            throw DomainMutationError.versionMustAdvance
        }
        self.indentLevel = indentLevel
        indentVersion = version
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

    private enum CodingKeys: String, CodingKey {
        case id, noteID, createdAt, text, richText, textVersion, completion,
             completionVersion, orderToken, orderVersion, indentLevel,
             indentVersion, lifecycle, lifecycleVersion, schemaVersion
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(TaskID.self, forKey: .id)
        noteID = try values.decode(NoteID.self, forKey: .noteID)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        let legacyText = try values.decodeIfPresent(String.self, forKey: .text)
        if let decoded = try values.decodeIfPresent(RichText.self, forKey: .richText) {
            guard legacyText == nil || legacyText == decoded.text else {
                throw DecodingError.dataCorruptedError(
                    forKey: .richText,
                    in: values,
                    debugDescription: "Rich text and compatibility text disagree"
                )
            }
            richText = decoded
        } else {
            guard schemaVersion < 3 else {
                throw DecodingError.keyNotFound(
                    CodingKeys.richText,
                    .init(
                        codingPath: values.codingPath,
                        debugDescription: "Task schema V3 requires canonical rich text"
                    )
                )
            }
            richText = RichText(text: try values.decode(String.self, forKey: .text))
        }
        textVersion = try values.decode(VersionStamp.self, forKey: .textVersion)
        completion = try values.decode(CompletionState.self, forKey: .completion)
        completionVersion = try values.decode(VersionStamp.self, forKey: .completionVersion)
        orderToken = try values.decode(OrderToken.self, forKey: .orderToken)
        orderVersion = try values.decode(VersionStamp.self, forKey: .orderVersion)
        indentLevel = try values.decodeIfPresent(Int.self, forKey: .indentLevel) ?? 0
        indentVersion = try values.decodeIfPresent(VersionStamp.self, forKey: .indentVersion)
            ?? orderVersion
        lifecycle = try values.decode(LifecycleState.self, forKey: .lifecycle)
        lifecycleVersion = try values.decode(VersionStamp.self, forKey: .lifecycleVersion)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(noteID, forKey: .noteID)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(text, forKey: .text)
        if schemaVersion >= 3 { try values.encode(richText, forKey: .richText) }
        try values.encode(textVersion, forKey: .textVersion)
        try values.encode(completion, forKey: .completion)
        try values.encode(completionVersion, forKey: .completionVersion)
        try values.encode(orderToken, forKey: .orderToken)
        try values.encode(orderVersion, forKey: .orderVersion)
        if schemaVersion >= 2 {
            try values.encode(indentLevel, forKey: .indentLevel)
            try values.encode(indentVersion, forKey: .indentVersion)
        }
        try values.encode(lifecycle, forKey: .lifecycle)
        try values.encode(lifecycleVersion, forKey: .lifecycleVersion)
        try values.encode(schemaVersion, forKey: .schemaVersion)
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
