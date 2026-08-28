//
//  TaskHierarchy.swift
//  Tildone
//

import TildoneDomain

struct TaskSubtaskProgress: Equatable {
    let completedCount: Int
    let totalCount: Int

    var fraction: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }
}

enum TaskHierarchy {
    static func hasSubtasks(at index: Int, in tasks: [Task]) -> Bool {
        guard tasks.indices.contains(index), index + 1 < tasks.endIndex else { return false }
        return tasks[index + 1].indentLevel > tasks[index].indentLevel
    }

    static func subtaskProgress(at index: Int, in tasks: [Task]) -> TaskSubtaskProgress? {
        guard hasSubtasks(at: index, in: tasks) else { return nil }
        let parentDepth = tasks[index].indentLevel
        let descendants = tasks[(index + 1)...].prefix { $0.indentLevel > parentDepth }
        let leaves = descendants.enumerated().filter { offset, task in
            let nextIndex = index + 2 + offset
            return nextIndex == tasks.endIndex || tasks[nextIndex].indentLevel <= task.indentLevel
        }.map(\.element)
        return TaskSubtaskProgress(
            completedCount: leaves.lazy.filter(\.isCompleted).count,
            totalCount: leaves.count
        )
    }

    static func leafTasks(in tasks: [Task]) -> [Task] {
        tasks.enumerated().compactMap { index, task in
            hasSubtasks(at: index, in: tasks) ? nil : task
        }
    }

    static func subtreeRange(startingAt index: Int, in tasks: [Task]) -> Range<Int> {
        guard tasks.indices.contains(index) else { return index..<index }
        let depth = tasks[index].indentLevel
        let end = tasks[(index + 1)...].firstIndex { $0.indentLevel <= depth } ?? tasks.endIndex
        return index..<end
    }
}
