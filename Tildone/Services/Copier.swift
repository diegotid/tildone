//
//  Copier.swift
//  Tildone
//
//  Created by Diego Rivera on 14/1/24.
//

import AppKit

struct Copier {
    
    static func copy(_ content: String, forType type: NSPasteboard.PasteboardType) {
        NSPasteboard.general.clearContents()
        switch type {
        case .string:
            NSPasteboard.general.setString(content, forType: .string)
        default:
            NSPasteboard.general.setData(content.data(using: .utf8)!, forType: type)
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
