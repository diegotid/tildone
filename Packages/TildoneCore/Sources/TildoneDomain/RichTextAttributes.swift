//
//  RichTextAttributes.swift
//  Tildone
//

/// String-backed attribute payloads deliberately retain names unknown to this
/// client. Future clients may add styles or palette entries without an older
/// client deleting them merely by decoding and re-encoding unchanged content.
public struct RichTextAttributes: Codable, Hashable, Sendable {
    public private(set) var styleNames: [String]
    public var foregroundColorName: String?
    public var highlightColorName: String?
    public var extensions: [String: String]

    public var styles: Set<RichTextStyle> {
        Set(styleNames.compactMap(RichTextStyle.init(rawValue:)))
    }

    public var foregroundColor: RichTextColor? {
        foregroundColorName.flatMap(RichTextColor.init(rawValue:))
    }

    public var highlightColor: RichTextColor? {
        highlightColorName.flatMap(RichTextColor.init(rawValue:))
    }

    public var isEmpty: Bool {
        styleNames.isEmpty && foregroundColorName == nil
            && highlightColorName == nil && extensions.isEmpty
    }

    public init(
        styles: Set<RichTextStyle> = [],
        foregroundColor: RichTextColor? = nil,
        highlightColor: RichTextColor? = nil,
        extensions: [String: String] = [:]
    ) {
        styleNames = styles.map(\.rawValue).sorted()
        foregroundColorName = foregroundColor?.rawValue
        highlightColorName = highlightColor?.rawValue
        self.extensions = extensions
    }

    public init(
        styleNames: [String],
        foregroundColorName: String? = nil,
        highlightColorName: String? = nil,
        extensions: [String: String] = [:]
    ) {
        self.styleNames = Array(Set(styleNames)).sorted()
        self.foregroundColorName = foregroundColorName
        self.highlightColorName = highlightColorName
        self.extensions = extensions
    }

    public func contains(_ style: RichTextStyle) -> Bool {
        styleNames.contains(style.rawValue)
    }

    func setting(_ style: RichTextStyle, enabled: Bool) -> Self {
        var names = Set(styleNames)
        if enabled { names.insert(style.rawValue) } else { names.remove(style.rawValue) }
        return Self(
            styleNames: Array(names),
            foregroundColorName: foregroundColorName,
            highlightColorName: highlightColorName,
            extensions: extensions
        )
    }

    func settingForeground(_ color: RichTextColor?) -> Self {
        Self(
            styleNames: styleNames,
            foregroundColorName: color?.rawValue,
            highlightColorName: highlightColorName,
            extensions: extensions
        )
    }

    func settingHighlight(_ color: RichTextColor?) -> Self {
        Self(
            styleNames: styleNames,
            foregroundColorName: foregroundColorName,
            highlightColorName: color?.rawValue,
            extensions: extensions
        )
    }

    func overlaying(_ other: Self) -> Self {
        var names = Set(styleNames)
        names.formUnion(other.styleNames)
        var mergedExtensions = extensions
        mergedExtensions.merge(other.extensions) { _, new in new }
        return Self(
            styleNames: Array(names),
            foregroundColorName: other.foregroundColorName ?? foregroundColorName,
            highlightColorName: other.highlightColorName ?? highlightColorName,
            extensions: mergedExtensions
        )
    }
}
