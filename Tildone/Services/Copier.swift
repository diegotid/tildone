//
//  Copier.swift
//  Tildone
//
//  Created by Diego Rivera on 14/1/24.
//

import AppKit
import TildoneDomain

struct Copier {

    private static let markdownType = NSPasteboard.PasteboardType("net.daringfireball.markdown")
    
    static func copy(_ content: String, forType type: NSPasteboard.PasteboardType) {
        NSPasteboard.general.clearContents()
        switch type {
        case .string:
            NSPasteboard.general.setString(content, forType: .string)
        default:
            NSPasteboard.general.setData(content.data(using: .utf8)!, forType: type)
        }
    }

    static func copyNoteContents(title: String?, tasks: [Task]) {
        let content = NoteClipboardContent(title: title, tasks: tasks)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content.plainText, forType: .string)
        pasteboard.setData(content.html.data(using: .utf8), forType: .html)
        pasteboard.setData(content.rtf, forType: .rtf)
        pasteboard.setString(content.markdown, forType: markdownType)
    }
}

struct NoteClipboardContent {
    let plainText: String
    let markdown: String
    let html: String
    let rtf: Data

    init(title: String?, tasks: [Task]) {
        self.init(
            title: title,
            lines: tasks.map {
                ClipboardLine(
                    richText: $0.richText,
                    indentLevel: $0.indentLevel,
                    isCompleted: $0.isCompleted
                )
            }
        )
    }

    init(title: String?, lines: [ClipboardLine]) {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTitle = title?.isEmpty == false ? title : nil

        markdown = Self.makeMarkdown(title: normalizedTitle, lines: lines)
        plainText = markdown
        html = Self.makeHTML(title: normalizedTitle, lines: lines)
        rtf = Self.makeRTF(title: normalizedTitle, lines: lines)
    }

    struct ClipboardLine {
        let richText: RichText
        let indentLevel: Int
        let isCompleted: Bool

        var text: String { richText.text }

        init(richText: RichText, indentLevel: Int, isCompleted: Bool) {
            self.richText = richText
            self.indentLevel = indentLevel
            self.isCompleted = isCompleted
        }

        init(text: String, indentLevel: Int, isCompleted: Bool) {
            self.init(
                richText: RichText(text: text),
                indentLevel: indentLevel,
                isCompleted: isCompleted
            )
        }
    }

    private static func makeMarkdown(title: String?, lines: [ClipboardLine]) -> String {
        let taskLines = lines.map { line in
            let checked = line.isCompleted ? "x" : " "
            return "\(String(repeating: "  ", count: max(0, line.indentLevel)))- [\(checked)] \(markdown(line.richText))"
        }
        return ([title].compactMap { $0 } + taskLines).joined(separator: "\n")
    }

    private static func makeHTML(title: String?, lines: [ClipboardLine]) -> String {
        let titleHTML = title.map { "<strong>\(escapeHTML($0))</strong>" } ?? ""
        let items = lines.map { line in
            let rich = richHTML(line.richText)
            let completed = line.isCompleted ? "<s>\(rich)</s>" : rich
            let indentation = "margin-left: \(Double(max(0, line.indentLevel)) * 1.5)em;"
            return "<li style=\"\(indentation)\">\(completed)</li>"
        }.joined()
        return "<!doctype html><html><head><meta charset=\"utf-8\"></head><body>\(titleHTML)<ul>\(items)</ul></body></html>"
    }

