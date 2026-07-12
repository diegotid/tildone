# Stage 5 Shared Persistence Summary

## Scope and boundaries

Stage 5 now includes the persistence hardening pass required before Stage 6.
The work remains confined to `TildoneDomain`, `TildonePersistence`, their tests,
fixtures, the package manifest, and this summary. It does not implement legacy
import/cutover, application integration, networking, CloudKit, `CKSyncEngine`,
entitlements, UI, or automatic SwiftData CloudKit mirroring. The released
`Todo`/`TodoList` sources, project file, and application entitlements are
unchanged.

`Package.swift` keeps `// swift-tools-version: 5.9` as its required first line,
with the requested copyright-style header immediately below it.

The durable rules in `AGENTS.md` remain correct and were not weakened:

- every shared `ModelConfiguration` explicitly uses
  `cloudKitDatabase: .none`;
- the released legacy store is never opened using the shared schema or
  migrated in place;
- stored models and `ModelContext` remain internal to persistence; and
- every shared content mutation atomically records transport-neutral outbound
  evidence.

## Final V1 schema decisions

`TildoneSchemaV1` remains version `1.0.0` with five SwiftData models and no
migration stage because this is still the first shared-store schema.

- `StoredNote` now stores `lastMeaningfulEditAt` with its own
  `lastMeaningfulEditVersionCounter` and
  `lastMeaningfulEditVersionReplicaID`. The date/version pair is independent
  of title and lifecycle.
- `StoredTask` retains independent text, completion, order, and lifecycle
  payload/version pairs and immutable stable note ownership.
- `PendingMutation` remains content-free and transport-neutral. Attempt count
  is the durable boundary between work that was never dispatched and work
  that may be in flight.
- `WorkspaceMetadata` remains the single durable owner of workspace identity,
  replica identity, logical counter, schema version, and uninterpreted future
  engine state.
- `QuarantinedRecord` remains content-free. Accepted opaque IDs are canonical
  note/task record names or canonical typed schema/unknown UUID identifiers.

There are still no SwiftData relationships or physical content deletion in the
shared schema. Note/task lifecycle tombstones remain on their content rows and
are retained indefinitely.

## Meaningful-edit semantics

`Note.lastMeaningfulEditAt` is now a proper versioned domain property.
`Note.merged(with:)` merges its date and version as one payload using the same
deterministic logical-version rule as other mutable properties; wall-clock
maximum no longer chooses the value.

Renaming a note advances the title version and meaningful-edit version
independently. Every task create/edit/toggle/move/delete/restore operation also
advances the owning note's meaningful-edit version. Persistence updates the
task, owning note, workspace counter, task outbox row, and note outbox row in
one `ModelContext.save()`. Independent title/lifecycle/task versions are not
changed as a side effect.

Two logical counters may therefore be consumed by one user operation when two
synchronized records change. Counter density is not an invariant; strict
monotonicity and atomic durability are.

## Physical workspace ownership and concurrency

One repository owns one physical workspace for the lifetime of its
`ModelContainer`. `WorkspaceOwnershipLease` enforces this before a container is
created:

1. a process-local registry excludes duplicate repositories in the same
   process, including equivalent canonical/symlinked paths; and
2. a nonblocking Darwin `flock` on a workspace-owned lock file excludes a
   cooperating second process.

The actor retains the lease as long as it retains the container and releases
both together on deinitialization. A second opener receives
`PersistenceError.workspaceInUse`; it cannot race metadata creation, stable-ID
checks, or logical-counter updates. In-memory repositories remain isolated and
do not claim a disk lease.

This makes actor serialization an implementation detail inside an enforceable
workspace lifetime rather than the only concurrency guarantee. The stored
metadata counter is additionally checked against every stored property version
and pending sequence before it is advanced, preventing silent counter reuse
after malformed or manually altered metadata.

The lock is advisory: code that bypasses the internal repository and directly
opens the SQLite file could ignore it. Stored model types and container
construction are internal, so supported clients cannot do that. Stage 6 must
keep all shared-store access behind the repository/lease boundary.

## Outbox supersession and acknowledgement

The outbox contains only mutation UUID, target kind, opaque stable UUID,
logical sequence, dates, attempt count, and supersession UUID. It contains no
title, task text, record payload, CloudKit operation, or network concept.

Supersession is now state-aware:

- an active row with `attemptCount == 0` was never dispatched and is deleted
  when newer work for the same target is enqueued;
- an active row with an attempt is retained and linked to the newer row because
  it may be in flight;
