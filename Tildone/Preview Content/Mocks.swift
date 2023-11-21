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
        return Todo("First task", order: 1)
    }()
    static var anotherTask = {
        return Todo("Second task", order: 2)
    }()
}
