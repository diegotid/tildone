//
//  RichText.swift
//  Tildone
//
//  Platform-neutral task rich text. Offsets use UTF-16 so they round-trip
//  exactly through AppKit, UIKit and CloudKit without archiving either UI
//  framework's attributed-string representation.
//
import Foundation

public struct RichText: Codable, Hashable, Sendable {
    public static let currentRepresentationVersion = 1

    public let representationVersion: Int
    public let text: String
    public let spans: [RichTextSpan]

    public var utf16Count: Int { text.utf16.count }
    public var isPlain: Bool { spans.isEmpty }

    public init(
        text: String,
        spans: [RichTextSpan] = [],
        representationVersion: Int = RichText.currentRepresentationVersion
    ) {
        self.representationVersion = max(1, representationVersion)
        self.text = text
        self.spans = Self.normalize(spans, in: text)
    }

    private enum CodingKeys: String, CodingKey {
        case representationVersion, text, spans
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let representationVersion = try values.decode(Int.self, forKey: .representationVersion)
        guard representationVersion >= 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .representationVersion,
                in: values,
                debugDescription: "Rich-text representation version must be positive"
            )
        }
        self.init(
            text: try values.decode(String.self, forKey: .text),
            spans: try values.decode([RichTextSpan].self, forKey: .spans),
            representationVersion: representationVersion
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(representationVersion, forKey: .representationVersion)
        try values.encode(text, forKey: .text)
        try values.encode(spans, forKey: .spans)
    }

    public func attributes(atUTF16Offset offset: Int) -> RichTextAttributes {
        guard offset >= 0, offset < utf16Count else { return RichTextAttributes() }
        return spans.first {
            $0.range.location <= offset && offset < $0.range.upperBound
        }?.attributes ?? RichTextAttributes()
    }

    /// Retains the Mac app's fast-capture capitalization behavior. Unicode
    /// expansions are left unchanged because changing UTF-16 length would make
    /// an in-flight native selection ambiguous.
    public func capitalizingFirstLetter() -> Self {
        guard let first = text.first else { return self }
        let uppercase = String(first).uppercased()
        guard uppercase != String(first), uppercase.utf16.count == String(first).utf16.count else {
            return self
        }
        return Self(
            text: uppercase + text.dropFirst(),
            spans: spans,
            representationVersion: representationVersion
        )
    }

    public func trimmingCharacters(in set: CharacterSet) -> Self {
        let trimmedText = text.trimmingCharacters(in: set)
        guard trimmedText != text else { return self }
        guard !trimmedText.isEmpty,
              let retainedRange = text.range(of: trimmedText) else {
            return Self(text: "", representationVersion: representationVersion)
        }

        let retained = NSRange(retainedRange, in: text)
        let adjustedSpans = spans.compactMap { span -> RichTextSpan? in
            let lower = max(span.range.location, retained.location)
            let upper = min(span.range.upperBound, NSMaxRange(retained))
            guard lower < upper else { return nil }
            return RichTextSpan(
                range: RichTextRange(
                    location: lower - retained.location,
                    length: upper - lower
                ),
                attributes: span.attributes
            )
        }
        return Self(
            text: trimmedText,
            spans: adjustedSpans,
            representationVersion: representationVersion
        )
    }

    /// Applies a format to a native selection. A collapsed selection expands
    /// to the word containing the caret (or immediately preceding it when the
    /// caret is at the word's trailing edge). Whitespace-only carets are no-ops.
    public func applying(_ format: RichTextFormat, to selection: RichTextRange) -> Self {
        guard let target = resolvedFormattingRange(for: selection), !target.isEmpty else {
            return self
        }

        let boundaries = Set(
            [0, utf16Count, target.location, target.upperBound]
                + spans.flatMap { [$0.range.location, $0.range.upperBound] }
        ).sorted()
        let targetIntervals = zip(boundaries, boundaries.dropFirst()).filter {
            $0.0 >= target.location && $0.1 <= target.upperBound && $0.0 < $0.1
        }
        let removesStyle: Bool
        if case let .toggle(style) = format {
            removesStyle = !targetIntervals.isEmpty && targetIntervals.allSatisfy {
                attributes(atUTF16Offset: $0.0).contains(style)
            }
        } else {
            removesStyle = false
        }

        var result: [RichTextSpan] = []
        for (lower, upper) in zip(boundaries, boundaries.dropFirst()) where lower < upper {
            var attributes = attributes(atUTF16Offset: lower)
            if lower >= target.location, upper <= target.upperBound {
                switch format {
                case let .toggle(style):
                    attributes = attributes.setting(style, enabled: !removesStyle)
                case let .foreground(color):
                    attributes = attributes.settingForeground(color)
                case let .highlight(color):
                    attributes = attributes.settingHighlight(color)
                }
            }
            guard !attributes.isEmpty else { continue }
            result.append(RichTextSpan(
                range: RichTextRange(location: lower, length: upper - lower),
                attributes: attributes
            ))
        }
        return Self(text: text, spans: result, representationVersion: representationVersion)
    }

    public func resolvedFormattingRange(for selection: RichTextRange) -> RichTextRange? {
        guard selection.location >= 0, selection.length >= 0,
              selection.location <= utf16Count else { return nil }
        if selection.length > 0 {
            let upper = selection.location + min(
                selection.length,
                utf16Count - selection.location
            )
            guard upper > selection.location else { return nil }
            let range = NSRange(location: selection.location, length: upper - selection.location)
            let composed = (text as NSString).rangeOfComposedCharacterSequences(for: range)
            return RichTextRange(location: composed.location, length: composed.length)
        }
        return wordRange(atUTF16Offset: selection.location)
    }

    private func wordRange(atUTF16Offset offset: Int) -> RichTextRange? {
        guard !text.isEmpty, let fullRange = Range(NSRange(location: 0, length: utf16Count), in: text) else {
            return nil
        }
        var containing: RichTextRange?
        var trailing: RichTextRange?
        text.enumerateSubstrings(in: fullRange, options: [.byWords, .substringNotRequired]) {
            _, range, _, stop in
            let nsRange = NSRange(range, in: text)
            if nsRange.location <= offset && offset < NSMaxRange(nsRange) {
                containing = RichTextRange(location: nsRange.location, length: nsRange.length)
                stop = true
            } else if NSMaxRange(nsRange) == offset {
                trailing = RichTextRange(location: nsRange.location, length: nsRange.length)
            }
        }
        return containing ?? trailing
    }

    private static func normalize(_ spans: [RichTextSpan], in text: String) -> [RichTextSpan] {
        let length = text.utf16.count
        guard length > 0 else { return [] }
        let string = text as NSString
        let valid: [(range: NSRange, attributes: RichTextAttributes)] = spans.compactMap { span in
            guard span.range.location >= 0, span.range.length > 0,
                  span.range.location < length, !span.attributes.isEmpty else { return nil }
            let upper = span.range.location + min(
                span.range.length,
                length - span.range.location
            )
            guard upper > span.range.location else { return nil }
            let composed = string.rangeOfComposedCharacterSequences(
                for: NSRange(location: span.range.location, length: upper - span.range.location)
            )
            guard composed.length > 0 else { return nil }
            return (
                composed,
                RichTextAttributes(
                    styleNames: span.attributes.styleNames,
                    foregroundColorName: span.attributes.foregroundColorName,
                    highlightColorName: span.attributes.highlightColorName,
                    extensions: span.attributes.extensions
                )
            )
        }
        guard !valid.isEmpty else { return [] }

        let boundaries = Set(valid.flatMap { [$0.range.location, NSMaxRange($0.range)] }).sorted()
        var normalized: [RichTextSpan] = []
        for (lower, upper) in zip(boundaries, boundaries.dropFirst()) where lower < upper {
            var attributes = RichTextAttributes()
            var covered = false
            for span in valid where span.range.location <= lower && upper <= NSMaxRange(span.range) {
                attributes = attributes.overlaying(span.attributes)
                covered = true
            }
            guard covered, !attributes.isEmpty else { continue }
            if let last = normalized.last,
               last.range.upperBound == lower,
               last.attributes == attributes {
                normalized[normalized.count - 1] = RichTextSpan(
                    range: RichTextRange(
                        location: last.range.location,
                        length: upper - last.range.location
                    ),
                    attributes: attributes
                )
            } else {
                normalized.append(RichTextSpan(
                    range: RichTextRange(location: lower, length: upper - lower),
                    attributes: attributes
                ))
            }
        }
        return normalized
    }
}
