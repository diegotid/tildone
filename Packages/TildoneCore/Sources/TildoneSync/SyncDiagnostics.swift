//
//  SyncDiagnostics.swift
//  Tildone
//
import Foundation

#if DEBUG
import OSLog
#endif

/// Debug-only, content-free synchronization breadcrumbs for device validation.
///
/// Messages intentionally contain only lifecycle categories and aggregate
/// counts. Record identifiers, account identifiers, titles, and task text are
/// never accepted by this API.
enum SyncDiagnostics {
#if DEBUG
    private static let logger = Logger(
        subsystem: "studio.cuatro.tildone",
        category: "CloudKitSync"
    )
#endif

    static func checkpointStarted(pendingCount: Int) {
#if DEBUG
        logger.debug("checkpoint-started pending=\(pendingCount, privacy: .public)")
#endif
    }

    static func fetched(modificationCount: Int, deletionCount: Int) {
#if DEBUG
        logger.debug(
            "fetched-records modifications=\(modificationCount, privacy: .public) deletions=\(deletionCount, privacy: .public)"
        )
#endif
    }

    static func sent(savedCount: Int, failedCount: Int) {
#if DEBUG
        logger.debug(
            "sent-records saved=\(savedCount, privacy: .public) failed=\(failedCount, privacy: .public)"
        )
#endif
    }

    static func accountChanged(category: String) {
#if DEBUG
        logger.notice("account-change category=\(category, privacy: .public)")
#endif
    }

    static func statusChanged(_ status: SyncStatus) {
#if DEBUG
        logger.debug(
            "status availability=\(status.availability.rawValue, privacy: .public) activity=\(status.activity.rawValue, privacy: .public) pending=\(status.pendingMutationCount, privacy: .public) issue=\(status.issue?.rawValue ?? "none", privacy: .public)"
        )
#endif
    }

    static func failed(category: String) {
#if DEBUG
        logger.error("sync-failure category=\(category, privacy: .public)")
#endif
    }

    static func quarantined(category: String) {
#if DEBUG
        logger.error("quarantined-record category=\(category, privacy: .public)")
#endif
    }
}
