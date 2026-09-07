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
                    text: $0.text,
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
        let text: String
        let indentLevel: Int
        let isCompleted: Bool
    }

    private static func makeMarkdown(title: String?, lines: [ClipboardLine]) -> String {
        let taskLines = lines.map { line in
            let checked = line.isCompleted ? "x" : " "
            return "\(String(repeating: "  ", count: max(0, line.indentLevel)))- [\(checked)] \(line.text)"
        }
        return ([title].compactMap { $0 } + taskLines).joined(separator: "\n")
    }

    private static func makeHTML(title: String?, lines: [ClipboardLine]) -> String {
        let titleHTML = title.map { "<strong>\(escapeHTML($0))</strong>" } ?? ""
        let items = lines.map { line in
            let completed = line.isCompleted ? "<s>\(escapeHTML(line.text))</s>" : escapeHTML(line.text)
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
            result.append(NSAttributedString(
                string: "• \(line.text)\n",
                attributes: [
                    .paragraphStyle: paragraph,
                    .strikethroughStyle: line.isCompleted ? NSUnderlineStyle.single.rawValue : 0
                ]
            ))
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
