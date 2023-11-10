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
    var order: Int
    var done: Bool

    @Relationship
    var list: TodoList?

    public init(_ what: String, order: Int) {
        self.what = what
        self.order = order
        self.done = false
    }
}
