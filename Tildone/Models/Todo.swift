//
//  Todo.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import Foundation
import SwiftData

@Model
final class Todo {
    var what: String
    var created: Date
    var index: Int?
    var done: Date?

    @Relationship
    var list: TodoList?
    
    var isDone: Bool {
        self.done != nil
    }

    public init(_ what: String, at index: Int) {
        self.created = Date()
        self.what = what
        self.index = index
    }
    
    func setDone(_ done: Bool? = true) {
        if done == false {
            self.done = nil
        } else {
            self.done = Date()
        }
    }
}

extension Array where Element == Todo {
    func sorted() -> [Todo] {
        self.secondaryOrderSorted()
            .mainOrderSorted()
            .indexIfUnindexed()
    }
    
    func maxIndex() -> Int? {
        return self.reduce(0) { max, task in
            (task.index ?? 0) > max ?? 0 ? task.index : max
        }
    }
    
    private func mainOrderSorted() -> [Todo] {
        self.sorted(by: { $0.index ?? Int.max < $1.index ?? Int.max })
    }
    
    private func secondaryOrderSorted() -> [Todo] {
        self.sorted(by: { $0.created < $1.created })
    }
    
    /// Function intended for retrocompatibility as first app versions had unindexed todo lists
    private func indexIfUnindexed() -> [Todo] {
        self.enumerated()
            .map { index, todo in
                if todo.index == nil {
                    todo.index = index
                }
                return todo
            }
    }
}
