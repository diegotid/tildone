//
//  WorkspaceOwnership.swift
//  Tildone
//
//  Created by Diego Rivera on 7/13/26.
//
import Darwin
import Foundation

/// An exclusive lifetime lease for one physical shared workspace.
///
/// The in-process registry closes the same-process `flock` loophole, while the
/// advisory lock file excludes a second Tildone process. The repository owns
/// this value for exactly as long as it owns its `ModelContainer`.
final class WorkspaceOwnershipLease: @unchecked Sendable {
    private static let registryLock = NSLock()
    nonisolated(unsafe) private static var ownedPaths: Set<String> = []

    private let canonicalPath: String
    private let fileDescriptor: Int32

    static func acquire(for storeURL: URL?) throws -> WorkspaceOwnershipLease? {
        guard let storeURL else { return nil }
        let directory = storeURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw PersistenceError.invalidStoreLocation
        }

        let canonicalStoreURL = storeURL.standardizedFileURL.resolvingSymlinksInPath()
        let canonicalPath = canonicalStoreURL.path
        registryLock.lock()
        guard ownedPaths.insert(canonicalPath).inserted else {
            registryLock.unlock()
            throw PersistenceError.workspaceInUse
        }
        registryLock.unlock()

        let lockURL = canonicalStoreURL.deletingLastPathComponent()
            .appendingPathComponent("tildone-shared.owner.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            releaseRegistryPath(canonicalPath)
            throw PersistenceError.invalidStoreLocation
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            releaseRegistryPath(canonicalPath)
            throw PersistenceError.workspaceInUse
        }
        return WorkspaceOwnershipLease(canonicalPath: canonicalPath, fileDescriptor: descriptor)
    }

    private init(canonicalPath: String, fileDescriptor: Int32) {
        self.canonicalPath = canonicalPath
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        Self.releaseRegistryPath(canonicalPath)
    }

    private static func releaseRegistryPath(_ path: String) {
        registryLock.lock()
        ownedPaths.remove(path)
        registryLock.unlock()
    }
}
