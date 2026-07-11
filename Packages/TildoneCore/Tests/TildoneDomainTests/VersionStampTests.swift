import Foundation
import XCTest
@testable import TildoneDomain

final class VersionStampTests: XCTestCase {
    private let replicaA = ReplicaID(testUUID("00000000-0000-0000-0000-000000000001"))
    private let replicaB = ReplicaID(testUUID("00000000-0000-0000-0000-000000000002"))

    func testOrderingComparesCounterThenReplica() {
        XCTAssertLessThan(stamp(1, replicaB), stamp(2, replicaA))
        XCTAssertLessThan(stamp(4, replicaA), stamp(4, replicaB))
        XCTAssertEqual(stamp(4, replicaA), stamp(4, replicaA))
    }

    func testClockAdvancesBeyondLocalAndAllObservedCounters() throws {
        var clock = VersionClock(replicaID: replicaA)

        XCTAssertEqual(try clock.next(), stamp(1, replicaA))
        let generated = try clock.next(afterObserving: [stamp(9, replicaB), stamp(4, replicaA)])
        XCTAssertEqual(generated, stamp(10, replicaA))
        XCTAssertEqual(try clock.next(), stamp(11, replicaA))
    }

    func testObservingDoesNotGenerateAStamp() throws {
        var clock = VersionClock(replicaID: replicaA)
        clock.observe(stamp(20, replicaB))

        XCTAssertEqual(clock.logicalCounter, 20)
        XCTAssertEqual(try clock.next(), stamp(21, replicaA))
    }

    func testClockReportsOverflowWithoutWrapping() {
        var clock = VersionClock(replicaID: replicaA, logicalCounter: UInt64.max)

        XCTAssertThrowsError(try clock.next()) { error in
            XCTAssertEqual(error as? VersionClockError, .counterOverflow)
        }
        XCTAssertEqual(clock.logicalCounter, UInt64.max)
    }

    func testObservingMaximumCounterAlsoReportsOverflow() {
        var clock = VersionClock(replicaID: replicaA)

        XCTAssertThrowsError(try clock.next(afterObserving: stamp(UInt64.max, replicaB)))
        XCTAssertEqual(clock.logicalCounter, UInt64.max)
    }

    private func stamp(_ counter: UInt64, _ replica: ReplicaID) -> VersionStamp {
        VersionStamp(logicalCounter: counter, replicaID: replica)
    }
}
