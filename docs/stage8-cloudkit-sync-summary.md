# Stage 8: private CloudKit synchronization

## Outcome

Stage 8 adds the UI-independent `TildoneSync` product and composes it with the Stage 4–7 domain, persistence, migration, durable-outbox, tombstone, and account-workspace layers. The local SwiftData store remains authoritative for interaction: every edit commits content, its version stamp, and its outbox mutation in one local transaction. `CKSyncEngine` sends and fetches later.

The rollout is development-only. Debug builds start synchronization only when the `TILDONE_ENABLE_CLOUDKIT_SYNC=1` environment variable is present; Release builds keep it disabled. No production CloudKit schema was deployed as part of this stage.

## CloudKit configuration

- Container: `iCloud.studio.cuatro.tildone`
- Database: private database only
- Custom zone: `TildoneUserData`, owned by `CKCurrentUserDefaultName`
- `CKSyncEngine` subscription identifier: `tildone-private-zone-v1`
- Record types: `TDNote` and `TDTask` only
- Mac and iPhone entitlements select the Development environment and the same container.
- The iPhone target enables the `remote-notification` background mode and registers for remote notifications while the development flag is enabled.
- Every Stage 5 SwiftData `ModelConfiguration` still explicitly uses `cloudKitDatabase: .none`; SwiftData automatic CloudKit mirroring is not used.

The app creates its custom zone through `CKSyncEngine` pending database changes. All content records live in that zone. Lifecycle deletion is represented inside records; normal operation does not physically delete content records.

## Record schema

Record names are derived only from stable domain UUIDs (`note-<uuid>` and `task-<uuid>`). Names, diagnostics, status values, and notification configuration contain no title or task text.

`TDNote` fields:

| Field | CloudKit value | Purpose |
| --- | --- | --- |
| `schemaVersion` | integer | Domain record schema version |
| `createdAt` | date | Immutable creation metadata |
| `title` | optional string | Note title |
| `titleVersionCounter` | integer | Title Lamport counter |
| `titleVersionReplicaID` | string | Title tie-break replica UUID |
| `lifecycle` | string | `active` or `deleted` |
| `lifecycleVersionCounter` | integer | Lifecycle Lamport counter |
| `lifecycleVersionReplicaID` | string | Lifecycle tie-break replica UUID |
| `lastMeaningfulEditAt` | date | Domain ordering metadata |
| `lastMeaningfulEditVersionCounter` | integer | Ordering-metadata Lamport counter |
| `lastMeaningfulEditVersionReplicaID` | string | Ordering-metadata tie-break replica UUID |

`TDTask` fields:

| Field | CloudKit value | Purpose |
| --- | --- | --- |
| `schemaVersion` | integer | Domain record schema version |
| `noteID` | string | Stable parent note UUID |
| `createdAt` | date | Immutable creation metadata |
| `text` | string | Task text |
| `textVersionCounter` | integer | Text Lamport counter |
| `textVersionReplicaID` | string | Text tie-break replica UUID |
| `isCompleted` | boolean | Completion value |
| `completedAt` | optional date | Atomically paired completion date |
| `completionVersionCounter` | integer | Completion Lamport counter |
| `completionVersionReplicaID` | string | Completion tie-break replica UUID |
| `orderToken` | string | Fractional ordering token |
| `orderVersionCounter` | integer | Ordering Lamport counter |
| `orderVersionReplicaID` | string | Ordering tie-break replica UUID |
| `lifecycle` | string | `active` or `deleted` |
| `lifecycleVersionCounter` | integer | Lifecycle Lamport counter |
| `lifecycleVersionReplicaID` | string | Lifecycle tie-break replica UUID |

The mapper validates zone, record type, stable identifier, schema version, required values, version stamps, completion invariants, lifecycle, ownership, and order tokens. Unknown or malformed records are quarantined by opaque identifier. A future schema freezes this replica for an upgrade rather than partially interpreting the record.

## Engine and persistence lifecycle

`TildoneSyncCoordinator` requires an account-scoped repository. It refuses a local-only repository. Startup ordering is:

1. Complete and validate the Stage 6 legacy migration and Stage 7 shared-store activation.
2. Resolve the current private CloudKit user to a deterministic, content-free workspace UUID.
3. Open that account's physically separate shared store.
4. Restore the sync envelope from `WorkspaceMetadata.futureSyncEngineState`.
5. Construct `CKSyncEngine`, restore its serialized state, schedule the custom zone when necessary, and schedule every durable pending outbox target.
6. Send and fetch asynchronously.

