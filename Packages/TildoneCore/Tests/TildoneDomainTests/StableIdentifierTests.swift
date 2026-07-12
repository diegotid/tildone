//
//  StableIdentifierTests.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
import Foundation
import XCTest
@testable import TildoneDomain

final class StableIdentifierTests: XCTestCase {
    private let uuid = testUUID("01234567-89AB-CDEF-0123-456789ABCDEF")

    func testNoteIdentifierHasCanonicalPersistenceAndRecordRepresentations() throws {
        let id = NoteID(uuid)

        XCTAssertEqual(id.stringValue, "01234567-89ab-cdef-0123-456789abcdef")
        XCTAssertEqual(id.recordName, "note-01234567-89ab-cdef-0123-456789abcdef")
        XCTAssertEqual(NoteID(string: id.stringValue), id)
        XCTAssertEqual(NoteID(recordName: id.recordName), id)
        XCTAssertNil(NoteID(recordName: TaskID(uuid).recordName))

        let data = try JSONEncoder().encode(id)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"01234567-89ab-cdef-0123-456789abcdef\"")
        XCTAssertEqual(try JSONDecoder().decode(NoteID.self, from: data), id)
    }

    func testTaskIdentifierRoundTripsAndContainsNoContent() throws {
        let id = TaskID(uuid)
        XCTAssertEqual(TaskID(recordName: id.recordName), id)
        XCTAssertEqual(try JSONDecoder().decode(TaskID.self, from: JSONEncoder().encode(id)), id)
        XCTAssertFalse(id.recordName.contains("private task"))
    }

    func testReplicaIdentifierRoundTripsAndOrdersDeterministically() throws {
        let lower = ReplicaID(testUUID("00000000-0000-0000-0000-000000000001"))
        let upper = ReplicaID(testUUID("00000000-0000-0000-0000-000000000002"))

        XCTAssertLessThan(lower, upper)
        let data = try JSONEncoder().encode(lower)
        XCTAssertEqual(try JSONDecoder().decode(ReplicaID.self, from: data), lower)
    }
}
