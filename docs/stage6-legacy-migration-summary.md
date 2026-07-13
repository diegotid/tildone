# Stage 6 Legacy Mac Migration Summary

## Scope and shipping boundary

Stage 6 implements a Mac-only, side-by-side importer from the released
`Todo`/`TodoList` SwiftData store into the Stage 5 shared local store. It adds
durable migration evidence to `TildonePersistence` schema V2 and links the
Mac application target to `TildonePersistence`. The existing legacy models
remain in the `Tildone` module and are not compiled by iOS.

The importer is deliberately not called by `TildoneApp`. The normal Debug and
Release Mac startup code still constructs `Schema([Todo.self, TodoList.self])`
and its existing default `ModelConfiguration`; every shipping window therefore
continues to use the legacy store. No window, note, cleanup, completion, or
other presentation code was routed to the shared repository. The migration
result is “verified, eligible, and not activated,” not a cutover.

No CloudKit, iCloud, `CKSyncEngine`, networking, account adoption, cloud seed,
entitlement, or portal change was added. The Mac target's pre-existing empty
iCloud entitlement arrays are unchanged. Shared configurations still specify
`cloudKitDatabase: .none`. Imported rows create no ordinary `PendingMutation`
rows and `cloudSeedingEverBegun` is durably false.

## Released source discovery

The shipping bundle identifier in both Mac configurations is
`studio.cuatro.tildone`. Every non-test `TildoneApp` process uses the released
schema and disk-backed configuration:

```swift
let schema = Schema([Todo.self, TodoList.self])
let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
```

`LegacyStoreFileSet.releasedShippingURL()` repeats that exact configuration
and returns its `url`; it does not construct a path from naming conventions.
Both ordinary Debug and Release use the same source expression. Debug XCTest
hosts are automatically forced in memory by XCTest environment/class
detection; UI tests also pass a dedicated launch environment and argument.
This test-only guard exists because a hosted test starts the app before its
selected test method. The selected shipping filename is `default.store`.

Read-only filesystem discovery on the development Mac observed these existing
file sets without opening either database or reading content:

- sandboxed shipping location:
  `~/Library/Containers/studio.cuatro.tildone/Data/Library/Application Support/default.store`;
- unsandboxed process location:
  `~/Library/Application Support/default.store`;
- both observed locations had `default.store-wal` and `default.store-shm`.

SQLite/SwiftData may also use `default.store-journal`; the copier recognizes
main, `-wal`, `-shm`, and `-journal`. A source file set is copied coherently to
a private temporary directory and fingerprinted before and after copying. The
original is never passed to `ModelContainer`. The copied source is explicitly
opened with the exact released schema, an explicit URL, no CloudKit, autosave
disabled, and no calls to `save()` or mutating legacy helpers. If a WAL-mode
fixture has no checked-in WAL/SHM, only the throwaway copy is granted write
permission so SQLite can initialize recovery sidecars; the original remains
byte-identical.

Signed sandbox builds resolve Application Support inside the app container.
Unsigned command-line/Xcode-hosted execution can resolve the unsandboxed
Application Support path, which is why migration tests and the developer tool
never select the default as a source. SwiftUI previews in `Note` and `Settings`
are explicitly in memory. Unit migration fixtures use explicit temporary URLs.
Mac UI tests explicitly request an in-memory app store through both environment
and launch argument.

The Stage 5 persistent local-only destination remains under:

`<base>/TildoneSharedStore-v1/local-only/tildone-shared.sqlite`

The Stage 6 API also accepts an exact explicit destination file URL for tests
and the developer tool. It refuses any source/destination main or sidecar path
collision and never points the shared schema at `default.store`.

## Released fields, deletion, and ordering behavior

The released models are unchanged:

- `TodoList`: required `created`, optional `topic`, optional `systemURL`,
  optional `systemContent`, and inverse `[Todo] items`;
- `Todo`: required `what` and `created`, optional `index`, optional completion
  timestamp `done`, and optional owner `list`.

`TodoList.clean()` deletes every task whose text is exactly empty and saves.
It runs when notes lose focus. App termination deletes every empty or complete
note and explicitly deletes its children. Completion fade also physically
deletes a note and its children. No archive/tombstone exists in the legacy
store. Migration runs from a quiescent copied snapshot and never invokes these
methods.

