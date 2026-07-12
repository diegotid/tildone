//
//  OrderTokenTests.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
import Foundation
import XCTest
@testable import TildoneDomain

final class OrderTokenTests: XCTestCase {
    func testCreatesTokensAtAllBoundaries() throws {
        let middle = try OrderToken.between(nil, nil)
        let before = OrderToken.before(middle)
        let after = OrderToken.after(middle)
        let between = try OrderToken.between(middle, after)

        XCTAssertLessThan(before, middle)
        XCTAssertLessThan(middle, between)
        XCTAssertLessThan(between, after)
    }

    func testRepeatedInsertionRemainsStrictlyBetweenPrefixAdjacentTokens() throws {
        let lower = try OrderToken(rawValue: "a")
        var upper = try OrderToken(rawValue: "a1")

        for _ in 0..<200 {
            let inserted = try OrderToken.between(lower, upper)
            XCTAssertLessThan(lower, inserted)
            XCTAssertLessThan(inserted, upper)
            upper = inserted
        }
    }

    func testPropertyStyleInsertionMaintainsStrictSortedOrder() throws {
        var generator = DeterministicGenerator(state: 0xC0FFEE)
        var tokens: [OrderToken] = []

        for _ in 0..<1_000 {
            let insertionIndex = Int(generator.next() % UInt64(tokens.count + 1))
            let lower = insertionIndex == 0 ? nil : tokens[insertionIndex - 1]
            let upper = insertionIndex == tokens.count ? nil : tokens[insertionIndex]
            let token = try OrderToken.between(lower, upper)
            tokens.insert(token, at: insertionIndex)
        }

        XCTAssertEqual(tokens, tokens.sorted())
        XCTAssertEqual(Set(tokens).count, tokens.count)
        for pair in zip(tokens, tokens.dropFirst()) {
            XCTAssertLessThan(pair.0, pair.1)
        }
    }

    func testRejectsMalformedTokensAndInvalidBounds() throws {
        XCTAssertThrowsError(try OrderToken(rawValue: ""))
        XCTAssertThrowsError(try OrderToken(rawValue: "A"))
        XCTAssertThrowsError(try OrderToken(rawValue: "a0"))

        let lower = try OrderToken(rawValue: "b")
        let upper = try OrderToken(rawValue: "a")
        XCTAssertThrowsError(try OrderToken.between(lower, upper)) { error in
            XCTAssertEqual(error as? OrderTokenError, .invalidBounds)
        }
        XCTAssertThrowsError(try OrderToken.between(lower, lower))
    }

    func testLongTokensAreValidButSignalFutureMaintenance() throws {
        let normal = try OrderToken(rawValue: String(repeating: "1", count: OrderToken.recommendedMaximumLength))
        let long = try OrderToken(rawValue: String(repeating: "1", count: OrderToken.recommendedMaximumLength + 1))

        XCTAssertFalse(normal.exceedsRecommendedMaximumLength)
        XCTAssertTrue(long.exceedsRecommendedMaximumLength)
    }

    func testEqualTokenFallsBackToStableTaskIdentifier() throws {
        let token = try OrderToken(rawValue: "h")
        let first = makeTask(idSuffix: 1, token: token)
        let second = makeTask(idSuffix: 2, token: token)

        XCTAssertTrue(Task.orderedBefore(first, second))
        XCTAssertFalse(Task.orderedBefore(second, first))
    }

    private func makeTask(idSuffix: Int, token: OrderToken) -> Task {
        let id = TaskID(testUUID(String(format: "00000000-0000-0000-0000-%012d", idSuffix)))
        let noteID = NoteID(testUUID("10000000-0000-0000-0000-000000000000"))
        let replica = ReplicaID(testUUID("20000000-0000-0000-0000-000000000000"))
        let version = VersionStamp(logicalCounter: 1, replicaID: replica)
        return Task(
            id: id,
            noteID: noteID,
            createdAt: .distantPast,
            text: "",
            textVersion: version,
            completionVersion: version,
            orderToken: token,
            orderVersion: version,
            lifecycleVersion: version
        )
    }
}

private struct DeterministicGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
