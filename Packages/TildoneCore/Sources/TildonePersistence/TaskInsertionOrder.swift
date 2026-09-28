import TildoneDomain

/// Makes room at a visible insertion boundary, including tied positions from
/// concurrent edits. Only the tied prefix before the new row is retokened.
public struct TaskInsertionOrder: Sendable {
    public let token: OrderToken
    public let updates: [TaskStructureUpdate]

    public static func plan(at position: Int, in tasks: [Task]) throws -> Self {
        guard position >= 0, position <= tasks.count else { throw PersistenceError.domainInvariant }
        let lower = position > 0 ? tasks[position - 1].orderToken : nil
        let upper = position < tasks.count ? tasks[position].orderToken : nil
        guard let lower, let upper, lower == upper else {
            return Self(token: try OrderToken.between(lower, upper), updates: [])
        }
        var start = position - 1
        while start > 0, tasks[start - 1].orderToken == upper { start -= 1 }
        var previous = start > 0 ? tasks[start - 1].orderToken : nil
        var updates: [TaskStructureUpdate] = []
        for task in tasks[start..<position] {
            let token = try OrderToken.between(previous, upper)
            updates.append(TaskStructureUpdate(id: task.id, orderToken: token))
            previous = token
        }
        return Self(token: try OrderToken.between(previous, upper), updates: updates)
    }
}
