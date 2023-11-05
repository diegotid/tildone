//
//  Task.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import Foundation
import SwiftData

@Model
final class Task {
    var done: Bool
    var order: Int
    var statement: String
    
    @Relationship
    var topic: Topic?

    public init(order: Int, statement: String) {
        self.done = false
        self.order = order
        self.statement = statement
    }
}