Released visible ordering is reproduced without calling its mutating helper:

1. stable sort by `created` ascending;
2. stable sort by `index ?? Int.max` ascending;
3. for every nil index, assign its final zero-based array position as the
   helper's in-memory side effect.

Thus an index is primary, creation is the fallback/tie order, and original
relationship order is the last tie for equal index and creation date. Nil
indexes appear after indexed rows. Duplicate, negative, missing, and
noncontiguous indexes retain every task. The importer records the exact visible
ordinal and the nil-index normalized value without mutating the source. New
order tokens are fixed-width base-36 ordinals plus a canonical suffix, so their
lexical order exactly matches the released visible order. Gaps left by excluded
transient rows are harmless and deterministic.

## Mapping rules

- Nil and empty note titles remain distinct.
- User notes with no tasks, fully completed surviving notes, and notes left
  only with excluded transient rows remain active shared notes.
- Task text is copied byte-for-byte as a Swift `String`; migration does not
  capitalize, trim, normalize Unicode, or otherwise replay entry-time UI rules.
- Task creation, owner, completion Boolean, and exact completion timestamp are
  preserved. Every imported task has one imported note owner. An orphan or
  inconsistent inverse is a typed `invalidRelationship` failure; there is no
  silent reassignment.
- A task with exactly `what.isEmpty` is classified as a transient row and not
  imported because released cleanup reliably deletes exactly that condition.
  Whitespace-only and all other strings are preserved.
- Any note with either `systemContent` or `systemURL` is classified as an
  installation-local system/update note. It and all children receive durable
  exclusion mappings but no shared content rows, so they cannot later become
  ordinary synchronized user notes.
- `lastMeaningfulEditAt` has no released equivalent. The conservative import
  rule is the maximum of note creation, surviving task creation, and surviving
  completion timestamps. Historic title/text edit times cannot be recovered;
  wall clock is display metadata only and never conflict order.

## Stable identity and version initialization

Every legacy fetched object is keyed by a SHA-256 digest of its encoded stable
SwiftData `PersistentIdentifier` plus entity name. This is content-free,
survives reopening and copied snapshots, distinguishes identical content and
dates, and is never based on enumeration order or object memory identity.

`LegacyIdentityMapping` durably stores the legacy key, entity kind,
classification, stable `NoteID`/`TaskID` when imported, owner legacy key,
visible ordinal, first logical counter, and property count. A UUID is assigned
once and mappings survive restart, rollback, and verification. Excluded rows
retain evidence but have no shared ID or versions.

The destination workspace replica created for migration is persisted as the
migration replica. Counter ranges are allocated atomically with each new
mapping and advance `WorkspaceMetadata.logicalCounter`:

- note: title at `n`, lifecycle at `n+1`, meaningful-edit at `n+2`;
- task: text at `n`, completion at `n+1`, order at `n+2`, lifecycle at `n+3`.

Every property therefore has an independent nonzero version. All imported
lifecycle payloads are active. Counter allocation order has no domain meaning,
but each assigned range and replica are restart-stable, never regress, and
leave all future local edits beyond the stored counter floor.

## Durable state machine and fingerprint

Schema V2 adds `LegacyMigrationState` and `LegacyIdentityMapping` with a
lightweight V1-to-V2 migration. The state machine is:

`not started` → `source inspected` → `destination prepared` →
`copy in progress` → `copy completed` → `verification in progress` →
`verified` → `eligible for cutover`.

Typed failure is a separate durable phase retaining the last completed phase
and a content-free category. Resume from failure requires an explicit option;
failed data/mappings are not deleted or overwritten. The marker persists
migration format, source fingerprint, destination schema version, source and
destination counts, migration replica, logical counter progress, timestamps,
last completed phase, activation state, and cloud-seeding state. One save is
never treated as migration completion.

The fingerprint contains:

- an identity digest over canonical paths plus filesystem device/inode
  metadata;
- a content digest over role, size, and streaming bytes of main and sidecars;
- file and byte counts;
- separately persisted stable inspected entity counts.

Same identity plus changed bytes/counts is `sourceChanged`; a different
identity, including an independently copied database, is `differentSource`
even if bytes match. The whole-store digest is not logged and does not reveal
titles/tasks directly, but it is not a cryptographic commitment to semantic
SQLite rows: harmless SQLite/WAL maintenance changes it. Migration therefore
requires a quiescent source and rechecks it before copy completion and after
verification.

