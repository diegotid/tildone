//
//  TodoList.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import Foundation
import SwiftData

@Model
final class TodoList {
    var created: Date
    var title: String?
    
    @Relationship(inverse:\Todo.list)
    var items: [Todo]

    public init() {
        self.created = Date()
        self.items = []
    }
}
