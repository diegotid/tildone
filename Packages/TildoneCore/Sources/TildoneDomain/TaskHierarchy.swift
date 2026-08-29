//
//  TaskHierarchy.swift
//  TildoneDomain
//

public struct TaskSubtaskProgress: Equatable, Sendable {
    public let completedCount: Int
    public let totalCount: Int

    public init(completedCount: Int, totalCount: Int) {
        self.completedCount = completedCount
        self.totalCount = totalCount
    }

    public var fraction: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }
}

public enum TaskHierarchy {
    public static func hasSubtasks(at index: Int, in tasks: [Task]) -> Bool {
        guard tasks.indices.contains(index), index + 1 < tasks.endIndex else { return false }
        return tasks[index + 1].indentLevel > tasks[index].indentLevel
    }

    public static func subtaskProgress(at index: Int, in tasks: [Task]) -> TaskSubtaskProgress? {
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

    public static func leafTasks(in tasks: [Task]) -> [Task] {
        tasks.enumerated().compactMap { index, task in
            hasSubtasks(at: index, in: tasks) ? nil : task
        }
    }

    public static func subtreeRange(startingAt index: Int, in tasks: [Task]) -> Range<Int> {
        guard tasks.indices.contains(index) else { return index..<index }
        let depth = tasks[index].indentLevel
        let end = tasks[(index + 1)...].firstIndex { $0.indentLevel <= depth } ?? tasks.endIndex
        return index..<end
    }

    public static func parentID(at index: Int, in tasks: [Task]) -> TaskID? {
        guard tasks.indices.contains(index), tasks[index].indentLevel > 0 else { return nil }
        let parentLevel = tasks[index].indentLevel - 1
        return tasks[..<index].last(where: { $0.indentLevel == parentLevel })?.id
    }

    public static func isValidPreorder(_ tasks: [Task]) -> Bool {
        guard let first = tasks.first else { return true }
        guard first.indentLevel == 0 else { return false }
        return zip(tasks, tasks.dropFirst()).allSatisfy { previous, task in
            task.indentLevel <= previous.indentLevel + 1
        }
    }
}
