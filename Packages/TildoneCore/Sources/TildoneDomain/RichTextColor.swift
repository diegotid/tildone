//
//  RichTextColor.swift
//  Tildone
//

public enum RichTextColor: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink
    case gray

    public var id: Self { self }
}
