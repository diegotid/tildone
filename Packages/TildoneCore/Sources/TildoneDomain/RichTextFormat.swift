//
//  RichTextFormat.swift
//  Tildone
//

public enum RichTextFormat: Hashable, Sendable {
    case toggle(RichTextStyle)
    case foreground(RichTextColor?)
    case highlight(RichTextColor?)
}
