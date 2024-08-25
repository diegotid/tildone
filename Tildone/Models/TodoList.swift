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
    var topic: String?
    var systemURL: URL?
    var systemContent: String?
    
    @Relationship(inverse:\Todo.list)
    var items: [Todo]
    
    var isEmpty: Bool {
        items.isEmpty && topic == nil
    }
    var isComplete: Bool {
        !items.isEmpty && items.filter({ !$0.isDone }).isEmpty
    }
    var isDeletable: Bool {
        isComplete || isEmpty
    }
    var hash: String {
        created.ISO8601Format()
    }
    var isSystemList: Bool {
        systemContent != nil
    }

    public init() {
        self.created = Date()
        self.items = []
    }
}

extension TodoList {
    
    func createNewTask(todo: String, at index: Int) {
        leavePlace(at: index)
        let newTask = Todo(todo.capitalizingFirstLetter(), at: index)
        newTask.list = self
        modelContext?.insert(newTask)
        do {
            try modelContext?.save()
        } catch {
            fatalError("Error on task creation: \(error)")
        }
    }
    
    func remove(_ task: Todo) {
        self.items.removeAll(where: { $0.created == task.created })
        flattenIndexes()
    }
    
    func delete() {
        for task in items {
            modelContext?.delete(task)
        }
        modelContext?.delete(self)
        do {
            try modelContext?.save()
        } catch {
            fatalError("Could not delete list: \(error)")
        }
    }
    
    func clean() {
        for task in items {
            if task.what.isEmpty {
                modelContext?.delete(task)
            }
        }
        do {
            try modelContext?.save()
        } catch {
            fatalError("Error on task list cleaning: \(error)")
        }
    }
}

private extension TodoList {
    func leavePlace(at index: Int) {
        for task in items.sorted() {
            guard let currentIndex = task.index else { continue }
            if currentIndex >= index {
                task.index = currentIndex + 1
            }
        }
    }
    
    func flattenIndexes() {
        for (index, task) in items.sorted().enumerated() {
            task.index = index + 1
        }
    }
}
