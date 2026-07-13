//
//  TildoneTests.swift
//  TildoneTests
//

import XCTest
import TildoneDomain
import TildonePersistence
@testable import Tildone

final class TildoneTests: XCTestCase {
    func testMacSharedStoreRoutesCRUDThroughDomainRepository() async throws {
        let repository = try TildoneRepository(
            descriptor: .inMemory(),
            replicaID: ReplicaID(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!),
            now: { Date(timeIntervalSince1970: 2_000) }
        )
        let store = await MainActor.run { MacSharedStore(repository: repository) }

        let note = try await store.createNote(createdAt: Date(timeIntervalSince1970: 100))
        try await store.renameNote(note.id, to: "Title")
        let last = try await store.addTask(to: note.id, text: "Last")
        let first = try await store.addTask(to: note.id, text: "First", insertingAt: 0)
        try await store.setTaskCompletion(first.id, completed: true)
        try await store.editTask(last.id, text: "Changed")

        let loadedSnapshot = await MainActor.run { store.note(note.id) }
        let snapshot = try XCTUnwrap(loadedSnapshot)
        XCTAssertEqual(snapshot.title, "Title")
        XCTAssertEqual(snapshot.tasks.map(\.text), ["First", "Changed"])
        XCTAssertEqual(snapshot.pendingTasks.map(\.id), [last.id])

        try await store.deleteTask(first.id)
        try await store.deleteTask(last.id)
        try await store.renameNote(note.id, to: nil)
        let loadedEmpty = await MainActor.run { store.note(note.id) }
        let empty = try XCTUnwrap(loadedEmpty)
        XCTAssertTrue(empty.isDeletable)
        try await store.deleteNote(note.id)
        let remaining = try await repository.visibleNotes()
        XCTAssertTrue(remaining.isEmpty)
    }
}