- schedulable queries return only the newest active row;
- stale acknowledgement of an older mutation removes only that older row and
  cannot remove its successor; and
- acknowledgement of a newer mutation removes that row and reconciles all of
  its superseded ancestors, so no dangling supersession link remains.

Attempts, supersession, acknowledgement, restart, and retries are durable and
idempotent. Metadata validation requires canonical mutation UUIDs, canonical
target UUIDs, a matching stored entity of the declared kind, positive sequence,
consistent attempt date/count, unique active target, existing same-target
newer supersession links, and an acyclic sequence-increasing chain.

## Stored-representation validation and safe diagnostics

Mapping and repository reads reject rather than repair:

- noncanonical or malformed note/task/replica UUID strings;
- duplicate stored identities and duplicate workspace metadata rows;
- invalid ownership, lifecycle, completion/date pairing, order token, schema
  version, logical counter, or nonfinite date;
- malformed workspace singleton key/kind/account UUID/replica/schema/counter;
- counters below any durable content version or pending sequence;
- malformed pending target, attempt, UUID, active-target, or supersession data;
  and
- malformed quarantine UUID/kind/category/schema/content-free identifier.

Errors use typed categories and only canonical opaque identifiers or the fixed
safe marker `invalid`. Corrupt raw values, titles, and task text are never
echoed through errors or quarantine snapshots. Quarantine insertion rejects
arbitrary strings such as user content.

## Fixtures and provenance

Fixture details and hashes are also stored beside the artifacts in
`Tests/TildonePersistenceTests/Fixtures/README.md`.

### Shared V1 on-disk fixture

`TildoneSharedStoreV1` is an actual SQLite-backed SwiftData store generated
through the public repository API from finalized V1 using Xcode 26.4.1. It
contains note/task content, active and superseded outbox rows, workspace state,
and quarantine metadata. Tests copy it to a temporary directory and open the
copy through `TildoneSchemaMigrationPlan`.

SQLite SHA-256:
`a36abb3b0f597118b28c155db5ab074e8a2af7f0838f7194ea783e9957426ee6`.

Because V1 is the first schema, there is no V1-to-V2 migration stage yet. This
fixture is the frozen V1 input required for the first real future migration;
the next schema change must add that stage and migrate a copied fixture.

### Released Tildone 1.6.0 legacy fixture

`TildoneLegacy160/default.store` was generated in a temporary Swift package
whose module was named `Tildone`, using the exact persisted `Todo` and
`TodoList` declarations from Git tag `1.6.0`. It used an explicit test output
URL and never resolved or opened the installed application's production store.
It covers Unicode, nil and duplicate indexes, completion, an empty transient
task, and a system release note.

Legacy SQLite SHA-256:
`2ec613cc46f73561136daa025abe31f79186cdae8867abc8e0e0ff0c6811c5e4`.

Released source hashes:

- `Todo.swift`:
  `09c6ec936192ecb822e58bf8c5fbc2cfd895429664b60b0a8f532caced42c87e`
- `TodoList.swift`:
  `46f0a44bb635ab610d5e1abe16b69ac36c5d39eaff11ed99b234eeac2039739b`

Stage 5 does not import this fixture. A test treats it as immutable bytes,
creates and mutates a separate shared store, then verifies the fixture remains
byte-for-byte identical. The user's production path was deliberately not
resolved, read, launched, or checksummed, because doing so would weaken the
stronger rule that Stage 5 never touches it.

## Expanded test coverage

The persistence suite now covers:

- canonical full round trips including independent meaningful-edit versions;
- malformed stored notes/tasks, canonical UUIDs, ownership, dates, versions,
  completion, order, lifecycle, and future schema;
- duplicate metadata and stable identities;
- one lifetime owner for a physical store and same-store concurrent rejection;
- logical-counter monotonicity and replica retention across reopen;
- failed create/update/delete rollback of content, counter, and outbox;
- atomic task-plus-note scheduling and independent property versions;
- undispatched coalescing, in-flight retention, retry, restart, old-first and
  new-first acknowledgement, and stale acknowledgements;
- malformed workspace/outbox/supersession/quarantine metadata and content-free
  diagnostics;
- actual copied V1 fixture opening through the migration plan; and
- immutable released-1.6.0 fixture and sentinel legacy-path non-modification.

## Validation matrix (2026-07-13)

