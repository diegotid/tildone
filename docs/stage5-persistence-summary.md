# Stage 5 Shared Persistence Summary

## Scope and boundaries

Stage 5 adds the local-first `TildonePersistence` target inside `Packages/TildoneCore`. It depends only on Foundation, SwiftData, and `TildoneDomain`. It does not integrate either shipping app, open or modify the released Mac SwiftData store, import `Todo`/`TodoList`, enable iCloud, add networking, or implement CloudKit/`CKSyncEngine`.

Because `docs/stage4-domain-summary.md` was absent, the completed Stage 4 sources and tests were treated as authoritative. Stage 4 had no repository protocols, so `TildoneDomain` gained only Foundation-only async `NoteRepository` and `TaskRepository` protocols plus `Note.recordMeaningfulEdit(at:)` for domain-owned display metadata.

## Stored schema and deletion rules

`TildoneSchemaV1` is an explicit `VersionedSchema` with version `1.0.0`. `TildoneSchemaMigrationPlan` centrally lists that schema and deliberately has no migration stages for the initial version. This version identifies the new shared store only; it is unrelated to the released Mac schema.

The schema contains five SwiftData models:

- `StoredNote`: stable ID, creation date, optional title, independent title stamp, lifecycle/tombstone and stamp, last meaningful edit date, and record schema version.
- `StoredTask`: stable ID, immutable owning note ID, creation date, text/stamp, completion payload/stamp, order token/stamp, lifecycle/tombstone and stamp, and record schema version.
- `PendingMutation`: content-free mutation ID, target kind/stable ID, logical sequence, creation/attempt metadata, and supersession link.
- `WorkspaceMetadata`: singleton workspace identity, replica ID, durable logical counter, shared-schema version, and uninterpreted optional bytes reserved for future sync-engine state.
- `QuarantinedRecord`: content-free record identity/type, typed safe error category, optional record schema version, and quarantine date.

There are intentionally no SwiftData relationships or cascading delete rules. Ownership is an immutable stable note ID on every task. No content row is physically deleted by repository operations. This protects tombstone evidence, tolerates future task-before-parent delivery, and prevents framework cascades from erasing sync evidence. Outbox acknowledgements physically remove only acknowledged mutation rows. There is no time-based or automatic garbage collection.

No UI/window state, derived counts, user preferences, CloudKit records/system fields, or transport-operation concepts are stored. Counts and visibility are derived from validated domain snapshots.

## Mapping and errors

`StoredDomainMapping` is the explicit, testable boundary in both directions. It validates note/task IDs, ownership, nonnegative representable counters, replica IDs, lifecycle raw values, completion Boolean/date consistency, canonical order tokens, and record schema compatibility. It never crashes or invents repairs. Corrupt identifier text is replaced with a safe diagnostic marker instead of being echoed.

`PersistenceError` provides typed open, save, missing/duplicate identity, ownership, malformed representation, invariant, schema, workspace/location, counter, and atomic-mutation failures. Error payloads contain only stable opaque IDs, field/category names, or schema numbers—not note titles or task text. Store creation never falls back to a new empty store after an open failure.

## Repository API and concurrency

`TildoneRepository` is an actor conforming to the domain repository protocols. Domain `Note`/`Task` values are `Sendable` snapshots crossing actor isolation; SwiftData models and contexts remain internal. The actor serializes stable-ID checks and workspace logical-counter advancement. It creates a fresh `ModelContext` for each read or mutation and disables autosave.

Supported note operations are create, fetch including an explicit tombstone option, visible/meaningful-change queries, rename, soft delete, and explicit restore. Note deletion tombstones all active children in the same transaction. Supported task operations are add, fetch, deterministic ordered query, text edit, completion/uncompletion, move, soft delete, explicit restore, and domain-derived summaries. Task creation/mutation/restore rejects missing or deleted parents; ownership is never changed.

All business mutations use `TildoneDomain` mutation methods and advance only the affected property stamp. Task changes update the owning note's meaningful-edit display date without using wall-clock time as conflict authority.

## Atomic durable outbox

Each content mutation updates content, the workspace logical counter, and one or more `PendingMutation` rows in one `ModelContext.save()`. A failed save discards the operation context, leaving neither content nor outbound evidence committed.

Pending work contains no title or task text. Repeated changes to one target create a new sequenced row and mark the prior active row as superseded. Thus a stale in-flight acknowledgement cannot remove newer work. Active scheduling excludes superseded rows; all rows remain individually acknowledgeable/removable. Attempt count/date are durable and retry-safe. No CloudKit operation types or scheduling assumptions appear in persistence.

## Tombstones and visibility

Deleted notes/tasks remain durable lifecycle rows and are hidden from ordinary fetches. Ordinary field edits never change lifecycle state. Restore is an explicit repository call that obtains a newer lifecycle stamp. Deleting a note atomically tombstones its active tasks and enqueues each stable target. Restoring a note does not implicitly restore children. Tombstones survive reopen and are retained indefinitely in this stage.

## Workspaces and locations

`PersistenceStoreDescriptor` provides persistent, in-memory test, preview, and temporary-migration configurations. Tests and previews receive a caller-supplied base directory or isolated in-memory identifier.

Persistent locations are deterministic:

