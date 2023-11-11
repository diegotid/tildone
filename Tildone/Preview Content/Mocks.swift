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
        list.items = [
            Todo("First task", order: 1),
            Todo("Second task", order: 2)
        ]
        
        return list
    }()
}
