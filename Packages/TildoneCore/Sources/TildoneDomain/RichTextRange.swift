//
//  RichTextRange.swift
//  Tildone
//

public struct RichTextRange: Codable, Hashable, Sendable {
    public let location: Int
    public let length: Int

    public var upperBound: Int {
        let (value, overflow) = location.addingReportingOverflow(length)
        return overflow ? Int.max : value
    }
    public var isEmpty: Bool { length == 0 }

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}
