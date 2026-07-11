import Foundation

/// A stable, content-free identifier for a note.
public struct NoteID: Codable, Hashable, Comparable, Sendable {
    public static let recordNamePrefix = "note-"

    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init?(string: String) {
        guard let value = UUID(uuidString: string) else { return nil }
        self.init(value)
    }

    public init?(recordName: String) {
        guard recordName.hasPrefix(Self.recordNamePrefix) else { return nil }
        self.init(string: String(recordName.dropFirst(Self.recordNamePrefix.count)))
    }

    /// A canonical, deterministic representation suitable for persistence.
    public var stringValue: String { rawValue.uuidString.lowercased() }

    /// A deterministic future CloudKit record name containing no user content.
    public var recordName: String { Self.recordNamePrefix + stringValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.stringValue < rhs.stringValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = Self(string: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid note identifier")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

/// A stable, content-free identifier for a task.
public struct TaskID: Codable, Hashable, Comparable, Sendable {
    public static let recordNamePrefix = "task-"

    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init?(string: String) {
        guard let value = UUID(uuidString: string) else { return nil }
        self.init(value)
    }

    public init?(recordName: String) {
        guard recordName.hasPrefix(Self.recordNamePrefix) else { return nil }
        self.init(string: String(recordName.dropFirst(Self.recordNamePrefix.count)))
    }

    public var stringValue: String { rawValue.uuidString.lowercased() }

    public var recordName: String { Self.recordNamePrefix + stringValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.stringValue < rhs.stringValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = Self(string: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid task identifier")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}

/// A stable installation identifier used only to disambiguate logical versions.
public struct ReplicaID: Codable, Hashable, Comparable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init?(string: String) {
        guard let value = UUID(uuidString: string) else { return nil }
        self.init(value)
    }

    public var stringValue: String { rawValue.uuidString.lowercased() }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.stringValue < rhs.stringValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = Self(string: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid replica identifier")
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}
