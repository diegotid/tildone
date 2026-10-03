import XCTest
@testable import Tildone

final class AppReviewPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let day: TimeInterval = 86_400

    private func engaged() -> AppReviewPolicy {
        var policy = AppReviewPolicy()
        for offset in [0.0, 1.0, 7.0] {
            policy.recordActivity(at: start.addingTimeInterval(offset * day))
        }
        for _ in 0..<10 { policy.recordCompletion(UUID(), completed: true) }
        return policy
    }

    func testFirstLaunchAndRepeatedActivityDoNotQualify() {
        var policy = AppReviewPolicy()
        for _ in 0..<20 { policy.recordActivity(at: start) }
        for _ in 0..<10 { policy.recordCompletion(UUID(), completed: true) }
        XCTAssertEqual(policy.activeDays, 1)
        XCTAssertFalse(policy.isEligible(at: start.addingTimeInterval(7 * day), version: "1"))
    }

    func testAgeBoundaryAndMeaningfulUseAreRequired() {
        let policy = engaged()
        XCTAssertFalse(policy.isEligible(at: start.addingTimeInterval(7 * day - 1), version: "1"))
        XCTAssertTrue(policy.isEligible(at: start.addingTimeInterval(7 * day), version: "1"))
    }

    func testRepeatedCompletionAndUncompletionDoNotInflateEngagement() {
        var policy = AppReviewPolicy()
        let id = UUID()
        for _ in 0..<20 { policy.recordCompletion(id, completed: true) }
        XCTAssertEqual(policy.completedTaskIDs.count, 1)
        policy.recordCompletion(id, completed: false)
        XCTAssertTrue(policy.completedTaskIDs.isEmpty)
        for _ in 0..<100 { policy.recordCompletion(UUID(), completed: true) }
        XCTAssertEqual(policy.completedTaskIDs.count, 10)
    }

    func testSameVersionAndCooldownRemainBlockedWithFreshCompletions() {
        var policy = engaged()
        let requested = start.addingTimeInterval(7 * day)
        policy.recordRequest(at: requested, version: "1")
        XCTAssertTrue(policy.completedTaskIDs.isEmpty)
        for _ in 0..<10 { policy.recordCompletion(UUID(), completed: true) }
        XCTAssertFalse(policy.isEligible(at: requested.addingTimeInterval(120 * day), version: "1"))
        XCTAssertFalse(policy.isEligible(at: requested.addingTimeInterval(120 * day - 1), version: "2"))
        XCTAssertTrue(policy.isEligible(at: requested.addingTimeInterval(120 * day), version: "2"))
    }

    func testThreeRequestsAreMaximumInRollingYear() {
        var policy = engaged()
        for (index, offset) in [7.0, 127.0, 247.0].enumerated() {
            policy.recordRequest(at: start.addingTimeInterval(offset * day), version: String(index))
        }
        for _ in 0..<10 { policy.recordCompletion(UUID(), completed: true) }
        XCTAssertFalse(policy.isEligible(at: start.addingTimeInterval(367 * day), version: "next"))
        XCTAssertTrue(policy.isEligible(at: start.addingTimeInterval(372 * day), version: "next"))
    }

    func testRelaunchPreservesEngagementAndRequestBudget() throws {
        var policy = engaged()
        policy.recordRequest(at: start.addingTimeInterval(7 * day), version: "1")
        for _ in 0..<10 { policy.recordCompletion(UUID(), completed: true) }
        let restored = try JSONDecoder().decode(AppReviewPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertEqual(restored.requests, policy.requests)
        XCTAssertFalse(restored.isEligible(at: start.addingTimeInterval(8 * day), version: "2"))
        XCTAssertTrue(restored.isEligible(at: start.addingTimeInterval(127 * day), version: "2"))
    }

    func testClockMovingBackwardsDoesNotAddDaysOrBypassCooldown() {
        var policy = engaged()
        policy.recordActivity(at: start)
        XCTAssertEqual(policy.activeDays, 3)
        policy.recordRequest(at: start.addingTimeInterval(7 * day), version: "1")
        for _ in 0..<10 { policy.recordCompletion(UUID(), completed: true) }
        XCTAssertFalse(policy.isEligible(at: start, version: "2"))
    }

    func testMissingMarketingVersionDoesNotQualify() {
        XCTAssertFalse(engaged().isEligible(at: start.addingTimeInterval(7 * day), version: ""))
    }
}
