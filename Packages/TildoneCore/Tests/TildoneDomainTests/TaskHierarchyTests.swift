import XCTest
@testable import TildoneDomain

final class TaskHierarchyTests: XCTestCase {
    func testRecursiveLeavesProgressSubtreesAndParentsShareOnePreorderModel() throws {
        let root = try task(token: "b", level: 0)
        let nestedParent = try task(token: "d", level: 1)
        let grandchild = try task(token: "f", level: 2, completed: true)
        let sibling = try task(token: "h", level: 1)
        let otherRoot = try task(token: "j", level: 0, completed: true)
        let tasks = [root, nestedParent, grandchild, sibling, otherRoot]

        XCTAssertTrue(TaskHierarchy.isValidPreorder(tasks))
        XCTAssertTrue(TaskHierarchy.hasSubtasks(at: 0, in: tasks))
        XCTAssertTrue(TaskHierarchy.hasSubtasks(at: 1, in: tasks))
        XCTAssertFalse(TaskHierarchy.hasSubtasks(at: 2, in: tasks))
        XCTAssertEqual(
            TaskHierarchy.leafTasks(in: tasks).map(\.id),
            [grandchild.id, sibling.id, otherRoot.id]
        )
        XCTAssertEqual(
            TaskHierarchy.subtaskProgress(at: 0, in: tasks),
            TaskSubtaskProgress(completedCount: 1, totalCount: 2)
        )
        XCTAssertEqual(
            TaskHierarchy.subtaskProgress(at: 1, in: tasks),
            TaskSubtaskProgress(completedCount: 1, totalCount: 1)
        )
        XCTAssertEqual(TaskHierarchy.subtreeRange(startingAt: 0, in: tasks), 0..<4)
        XCTAssertEqual(TaskHierarchy.subtreeRange(startingAt: 1, in: tasks), 1..<3)
        XCTAssertEqual(TaskHierarchy.parentID(at: 1, in: tasks), root.id)
        XCTAssertEqual(TaskHierarchy.parentID(at: 2, in: tasks), nestedParent.id)
        XCTAssertEqual(TaskHierarchy.parentID(at: 3, in: tasks), root.id)
        XCTAssertNil(TaskHierarchy.parentID(at: 4, in: tasks))
    }

    func testPreorderValidationRejectsOrphansAndSkippedLevels() throws {
        XCTAssertFalse(TaskHierarchy.isValidPreorder([
            try task(token: "b", level: 1),
        ]))
        XCTAssertFalse(TaskHierarchy.isValidPreorder([
            try task(token: "b", level: 0),
            try task(token: "d", level: 2),
        ]))
    }

    private func task(token: String, level: Int, completed: Bool = false) throws -> Task {
        let stamp = VersionStamp(logicalCounter: 1, replicaID: ReplicaID())
        return Task(
            id: TaskID(),
            noteID: NoteID(),
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            text: token,
            textVersion: stamp,
            completion: completed ? .completed(at: Date(timeIntervalSinceReferenceDate: 1)) : .incomplete,
            completionVersion: stamp,
            orderToken: try OrderToken(rawValue: token),
            orderVersion: stamp,
            indentLevel: level,
            indentVersion: stamp,
            lifecycleVersion: stamp
        )
    }
}