Toolchain: Xcode 26.4.1 (build 17E202), Apple Swift 6.3.1 in Swift 5 package
language mode, macOS 26.5.2, macOS 26.4 SDK, and iOS 26.4 SDK. SwiftPM cache
paths were redirected to `/tmp`; Xcode commands used isolated `/tmp`
DerivedData and `CODE_SIGNING_ALLOWED=NO`. Xcode package/build commands required
execution outside the managed nested sandbox so Xcode could access its normal
caches and CoreSimulator services.

- `swift test --disable-sandbox --filter TildoneDomainTests` with temporary
  module caches: passed 28 tests.
- `swift test --disable-sandbox --filter TildonePersistenceTests`: passed 25
  tests.
- `swift test --disable-sandbox`: passed all 54 package tests (28 domain, 25
  persistence, 1 sync boundary placeholder).
- `xcodebuild -project Tildone.xcodeproj -scheme TildonePersistence
  -destination 'generic/platform=macOS' -derivedDataPath
  /tmp/TildoneStage5PackageMac CODE_SIGNING_ALLOWED=NO build`: succeeded for
  arm64 and x86_64, macOS 14.0.
- The same persistence build with `-destination 'generic/platform=iOS'` and
  `/tmp/TildoneStage5PackageiOS`: succeeded for arm64, iOS 17.0.
- `xcodebuild -project Tildone.xcodeproj -scheme Tildone -configuration Debug
  -destination 'platform=macOS' -derivedDataPath /tmp/TildoneStage5MacApp
  CODE_SIGNING_ALLOWED=NO build`: succeeded. The pre-existing explicit
  specialization warning in `Note.swift` remains; persistence introduced no
  warning.
- The Mac command with `/tmp/TildoneStage5MacTests`,
  `-only-testing:TildoneTests test`: passed both existing unit tests.
- `xcodebuild -project Tildone.xcodeproj -scheme 'Tildone iOS'
  -configuration Debug -destination 'generic/platform=iOS'
  -derivedDataPath /tmp/TildoneStage5iOSApp CODE_SIGNING_ALLOWED=NO build`:
  succeeded.
- The iOS command targeting the booted iPhone 17 Pro simulator
  `8D41C6D2-4E49-4831-A1B8-D81D5B962FF0`, using
  `/tmp/TildoneStage5iOSTests` and `-only-testing:TildoneiOSTests test`:
  passed the scaffold unit test.

The Mac UI test runner was not launched. It launches the shipping Mac bundle
identity and the current UI tests do not inject a safe legacy-store URL; running
it could open or mutate the user's production default store. Building the UI
test bundle occurred as part of unit-test preparation, but execution remains a
Stage 6/app-test harness prerequisite. This is a deliberate safety limitation,
not a passing UI result.

## Static audits

- Persistence imports Foundation, SwiftData, TildoneDomain, and Darwin only.
  Darwin is used solely for the cross-process workspace lock. There are no
  SwiftUI, AppKit, UIKit, ServiceManagement, application-target, TildoneSync,
  CloudKit, `CKSyncEngine`, URLSession, or Network imports/references.
- Both production `ModelConfiguration` construction sites explicitly use
  `cloudKitDatabase: .none`; no automatic/private/public CloudKit database
  configuration exists in the package.
- `git diff --exit-code` confirms no changes to `Todo.swift`, `TodoList.swift`,
  `Tildone.entitlements`, or `project.pbxproj`.
- Fixture hashes remained identical after all tests.
- `git diff --check` passes and no shared-store database was produced outside
  test resources or isolated `/tmp` locations.

## Remaining risks and Stage 6 readiness

- The file lock is advisory and is tested for same-process/same-disk exclusion;
  a dedicated subprocess crash/lock-stealing longevity test would further
  strengthen cross-process evidence.
- SwiftData emits harmless Core Data registration diagnostics during many
  short-lived in-memory test containers on this toolchain.
- V1 is frozen by the checked-in fixture, but there is no V2 migration yet.
- The released legacy fixture proves schema provenance and gives Stage 6 a safe
  source, but import mapping, verification markers, interruption recovery,
  idempotency, rollback retention, and cutover are intentionally not built.
- Mac UI tests need dependency-injected store locations before they can be run
  without risking production legacy data.
- CloudKit/sync transport, accounts, networking, app integration, and
  entitlements remain entirely unimplemented.

Stage 6 importer development is safe to begin against copied fixtures and
temporary destinations. Stage 6 cutover is not yet safe to ship: it must first
implement side-by-side read-only legacy access, verified/idempotent mapping,
interruption recovery, production-path injection, rollback evidence, and a
safe Mac UI/integration test harness. No Stage 6 behavior was implemented in
this pass.
