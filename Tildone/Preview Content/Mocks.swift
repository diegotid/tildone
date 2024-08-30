//
//  Mocks.swift
//  Tildone
//
//  Created by Diego Rivera on 5/11/23.
//

import SwiftUI

extension TodoList {
    static var preview = {
        let list = TodoList()
        list.topic = "Mock list"
        list.items = [.oneTask, .anotherTask, .undoneTask]
        list.systemURL = URL(string: "http://cuatro.studio")
        list.systemContent = """
        Tildone has been updated featuring now:
        \u{2022} Open at login
        \u{2022} Focus filters
        \u{2022} Arrange notes
        \u{2022} Spanish, French and Chinese
        \u{2022} Several other improvements
        """
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
    static var undoneTask = {
        let task = Todo("Undone task", at: 2)
        return task
    }()
}
