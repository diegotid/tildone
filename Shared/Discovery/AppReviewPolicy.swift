import Foundation

/// Installation-local engagement, never synchronized or sent to analytics.
/// Stores opaque IDs only, bounded to the ten completions needed for eligibility.
struct AppReviewPolicy: Codable {
    static let storageKey = "appReviewPolicy.v1"
    private(set) var firstUse: Date?
    private(set) var lastActiveDay: Date?
    private(set) var activeDays = 0
    private(set) var completedTaskIDs: Set<UUID> = []
    private(set) var requests: [Date] = []
    private(set) var lastRequestedVersion: String?

    mutating func recordActivity(at now: Date, calendar: Calendar = .current) {
        if firstUse == nil { firstUse = now }
        let day = calendar.startOfDay(for: now)
        if lastActiveDay.map({ day > $0 }) ?? true {
            activeDays += 1
            lastActiveDay = day
        }
    }

    mutating func recordCompletion(_ id: UUID, completed: Bool) {
        if completed {
            if completedTaskIDs.count < 10 { completedTaskIDs.insert(id) }
        } else {
            completedTaskIDs.remove(id)
        }
    }

    func isEligible(at now: Date, version: String) -> Bool {
        guard let firstUse, now.timeIntervalSince(firstUse) >= 7 * 86_400,
              activeDays >= 3, completedTaskIDs.count >= 10,
              !version.isEmpty, lastRequestedVersion != version else { return false }
        if let last = requests.last, now.timeIntervalSince(last) < 120 * 86_400 { return false }
        return requests.filter { now.timeIntervalSince($0) < 365 * 86_400 }.count < 3
    }

    /// StoreKit doesn't report whether a prompt appeared or a review was submitted.
    /// Consume our budget for every API call, including calls Apple suppresses.
    mutating func recordRequest(at now: Date, version: String) {
        requests = requests.filter { now.timeIntervalSince($0) < 365 * 86_400 }
        requests.append(now)
        lastRequestedVersion = version
        completedTaskIDs.removeAll()
    }
}
