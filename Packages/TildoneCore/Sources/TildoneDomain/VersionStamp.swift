import Foundation

/// A Lamport-style logical version.
///
/// Logical versions determine conflict winners. Dates on domain records are
/// user-visible metadata only and must never be used as revision ordering.
public struct VersionStamp: Codable, Hashable, Comparable, Sendable {
    public let logicalCounter: UInt64
    public let replicaID: ReplicaID

    public init(logicalCounter: UInt64, replicaID: ReplicaID) {
        self.logicalCounter = logicalCounter
        self.replicaID = replicaID
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.logicalCounter != rhs.logicalCounter {
            return lhs.logicalCounter < rhs.logicalCounter
        }
        return lhs.replicaID < rhs.replicaID
    }
}

public enum VersionClockError: Error, Equatable, Sendable {
    case counterOverflow
}

/// Generates monotonically increasing stamps for one replica.
public struct VersionClock: Hashable, Sendable {
    public let replicaID: ReplicaID
    public private(set) var logicalCounter: UInt64

    public init(replicaID: ReplicaID, logicalCounter: UInt64 = 0) {
        self.replicaID = replicaID
        self.logicalCounter = logicalCounter
    }

    /// Records a remotely observed or previously generated stamp without
    /// generating a new local version.
    public mutating func observe(_ stamp: VersionStamp) {
        logicalCounter = max(logicalCounter, stamp.logicalCounter)
    }

    public mutating func observe<S: Sequence>(contentsOf stamps: S) where S.Element == VersionStamp {
        for stamp in stamps {
            observe(stamp)
        }
    }

    /// Returns a local stamp beyond the clock and every supplied observation.
    /// Overflow is reported rather than wrapping and breaking version ordering.
    public mutating func next<S: Sequence>(afterObserving stamps: S) throws -> VersionStamp where S.Element == VersionStamp {
        observe(contentsOf: stamps)
        guard logicalCounter < UInt64.max else {
            throw VersionClockError.counterOverflow
        }
        logicalCounter += 1
        return VersionStamp(logicalCounter: logicalCounter, replicaID: replicaID)
    }

    public mutating func next(afterObserving stamp: VersionStamp? = nil) throws -> VersionStamp {
        try next(afterObserving: stamp.map { [$0] } ?? [])
    }
}