```text
<base>/TildoneSharedStore-v1/local-only/tildone-shared.sqlite
<base>/TildoneSharedStore-v1/accounts/<opaque-account-UUID>/tildone-shared.sqlite
```

Preview and temporary-migration roots include caller-controlled UUIDs and cannot collide with production. Every directory is created explicitly and failures are typed. The new filename/root cannot collide with the legacy default store. Account UUIDs are opaque caller-supplied keys; persistence performs no account query, adoption, or workspace merge.

Every `ModelConfiguration`, both disk and memory, explicitly sets `cloudKitDatabase: .none`. The target does not import CloudKit and needs no entitlement.

## Tests

`TildonePersistenceTests` uses only in-memory stores and caller-created temporary directories. Coverage includes:

- complete note/task round trips including every ID, stamp, lifecycle, completion/date, order token, Unicode, and optional title;
- malformed IDs/ownership/order/stamps/lifecycle/completion/schema with typed failures;
- independent mutation stamps, deterministic equal-token ordering, summaries, visibility, meaningful-edit queries, invalid/deleted parents, parent deletion, and explicit restore;
- atomic outbox success, supersession, retry, acknowledgement, content-free snapshots, reopen durability, and forced-save rollback leaving neither half;
- concurrent duplicate creation, actor-serialized monotonic counters, and independent in-memory repositories;
- create/reopen durability, local/account workspace isolation, repeatable paths, typed bad locations, opaque state, schema/migration wiring, and proof a sentinel legacy-store path remains byte-for-byte untouched.

## Validation commands and results

Validation used Xcode 26.4.1 (build 17E202), macOS 26.5.2, the macOS 26.4 SDK, and iOS 26.4 SDK. SwiftPM compiler/module caches were redirected to `/tmp` because the managed sandbox blocks the user cache; SwiftPM itself required approved execution outside its nested sandbox.

- `swift test --filter TildoneDomainTests` in `Packages/TildoneCore`: passed 28 tests.
- `swift test --filter TildonePersistenceTests`: passed 14 tests.
- `swift test`: passed all 43 TildoneCore tests (28 domain, 14 persistence, 1 sync boundary placeholder).
- `xcodebuild -scheme TildonePersistence -destination 'generic/platform=macOS' ... build`: succeeded for macOS 14.0, arm64 and x86_64.
- `xcodebuild -scheme TildonePersistence -destination 'generic/platform=iOS' ... build`: succeeded for iOS 17.0, arm64.
- `xcodebuild -project Tildone.xcodeproj -scheme Tildone -destination 'platform=macOS' ... -only-testing:TildoneTests test`: succeeded; both existing Mac unit tests passed.
- Full Mac `Tildone` scheme test: app and test targets built, the two unit tests passed, but the generated `TildoneUITests-Runner` exited before establishing an XCTest connection. The result bundle reported one runner-bootstrap failure and no failed test assertion, so Mac UI execution is not validated in this environment.
- `xcodebuild -project Tildone.xcodeproj -scheme 'Tildone iOS' -destination 'generic/platform=iOS' ... build`: succeeded for the iOS scaffold.
- iOS simulator unit-test attempt on iPad (A16), iOS 26.4.1: simulator and test bundles built, but Xcode remained blocked waiting for the target runner to materialize. The run was interrupted after 85 seconds; iOS test execution is unavailable in this environment.

All Xcode builds used isolated `/tmp` DerivedData and `CODE_SIGNING_ALLOWED=NO`; they did not alter application entitlements or project signing settings. Static audits found only Foundation/SwiftData/TildoneDomain imports in persistence, no forbidden framework/target references, `.none` at both `ModelConfiguration` construction sites, no shared-store database files under the repository, and no diff in `Tildone/Models/Todo.swift` or `TodoList.swift`.

## CloudKit exclusion audit

`TildonePersistence` imports only Foundation, SwiftData, and `TildoneDomain`. It has no dependency on `TildoneSync`, SwiftUI, AppKit, UIKit, application targets, CloudKit, or `CKSyncEngine`. Both `ModelConfiguration` construction sites explicitly use `.none`; there is no `.automatic` configuration construction.

## Deferred to Stage 6 or later

- Side-by-side reading/importing/verifying `Todo` and `TodoList`, migration provenance/cutover, rollback retention, and released-store fixtures.
- App UI/repository integration and iPhone UI.
- CloudKit mapping, `CKSyncEngine`, zones, schemas, account discovery/change handling, networking, entitlements, production capabilities, and App Store configuration.
- Local-only-to-account adoption, workspace merge, conflict UI/recovery copies, production tombstone compaction, and sync-state interpretation.

## Deviations and owner-review risks

There is no separate tombstone model: lifecycle state and lifecycle stamp live on the durable content row, which retains the complete record. This is narrower and safer for property-level merges than duplicating identity across content and tombstone tables.

SwiftData stores logical counters as signed 64-bit integers. The domain can represent `UInt64`, so persistence reports `counterOverflow` beyond `Int64.max` instead of truncating or wrapping. At one mutation per second that boundary is operationally unreachable, but it is a deliberate representational limit.

The quarantine table and opaque future sync-state bytes are present, but remote-record ingestion and interpretation remain sync-stage work. Schema V1 currently has no migration stage; the migration-plan wiring must gain an explicit next stage before any stored model changes ship. Real released-store migration compatibility remains unverified because Stage 5 never opens that store and no released fixture is present.