## Batching, restart, and atomicity

Notes are fetched in bounded batches; one note's relationship is materialized
at a time to reproduce the released relationship-order tie exactly. Destination
task writes and mappings are committed in bounded batches. Mapping allocation,
workspace counter progress, imported content, and migration progress are each
transactional. A crash cannot commit content without its corresponding stable
mapping/progress, and reprocessing compares exact domain values before treating
an existing row as success. No content or outbox duplicate can be produced.

The remaining memory bound is the largest single legacy note because exact
relationship-order ties are not queryable as a public SwiftData sort key. The
large-list fixture exercises 500 tasks, but an exceptionally huge one-note
store remains a documented operational risk rather than silently changing tie
semantics.

## Independent verification and cutover eligibility

After copy, all destination repository references are released. Verification
opens a fresh `ModelContainer`/repository and a fresh copied source snapshot.
It directly compares, in process:

- eligible/system/transient counts and every mapping;
- note/task stable IDs and immutable ownership;
- nil/empty title, exact text, creation date, completion payload/date;
- exact order token/order and per-note ordered task IDs;
- active lifecycle and every required property version/replica/counter;
- schema version, duplicate IDs, mapping uniqueness, and absence of ordinary
  pending mutations;
- system-note exclusion and `cloudSeedingEverBegun == false`.

Any mismatch records `verificationMismatch`, retains the destination as
evidence, and blocks eligibility. Tests deliberately corrupt note title, task
text, ownership, completion, order token, order version, mapping ID, count,
property version, and system classification; every case fails verification.
An interruption after `verified` but before the final marker re-verifies and
then reaches `eligibleForCutover` without activation.

## Rollback and Stage 7 boundary

Before shared-only edits or cloud seeding, the untouched legacy store is the
rollback source. Once either begins, automatic rollback could fork history and
is unsafe. The marker distinguishes verified-not-activated from activated and
cloud seeding separately. Stage 6 never sets activated, never seeds cloud, and
never deletes the source or mapping evidence.

Stage 7 must atomically choose one store for the whole Mac process, route all
Mac mutations through repositories, reconcile windows, define the activation
transaction, and retain mappings/source for the owner-approved rollback window.
It must not allow some windows to use each store. Minimum future-removal gates
are an activated marker, successful stable release window, no rollback need,
cloud/account safety decision, support sign-off, and the owner-approved
retention period (architecture recommendation: at least one later stable
release and 90 days).

## Fixtures and developer tool

The checked-in `TildoneLegacy160/default.store` remains the immutable historic
fixture generated from tag 1.6.0 with documented source hashes. Tests also
build sanitized disk fixtures from the exact app-target models for empty,
nil/empty title, Unicode/accent/emoji/multiline, completed/incomplete and
completion dates, nil/duplicate/noncontiguous indexes, identical text/dates,
fully completed, transient empty, system/update, orphan, and 500-task cases.
File-set tests copy WAL/SHM/journal siblings coherently.

`Scripts/run-stage6-migration.sh` is a Debug/XCTest-backed developer command
with a dedicated shared scheme. It requires absolute source and destination
arguments and has no default. It passes them through a locked temporary plist,
uses a unique temporary snapshot root removed only after the test-host process
exits, and launches the host app with an in-memory legacy store. A source equal
to the resolved live shipping URL additionally requires `--allow-live-source`.
Output is limited to phase, counts, mapping count, and the migration replica
ID; titles and task text are not printed.

Example using a copied fixture only:

```sh
Scripts/run-stage6-migration.sh \
  /tmp/TildoneLegacyCopy/default.store \
  /tmp/TildoneStage6Tool/shared.sqlite
```

## Tests and validation

The implementation includes package tests for V1-to-V2 opening, state
transitions, explicit failure/resume, migration-version mismatch, different
and changed source, atomic save rollback (the disk-full/save-failure injection
boundary), stable mappings/versions across restart, idempotent import, and no
outbox. Mac tests cover exact path selection, missing/collision/unwritable
paths, sidecars, historic and generated fixtures, source byte equality, order,
system/empty/Unicode/completion/ownership, large lists, orphan failure, every
durable interruption checkpoint, and independent-verification corruption.

