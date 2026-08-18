//
//  CompletionFadeLifecycle.swift
//  Tildone
//

import Foundation

/// Restart-safe presentation state for a note's destructive completion grace
/// period. The persisted completion date identifies one completion cycle, so a
/// restored or remotely completed note resumes the same fade instead of being
/// treated as permanently "already done."
struct CompletionFadeLifecycle: Equatable {
    enum Phase: Equatable {
        case idle
        case fading(completedAt: Date)
        case cancelled(completedAt: Date)
        case deleting(completedAt: Date)

        var completedAt: Date? {
            switch self {
            case .idle: nil
            case let .fading(completedAt), let .cancelled(completedAt), let .deleting(completedAt):
                completedAt
            }
        }
    }

    private(set) var phase: Phase = .idle

    var isFading: Bool {
        if case .fading = phase { return true }
        return false
    }

    var showsCompletionOverlay: Bool {
        switch phase {
        case .fading, .deleting: true
        case .idle, .cancelled: false
        }
    }

    mutating func synchronize(completedAt: Date?, autoDeletionCancelled: Bool = false) {
        guard let completedAt else {
            phase = .idle
            return
        }
        if autoDeletionCancelled {
            phase = .cancelled(completedAt: completedAt)
            return
        }
        guard phase.completedAt != completedAt else { return }
        phase = .fading(completedAt: completedAt)
    }

    mutating func cancel() {
        guard case let .fading(completedAt) = phase else { return }
        phase = .cancelled(completedAt: completedAt)
    }

    func progress(at date: Date, duration: TimeInterval) -> TimeInterval {
        guard case let .fading(completedAt) = phase, duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(completedAt), 0), duration)
    }

    mutating func beginDeletionIfReady(at date: Date, duration: TimeInterval) -> Date? {
        guard case let .fading(completedAt) = phase,
              date.timeIntervalSince(completedAt) >= duration else {
            return nil
        }
        phase = .deleting(completedAt: completedAt)
        return completedAt
    }

    mutating func deletionFailed(completedAt: Date) {
        guard phase == .deleting(completedAt: completedAt) else { return }
        phase = .cancelled(completedAt: completedAt)
    }
}
