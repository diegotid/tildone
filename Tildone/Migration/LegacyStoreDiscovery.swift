//
//  LegacyStoreDiscovery.swift
//  Tildone
//
//  Created by OpenAI Codex on 7/13/26.
//
import Foundation
import SwiftData
import TildonePersistence

enum LegacyStoreDiscoveryError: Error, Equatable {
    case missingSource
    case invalidSource
    case sourceChanged
    case sourceDestinationCollision
    case snapshotCopyFailed
}

struct LegacyStoreFileSet: Equatable {
    static let sidecarSuffixes = ["", "-wal", "-shm", "-journal"]

    let mainStoreURL: URL
    let fileURLs: [URL]
    let fingerprint: LegacySourceFingerprint

    /// Resolves the exact URL selected by the released app's configuration.
    /// This is used for discovery only; migration and tests require an explicit
    /// URL and never fall back to this value.
    static func releasedShippingURL() -> URL {
        let schema = Schema([Todo.self, TodoList.self])
        return ModelConfiguration(schema: schema, isStoredInMemoryOnly: false).url
    }

    static func inspect(sourceURL: URL, destinationURL: URL? = nil) throws -> Self {
        guard sourceURL.isFileURL else { throw LegacyStoreDiscoveryError.invalidSource }
        let source = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw LegacyStoreDiscoveryError.missingSource
        }

        if let destinationURL {
            let destination = destinationURL.standardizedFileURL.resolvingSymlinksInPath()
            let sourcePaths = Set(sidecarSuffixes.map { source.path + $0 })
            let destinationPaths = Set(sidecarSuffixes.map { destination.path + $0 })
            guard sourcePaths.isDisjoint(with: destinationPaths) else {
                throw LegacyStoreDiscoveryError.sourceDestinationCollision
            }
        }

        let candidates = sidecarSuffixes.map { URL(fileURLWithPath: source.path + $0) }
        let files = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard files.first == source else { throw LegacyStoreDiscoveryError.missingSource }

        var identityHasher = TildoneSHA256()
        var contentHasher = TildoneSHA256()
        var totalBytes: UInt64 = 0
        for file in files {
            let suffix = String(file.path.dropFirst(source.path.count))
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard let sizeNumber = attributes[.size] as? NSNumber,
                  let deviceNumber = attributes[.systemNumber] as? NSNumber,
                  let inodeNumber = attributes[.systemFileNumber] as? NSNumber else {
                throw LegacyStoreDiscoveryError.invalidSource
            }
            let size = sizeNumber.uint64Value
            guard UInt64.max - totalBytes >= size else { throw LegacyStoreDiscoveryError.invalidSource }
            totalBytes += size

            identityHasher.update(Data("\(suffix)|\(file.standardizedFileURL.path)|\(deviceNumber)|\(inodeNumber)\n".utf8))
            contentHasher.update(Data("\(suffix)|\(size)\n".utf8))
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            while true {
                let data = try handle.read(upToCount: 1_048_576) ?? Data()
                if data.isEmpty { break }
                contentHasher.update(data)
            }
        }
        guard totalBytes > 0 else { throw LegacyStoreDiscoveryError.invalidSource }
        return Self(
            mainStoreURL: source,
            fileURLs: files,
            fingerprint: LegacySourceFingerprint(
                identityDigest: identityHasher.finalizeHex(),
                contentDigest: contentHasher.finalizeHex(),
                fileCount: files.count,
                totalByteCount: totalBytes
            )
        )
    }

    func makeReadOnlySnapshot(in snapshotRoot: URL? = nil) throws -> LegacyStoreSnapshot {
        let root = snapshotRoot ?? FileManager.default.temporaryDirectory
        guard root.isFileURL else { throw LegacyStoreDiscoveryError.snapshotCopyFailed }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root
            .appendingPathComponent("TildoneLegacySnapshot-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for source in fileURLs {
                let suffix = String(source.path.dropFirst(mainStoreURL.path.count))
                let destination = directory.appendingPathComponent(mainStoreURL.lastPathComponent + suffix)
                try FileManager.default.copyItem(at: source, to: destination)
            }
            let after = try Self.inspect(sourceURL: mainStoreURL)
            guard after.fingerprint == fingerprint else {
                try? FileManager.default.removeItem(at: directory)
                throw LegacyStoreDiscoveryError.sourceChanged
            }
            return LegacyStoreSnapshot(
                directoryURL: directory,
                mainStoreURL: directory.appendingPathComponent(mainStoreURL.lastPathComponent),
                requiresWritableWALRecovery: !fileURLs.contains(where: { $0.path == mainStoreURL.path + "-wal" }) ||
                    !fileURLs.contains(where: { $0.path == mainStoreURL.path + "-shm" })
            )
        } catch let error as LegacyStoreDiscoveryError {
            throw error
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw LegacyStoreDiscoveryError.snapshotCopyFailed
        }
    }
}