Final validation on 2026-07-13:

- `CLANG_MODULE_CACHE_PATH=/tmp/TildoneStage6Clang SWIFT_MODULECACHE_PATH=/tmp/TildoneStage6Swift swift test --disable-sandbox` in `Packages/TildoneCore`: 58 tests passed (all domain, persistence, sync-module, and version tests).
- `xcodebuild ... -scheme Tildone ... -only-testing:TildoneTests test` with derived data `/tmp/TildoneStage6Mac`: all migration and existing Mac unit tests passed; the opt-in tool test was skipped as intended. The suite includes the 500-task fixture, every durable checkpoint, all destination-corruption cases, the frozen 1.6.0 fixture, and direct independent reopen verification.
- `xcodebuild ... -scheme Tildone -configuration Release -destination 'platform=macOS' ... build` with derived data `/tmp/TildoneStage6MacRelease`: succeeded. Existing unrelated `Note.swift` generic-specialization and `Desktop.swift` immutable-variable warnings remain.
- `xcodebuild ... -scheme 'Tildone iOS' -destination 'generic/platform=iOS' ... build` with derived data `/tmp/TildoneStage6iOS`: succeeded. Its generated Swift file list contains only `TildoneiOSApp.swift`, `TildoneiOSRootView.swift`, and generated assets—no migration or persistence source.
- `Scripts/run-stage6-migration.sh <frozen-1.6.0-default.store> /tmp/TildoneStage6Tool-019f5898.sqlite`: succeeded and then resumed/reverified with `eligible-for-cutover`, 1 eligible note, 3 eligible tasks, and 6 mappings. The destination was freshly reopened for verification. The source remained the sole fixture file at 77,824 bytes with SHA-256 `2ec613cc46f73561136daa025abe31f79186cdae8867abc8e0e0ff0c6811c5e4` before and after.
- `git diff --check`, plist/entitlement lint, generated iOS source-list inspection, and case-insensitive CloudKit/iCloud/network searches passed. Both entitlement files are unchanged; the only migration/shared-store cloud configuration is `.none`; no `CKSyncEngine`, cloud dependency, container, or networking API was added.

The pre-existing Mac UI test target was also attempted with its new explicit
in-memory launch guard. Xcode stalled for 258.896 seconds before workers
materialized and the run was interrupted; no UI test result was produced. Mac
unit tests and both app builds are complete, but UI automation is therefore an
uncompleted validation item caused by the local Xcode test service.

### Live-store validation incident

Before the automatic XCTest-host guard was added, Xcode launched the hosted
app while preparing validation. That process selected the unsigned
`~/Library/Application Support/default.store` configuration and changed its
WAL/SHM metadata. A later UI-test attempt changed SHM metadata even though its
launch environment requested an in-memory store; the UI test launch argument
is now also mandatory. There is no pre-run byte baseline from which to prove
that development machine's live file set was unchanged, so this summary does
not claim it. No live file was deleted, renamed, moved, compacted, or opened by
the migration reader, and no repair was attempted. After the automatic unit
test guard, a focused test and the complete Mac unit suite preserved the live
main/WAL/SHM SHA-256 values exactly. The immutable historic fixture and all
generated/copied fixtures were byte-compared successfully.

## Deferred decisions and risks

- Stage 7 activation and rollback-window duration remain owner decisions.
- Historic public store shapes older than the exact 1.6.0 schema still need any
  obtainable authentic fixtures; current optional-index compatibility is
  exercised, but repository evidence does not prove every App Store version.
- Exact ties rely on the source relationship's visible iteration order, as the
  shipping stable sort does. This is preserved at snapshot time but SwiftData
  does not expose a separately documented durable relationship ordinal.
- The largest single note is the importer memory bound described above.
- Filesystem identity is intentionally strict: moving/copying the source during
  an incomplete migration requires operator review rather than automatic
  equivalence.
- No source deletion, auto rollback, Mac UI cutover, iPhone functionality,
  sync engine, cloud authorization, cloud seed, or entitlement work belongs to
  Stage 6.
- The development machine's live unsandboxed WAL/SHM test-host incident above
  requires owner awareness; the code cannot safely infer or reverse any live
  SQLite change without a known-good baseline.