The versioned sync envelope contains:

- `CKSyncEngine.State.Serialization`
- encoded CloudKit system fields per stable record name, including change tags required for conflict retries
- whether the custom zone was confirmed
- a durable `zoneResetRequired` safety latch

Envelope mutations and their repository writes are serialized through one actor so an older engine checkpoint cannot overwrite newer system fields. The existing Stage 5 opaque state column means no speculative SwiftData schema change was needed.

The iPhone scaffold performs the same account resolution, account-workspace open, state restore, and engine startup. It intentionally adds no product editing UI in Stage 8.

## Outbox, retry, and conflict behavior

- A local domain mutation and its outbox row commit atomically.
- Preparing a `CKRecord` records an attempt but does not acknowledge the mutation.
- Only a record returned in `SentRecordZoneChanges.savedRecords` acknowledges the exact in-flight mutation UUID.
- A stale acknowledgement cannot clear a newer superseding mutation.
- Partial success acknowledges successful siblings and reschedules failed records only.
- Network, service, throttling, and temporary-account failures leave durable work pending for a later checkpoint.
- Duplicate scheduling, duplicate sends, and duplicate fetched deliveries are harmless.
- Relaunch restores both engine progress and unsent outbox work.
- `serverRecordChanged` decodes and domain-merges the server record, preserves the local outbox winner, stores the returned system fields/change tag, and retries the stable record.

Fetched notes are applied before fetched tasks. Remote application uses the existing pure, deterministic property-level merge rules and advances the local Lamport clock beyond observed counters. Remote application does not echo ordinary changes into the outbox.

Title, task text, completion, order, lifecycle, and note meaningful-edit metadata merge independently. Completion boolean and timestamp travel together. Stable replica IDs break same-counter ties. A lifecycle tombstone wins over ordinary edits until a newer explicit restore. A deleted parent normalizes all active children to newer tombstones and durably sends those child tombstones. A task arriving before its active parent may remain a valid orphan; a task arriving under a known deleted parent is tombstoned instead of resurrecting content.

Unexpected physical record deletion is defensively converted into a newer local lifecycle tombstone and sent back. This compatibility path prevents a physical deletion notification from making an older saved record authoritative again.

## Account and workspace behavior

The raw CloudKit user record name is hashed with the container identifier into a deterministic UUID and is never exposed or logged. Each confirmed account maps to a separate on-disk account directory.

- **Available:** open only the matching account workspace and start its engine.
- **No account:** do not open an account cache; Mac may continue in its local-only workspace and iPhone remains without a sync store.
- **Restricted:** report permission attention and do not open an account cache.
- **Temporarily unavailable / could not determine:** preserve data on disk, report offline/service status, and do not guess an account identity.
- **Confirmed sign-out or switch:** freeze/cancel the old engine and drop application references to its store. The Mac asks for relaunch; the iPhone stops exposing the handle. A new launch resolves and opens only the new account's directory.
- **Network/service/quota:** preserve all local work; expose a content-free status issue and retry through later engine scheduling.
- **Zone deletion/reset:** persist `zoneResetRequired`, cancel work, and require an explicit recovery decision. The implementation does not silently recreate the zone or upload a possibly stale local snapshot.

Local-only adoption remains deliberately unresolved. Merely enabling sync or signing into iCloud never uploads an existing local-only workspace. When the account workspace is empty, Mac stays local and reports `adoptionRequired`. The development-only `TILDONE_ALLOW_LOCAL_WORKSPACE_ADOPTION=1` flag is the explicit test boundary: it deterministically merges the local snapshot into the account workspace, queues a retry-safe seed, and marks legacy cloud seeding as begun. It can safely resume if interrupted. If the account already has data and adoption is not approved, the account workspace is authoritative and the unrelated local-only data remains separate and unuploaded.

## Transport-independent status

`SyncStatus` contains only availability, activity, pending mutation count, last successful checkpoint date, and a bounded issue enum. It has no record identifiers or content. The model distinguishes disabled, available, no-account, restricted, temporary-unavailability, adoption-required, account-changed, zone-reset-required, and incompatible-remote-data states, plus idle, syncing, offline, and attention-needed activity.

## Automated validation