    private static func makeRTF(title: String?, lines: [ClipboardLine]) -> Data {
        let result = NSMutableAttributedString()
        if let title {
            result.append(NSAttributedString(
                string: "\(title)\n",
                attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
            ))
        }
        for line in lines {
            let paragraph = NSMutableParagraphStyle()
            paragraph.headIndent = CGFloat(max(0, line.indentLevel)) * 20
            let item = NSMutableAttributedString(string: "• ", attributes: [.paragraphStyle: paragraph])
            let content = attributedString(line.richText)
            content.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: content.length))
            if line.isCompleted, content.length > 0 {
                content.addAttribute(
                    .strikethroughStyle,
                    value: NSUnderlineStyle.single.rawValue,
                    range: NSRange(location: 0, length: content.length)
                )
            }
            item.append(content)
            item.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: paragraph]))
            result.append(item)
        }
        return (try? result.data(
            from: NSRange(location: 0, length: result.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )) ?? Data()
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func markdown(_ richText: RichText) -> String {
        segments(in: richText).map { segment in
            var value = segment.text
            if segment.attributes.contains(.bold) { value = "**\(value)**" }
            if segment.attributes.contains(.italic) { value = "*\(value)*" }
            if segment.attributes.contains(.strikethrough) { value = "~~\(value)~~" }
            return value
        }.joined()
    }

    private static func richHTML(_ richText: RichText) -> String {
        let links = detectedLinks(in: richText.text)
        let linkBoundaries = links.flatMap { [$0.range.location, NSMaxRange($0.range)] }
        return segments(in: richText, extraBoundaries: linkBoundaries).map { segment in
            var value = escapeHTML(segment.text)
            if segment.attributes.contains(.bold) { value = "<strong>\(value)</strong>" }
            if segment.attributes.contains(.italic) { value = "<em>\(value)</em>" }
            if segment.attributes.contains(.underline) { value = "<u>\(value)</u>" }
            if segment.attributes.contains(.strikethrough) { value = "<s>\(value)</s>" }
            var styles: [String] = []
            if let color = segment.attributes.foregroundColor {
                styles.append("color: \(hex(color));")
            }
            if let color = segment.attributes.highlightColor {
                styles.append("background-color: \(hex(color));")
            }
            if !styles.isEmpty { value = "<span style=\"\(styles.joined(separator: " "))\">\(value)</span>" }
            if let link = links.first(where: {
                $0.range.location <= segment.range.location
                    && segment.range.upperBound <= NSMaxRange($0.range)
            }) {
                value = "<a href=\"\(escapeHTML(link.url.absoluteString))\">\(value)</a>"
            }
            return value
        }.joined()
    }

    private static func attributedString(_ richText: RichText) -> NSMutableAttributedString {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let result = NSMutableAttributedString(string: richText.text, attributes: [.font: font])
        for span in richText.spans {
            let range = NSRange(location: span.range.location, length: span.range.length)
            var traits: NSFontTraitMask = []
            if span.attributes.contains(.bold) { traits.insert(.boldFontMask) }
            if span.attributes.contains(.italic) { traits.insert(.italicFontMask) }
            if !traits.isEmpty {
                result.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: traits), range: range)
            }
            if span.attributes.contains(.underline) {
                result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            if span.attributes.contains(.strikethrough) {
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
            if let color = span.attributes.foregroundColor {
                result.addAttribute(.foregroundColor, value: nsColor(color), range: range)
            }
            if let color = span.attributes.highlightColor {
                result.addAttribute(.backgroundColor, value: nsColor(color).withAlphaComponent(0.34), range: range)
            }
        }
        for link in detectedLinks(in: richText.text) {
            result.addAttribute(.link, value: link.url, range: link.range)
        }
        return result
    }

    private struct Segment {
        let text: String
        let range: RichTextRange
        let attributes: RichTextAttributes
    }

    private static func segments(
        in richText: RichText,
        extraBoundaries: [Int] = []
    ) -> [Segment] {
        let length = richText.utf16Count
        guard length > 0 else { return [] }
        let boundaries = Set(
            [0, length] + extraBoundaries
                + richText.spans.flatMap { [$0.range.location, $0.range.upperBound] }
        ).filter { (0...length).contains($0) }.sorted()
        let string = richText.text as NSString
        return zip(boundaries, boundaries.dropFirst()).compactMap { lower, upper in
            guard lower < upper else { return nil }
            return Segment(
                text: string.substring(with: NSRange(location: lower, length: upper - lower)),
                range: RichTextRange(location: lower, length: upper - lower),
                attributes: richText.attributes(atUTF16Offset: lower)
            )
        }
    }

    private static func detectedLinks(in text: String) -> [(range: NSRange, url: URL)] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        return detector.matches(
            in: text,
            range: NSRange(location: 0, length: text.utf16.count)
        ).compactMap { match in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host?.isEmpty == false else { return nil }
            return (match.range, url)
        }
    }

    private static func hex(_ color: RichTextColor) -> String {
        switch color {
        case .red: "#d70015"
        case .orange: "#c93400"
        case .yellow: "#9d7a00"
        case .green: "#248a3d"
        case .blue: "#0066cc"
        case .purple: "#8944ab"
        case .pink: "#d30f45"
        case .gray: "#6c6c70"
        }
    }

    private static func nsColor(_ color: RichTextColor) -> NSColor {
        switch color {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        case .gray: .systemGray
        }
    }
}

// MARK: Todo extension

extension Todo {

    public func copy() {
        Copier.copy(self.what, forType: .string)
    }
    
    public func paste() {
        guard let clipboard = NSPasteboard.general.string(forType: .string) else {
            return
        }
        let lines = clipboard.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter {
            !$0.isEmpty
        }
        guard let firstLine = lines.first else {
            return
        }
        self.what = firstLine
        if lines.count > 1 {
            self.list?.paste(Array(lines.dropFirst()), from: 1 + (self.index ?? 0))
        }
    }
}

// MARK: TodoList extension

extension TodoList {
    
    public func copy() {
        let tasks: [Todo] = self.items.sorted(by: { $0.created < $1.created })
        let htmlListItems = tasks.reduce("") { list, task in
            "\(list)<li>\(task.what)</li>"
        }
        let htmlTitle: String = (self.topic != nil) ? "<strong>\(topic!)</strong>" : ""
        let htmlList: String = "\(htmlTitle)<ul>\(htmlListItems)</ul>"
        Copier.copy(htmlList, forType: .html)
    }
    
    public func paste(_ content: [String], from index: Int) {
        for line in content.reversed() {
            createNewTask(todo: line, at: index)
        }
    }
}
