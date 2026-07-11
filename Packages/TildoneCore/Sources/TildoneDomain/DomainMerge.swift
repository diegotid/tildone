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
        let winningLifecycle = try mergeVersioned(
            (lifecycle, lifecycleVersion),
            (other.lifecycle, other.lifecycleVersion)
        )

        return Self(
            id: id,
            createdAt: createdAt,
            title: winningTitle.value,
            titleVersion: winningTitle.version,
            lifecycle: winningLifecycle.value,
            lifecycleVersion: winningLifecycle.version,
            lastMeaningfulEditAt: max(lastMeaningfulEditAt, other.lastMeaningfulEditAt),
            schemaVersion: max(schemaVersion, other.schemaVersion)
        )
    }
}

public extension Task {
    /// Pure property-level merge. Lifecycle is independent, so field edits can
    /// never clear a tombstone; only a newer explicit lifecycle version can.
    func merged(with other: Self) throws -> Self {
        guard id == other.id else { throw DomainMergeError.differentIdentifiers }
        guard noteID == other.noteID, createdAt == other.createdAt else {
            throw DomainMergeError.immutableFieldMismatch
        }

        let winningText = try mergeVersioned((text, textVersion), (other.text, other.textVersion))
        let winningCompletion = try mergeVersioned(
            (completion, completionVersion),
            (other.completion, other.completionVersion)
        )
        let winningOrder = try mergeVersioned(
            (orderToken, orderVersion),
            (other.orderToken, other.orderVersion)
        )
        let winningLifecycle = try mergeVersioned(
            (lifecycle, lifecycleVersion),
            (other.lifecycle, other.lifecycleVersion)
        )

        return Self(
            id: id,
            noteID: noteID,
            createdAt: createdAt,
            text: winningText.value,
            textVersion: winningText.version,
            completion: winningCompletion.value,
            completionVersion: winningCompletion.version,
            orderToken: winningOrder.value,
            orderVersion: winningOrder.version,
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