The normal test suite does not use a network or Apple Account. `TildoneSyncTests` drives the mapper, durable repository, and `SyncPipeline` as simulated replicas. Coverage includes:

- domain/CloudKit mapping round trips and exact schema constants
- initial upload and initial fetch
- on-disk outbox durability and interrupted send/relaunch
- duplicate sends and duplicate deliveries
- independent-property edits and same-property conflicts
- text versus completion, concurrent reorder, delete versus edit, and parent deletion with child changes
- offline edits, reconnection, and partial acknowledgements
- simulated `serverRecordChanged`
- engine envelope restoration and durable zone-reset latch
- account workspace isolation and stable opaque account keys
- malformed, unknown, and future-schema records
- reordered duplicate delivery and convergence across three replicas

Validation performed on 2026-07-15:

- `swift test` in `Packages/TildoneCore`: 71 deterministic tests passed with no failures.
- Debug generic iPhone device build with code signing disabled: succeeded.
- Debug macOS build with code signing disabled: succeeded.
- Hosted Mac unit tests: passed; the live development-container smoke test is skipped by default.

The hosted opt-in test creates the custom zone if needed, saves/fetches/decodes one synthetic `TDNote`, and removes it. Run it only with a signed Debug app, a dedicated development account, and `TILDONE_RUN_DEVELOPMENT_CLOUDKIT_TESTS=1`. Never enable it against Production.

## Manual development-container test

Before testing, select a development team for both targets, verify both entitlements resolve to `iCloud.studio.cuatro.tildone`, leave the container environment at Development, and add `TILDONE_ENABLE_CLOUDKIT_SYNC=1` to both Debug run schemes. On the Mac only, add `TILDONE_ALLOW_LOCAL_WORKSPACE_ADOPTION=1` when explicitly testing adoption of pre-sync local data; remove it for all non-adoption scenarios.

### One Mac and one iPhone simulator or device

1. Sign both into the same iCloud account. A physical iPhone is preferred because simulator account and silent-push behavior can differ.
2. Launch the Mac first and allow Stage 6–7 migration/activation to finish. Approve adoption only with the development flag above.
3. Create a note and tasks on the Mac, edit title/text/completion/order, and launch the iPhone. Inspect the account workspace or use the debugger/integration harness to confirm the same domain records arrived; Stage 8 intentionally has no iPhone editing UI.
4. Terminate and relaunch each app. Confirm no duplicate rows and no loss of pending work.
5. Put one device in airplane mode, make several Mac edits (or use the package integration harness for an iPhone-originated edit), terminate/relaunch, reconnect, and verify the durable outbox drains and both stores converge.
6. Exercise concurrent title/text/completion/order mutations and delete-versus-edit with two development replicas. Confirm final domain snapshots, including tombstones, match.
7. Delete the development custom zone in CloudKit Dashboard. Confirm the client reports zone reset attention and does not silently seed. Recreate or clear test data only after making an explicit recovery decision.

### Two physical devices

Use two physical devices when validating background delivery, notification wakeups, airplane-mode transitions, termination/relaunch, or simulator account behavior. Install signed Debug builds with the same development flags and account, leave each app installed between steps, and repeat the offline/concurrent/deletion cases above. Because the Stage 8 iPhone product UI is still a scaffold, use the development integration harness/debugger to originate iPhone repository mutations.

### Different accounts

1. Seed account A, terminate the apps, and sign one device into account B.
2. Relaunch. Confirm account A content is not shown and the account-A store directory is not opened as account B.
3. Create or seed account-B test data and verify it does not appear under account A.
4. Test confirmed sign-out while running. Confirm the active engine stops and the old workspace is no longer exposed.

Do not use CloudKit Dashboard's Production environment, deploy a production schema, or run zone-deletion tests against production data.

## Deviations and deferred decisions

- No speculative record type or schema-marker record was added; current domain `schemaVersion` fields provide per-record compatibility checks.
- Automatic destructive zone recovery is deferred. The durable safety latch is implemented, but a future product flow must choose whether to accept remote reset, restore from a trusted replica, or export local data.
- Local-only-to-account adoption remains a product-policy decision and is available only through an explicit Debug-only test boundary.
- Full iPhone product UI is outside Stage 8, so two-device iPhone-originated edit validation currently requires the development harness/debugger. The sync and persistence products themselves build for iOS.
- No production schema was deployed and no live Apple-account test was run as part of the automated local validation recorded above.