final class LegacyStoreSnapshot {
    let directoryURL: URL
    let mainStoreURL: URL
    let requiresWritableWALRecovery: Bool

    init(directoryURL: URL, mainStoreURL: URL, requiresWritableWALRecovery: Bool) {
        self.directoryURL = directoryURL
        self.mainStoreURL = mainStoreURL
        self.requiresWritableWALRecovery = requiresWritableWALRecovery
    }

    deinit {
        // SwiftData/Core Data can keep autoreleased SQLite internals alive
        // until the next run-loop turn even after its container is released.
        // Delay unlinking so no open vnode is invalidated. The developer tool
        // additionally owns and removes its unique snapshot root after the
        // test-host process exits.
        let directoryURL = directoryURL
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }
}

/// Small streaming SHA-256 implementation kept here so the migration layer
/// depends only on Foundation and the explicitly approved modules.
struct TildoneSHA256 {
    private static let initial: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]
    private static let constants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    private var state = initial
    private var buffer = Data()
    private var byteCount: UInt64 = 0

    mutating func update(_ data: Data) {
        byteCount &+= UInt64(data.count)
        buffer.append(data)
        while buffer.count >= 64 {
            compress(buffer.prefix(64))
            buffer.removeFirst(64)
        }
    }

    mutating func finalizeHex() -> String {
        let bitCount = byteCount &* 8
        buffer.append(0x80)
        while buffer.count % 64 != 56 { buffer.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            buffer.append(UInt8((bitCount >> UInt64(shift)) & 0xff))
        }
        while !buffer.isEmpty {
            compress(buffer.prefix(64))
            buffer.removeFirst(64)
        }
        return state.map { String(format: "%08x", $0) }.joined()
    }

    private mutating func compress(_ block: Data.SubSequence) {
        let bytes = Array(block)
        var words = [UInt32](repeating: 0, count: 64)
        for index in 0..<16 {
            let offset = index * 4
            words[index] = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16 |
                UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
        }
        for index in 16..<64 {
            let x = words[index - 15]
            let y = words[index - 2]
            let s0 = rotateRight(x, by: 7) ^ rotateRight(x, by: 18) ^ (x >> 3)
            let s1 = rotateRight(y, by: 17) ^ rotateRight(y, by: 19) ^ (y >> 10)
            words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
        }
        var a = state[0], b = state[1], c = state[2], d = state[3]
        var e = state[4], f = state[5], g = state[6], h = state[7]
        for index in 0..<64 {
            let s1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
            let choice = (e & f) ^ ((~e) & g)
            let temp1 = h &+ s1 &+ choice &+ Self.constants[index] &+ words[index]
            let s0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
            let majority = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = s0 &+ majority
            h = g; g = f; f = e; e = d &+ temp1
            d = c; c = b; b = a; a = temp1 &+ temp2
        }
        state[0] &+= a; state[1] &+= b; state[2] &+= c; state[3] &+= d
        state[4] &+= e; state[5] &+= f; state[6] &+= g; state[7] &+= h
    }

    private func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}
