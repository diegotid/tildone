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
    var done: Date?

    @Relationship
    var list: TodoList?
    
    var isDone: Bool {
        self.done != nil
    }

    public init(_ what: String) {
        self.created = Date()
        self.what = what
    }
    
    func setDone(_ done: Bool? = true) {
        if done == false {
            self.done = nil
        } else {
            self.done = Date()
        }
    }
}
