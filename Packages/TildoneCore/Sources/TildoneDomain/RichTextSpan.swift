//
//  RichTextSpan.swift
//  Tildone
//

public struct RichTextSpan: Codable, Hashable, Sendable {
    public let range: RichTextRange
    public let attributes: RichTextAttributes

    public init(range: RichTextRange, attributes: RichTextAttributes) {
        self.range = range
        self.attributes = attributes
    }
}
