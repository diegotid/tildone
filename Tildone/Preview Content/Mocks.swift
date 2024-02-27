//
//  Mocks.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

extension TodoList {
    static var preview = {
        let list = TodoList()
        list.topic = "Mock list"
        list.items = [.oneTask, .anotherTask]
        return list
    }()
}

extension Todo {
    static var oneTask = {
        let task = Todo("First task", at: 0)
        task.setDone()
        return task
    }()
    static var anotherTask = {
        let task = Todo("Second task", at: 1)
        task.setDone()
        return task
    }()
}
