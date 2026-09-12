//
//  DomainMerge.swift
//  Tildone
//
//  Created by Diego Rivera on 7/12/26.
//
import Foundation

public enum DomainMergeError: Error, Equatable, Sendable {
    case differentIdentifiers
    case immutableFieldMismatch
    case conflictingPayloadAtSameVersion
}

public extension Note {
    /// Pure field-level merge. User-visible dates never choose title/lifecycle winners.
    func merged(with other: Self) throws -> Self {
        guard id == other.id else { throw DomainMergeError.differentIdentifiers }
        guard createdAt == other.createdAt else { throw DomainMergeError.immutableFieldMismatch }

        let winningTitle = try mergeVersioned(
            (title, titleVersion),
            (other.title, other.titleVersion)
        )
        let winningColor = try mergeColorVersioned(
            (color, colorVersion, schemaVersion),
            (other.color, other.colorVersion, other.schemaVersion)
        )
        let winningKind = try mergeKindVersioned(
            (kind, kindVersion, schemaVersion),
            (other.kind, other.kindVersion, other.schemaVersion)
        )
        let winningSingleMemoFont = try mergeSingleMemoFontVersioned(
            (singleMemoFont, singleMemoFontVersion, schemaVersion),
            (other.singleMemoFont, other.singleMemoFontVersion, other.schemaVersion)
        )
        let winningLifecycle = try mergeVersioned(
            (lifecycle, lifecycleVersion),
            (other.lifecycle, other.lifecycleVersion)
        )
        let winningMeaningfulEdit = try mergeVersioned(
            (lastMeaningfulEditAt, lastMeaningfulEditVersion),
            (other.lastMeaningfulEditAt, other.lastMeaningfulEditVersion)
        )

        return Self(
            id: id,
            createdAt: createdAt,
            title: winningTitle.value,
            titleVersion: winningTitle.version,
            color: winningColor.value,
            colorVersion: winningColor.version,
            kind: winningKind.value,
            kindVersion: winningKind.version,
            singleMemoFont: winningSingleMemoFont.value,
            singleMemoFontVersion: winningSingleMemoFont.version,
            lifecycle: winningLifecycle.value,
            lifecycleVersion: winningLifecycle.version,
            lastMeaningfulEditAt: winningMeaningfulEdit.value,
            lastMeaningfulEditVersion: winningMeaningfulEdit.version,
            schemaVersion: max(schemaVersion, other.schemaVersion)
        )
    }
}

private func mergeSingleMemoFontVersioned(
    _ lhs: (value: SingleMemoFont, version: VersionStamp, schemaVersion: Int),
    _ rhs: (value: SingleMemoFont, version: VersionStamp, schemaVersion: Int)
) throws -> (value: SingleMemoFont, version: VersionStamp) {
    let lhsIsExplicit = lhs.schemaVersion >= 4
    let rhsIsExplicit = rhs.schemaVersion >= 4
    if lhsIsExplicit != rhsIsExplicit {
        return lhsIsExplicit ? (lhs.value, lhs.version) : (rhs.value, rhs.version)
    }
    return try mergeVersioned(
        (lhs.value, lhs.version),
        (rhs.value, rhs.version)
    )
}

private func mergeKindVersioned(
    _ lhs: (value: NoteKind, version: VersionStamp, schemaVersion: Int),
    _ rhs: (value: NoteKind, version: VersionStamp, schemaVersion: Int)
) throws -> (value: NoteKind, version: VersionStamp) {
    let lhsIsExplicit = lhs.schemaVersion >= 3
    let rhsIsExplicit = rhs.schemaVersion >= 3
    if lhsIsExplicit != rhsIsExplicit {
        return lhsIsExplicit ? (lhs.value, lhs.version) : (rhs.value, rhs.version)
    }
    return try mergeVersioned(
        (lhs.value, lhs.version),
        (rhs.value, rhs.version)
    )
}

/// Color backfill is the only field whose conflict order carries migration
/// authority. Explicit V2 colors beat synthesized values, a legacy Mac value
/// beats a platform default, and an implicit V1 yellow loses to either. Values
/// in the same class retain ordinary Lamport ordering.
private func mergeColorVersioned(
    _ lhs: (value: NoteColor, version: VersionStamp, schemaVersion: Int),
    _ rhs: (value: NoteColor, version: VersionStamp, schemaVersion: Int)
) throws -> (value: NoteColor, version: VersionStamp) {
    func priority(_ value: (NoteColor, VersionStamp, Int)) -> Int {
        guard value.2 >= 2 else { return 0 }
        return NoteColorMigrationAuthority.authority(for: value.1.replicaID)?.rawValue ?? 3
    }

    let lhsPriority = priority(lhs)
    let rhsPriority = priority(rhs)
    if lhsPriority != rhsPriority {
        return lhsPriority > rhsPriority
            ? (lhs.value, lhs.version)
            : (rhs.value, rhs.version)
    }
    return try mergeVersioned(
        (lhs.value, lhs.version),
        (rhs.value, rhs.version)
    )
}

public extension Task {
    /// Pure property-level merge. Lifecycle is independent, so field edits can
    /// never clear a tombstone; only a newer explicit lifecycle version can.
    func merged(with other: Self) throws -> Self {
        guard id == other.id else { throw DomainMergeError.differentIdentifiers }
        guard noteID == other.noteID, createdAt == other.createdAt else {
            throw DomainMergeError.immutableFieldMismatch
        }

        // Text and formatting are one atomic field because every span is
        // positioned relative to that exact text revision.
        let winningText = try mergeVersioned(
            (richText, textVersion),
            (other.richText, other.textVersion)
        )
        let winningCompletion = try mergeVersioned(
            (completion, completionVersion),
            (other.completion, other.completionVersion)
        )
        let winningOrder = try mergeVersioned(
            (orderToken, orderVersion),
            (other.orderToken, other.orderVersion)
        )
        let winningIndent = try mergeVersioned(
            (indentLevel, indentVersion),
            (other.indentLevel, other.indentVersion)
        )
        let winningLifecycle = try mergeVersioned(
            (lifecycle, lifecycleVersion),
            (other.lifecycle, other.lifecycleVersion)
        )

        return Self(
            id: id,
            noteID: noteID,
            createdAt: createdAt,
            richText: winningText.value,
            textVersion: winningText.version,
            completion: winningCompletion.value,
            completionVersion: winningCompletion.version,
            orderToken: winningOrder.value,
            orderVersion: winningOrder.version,
            indentLevel: winningIndent.value,
            indentVersion: winningIndent.version,
            lifecycle: winningLifecycle.value,
            lifecycleVersion: winningLifecycle.version,
            schemaVersion: max(schemaVersion, other.schemaVersion)
        )
    }
}

private func mergeVersioned<Value: Equatable>(
    _ lhs: (value: Value, version: VersionStamp),
    _ rhs: (value: Value, version: VersionStamp)
) throws -> (value: Value, version: VersionStamp) {
    if lhs.version == rhs.version {
        guard lhs.value == rhs.value else {
            throw DomainMergeError.conflictingPayloadAtSameVersion
        }
        return lhs
    }
    return lhs.version > rhs.version ? lhs : rhs
}
