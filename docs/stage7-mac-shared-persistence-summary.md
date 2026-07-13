# Stage 7 Mac Shared Persistence Summary

## Scope

Stage 7 activates the Stage 5 `TildoneDomain`/`TildonePersistence` store for
the macOS app. The released `Todo`/`TodoList` schema remains in the Mac target
only for the Stage 6 reader and rollback window; it is not used by running Mac
windows after shared-store bootstrap succeeds.

CloudKit, iCloud capability changes, `CKSyncEngine`, networking, and iPhone UI
remain out of scope. Every shared `ModelConfiguration` continues to specify
`cloudKitDatabase: .none`.

## Startup and activation

`MacSharedStoreBootstrapper` is now the process-wide store selection point:

1. It opens the persistent local-only shared destination.
2. An already activated, eligible destination is used directly.
3. A verified eligible destination is atomically marked activated through
   `activateVerifiedLegacyMigration(at:)`.
4. If the destination has no marker and a legacy store exists, the app releases
   its destination lease, runs the Stage 6 side-by-side importer, requires its
   independent reopen/fingerprint verification result, then opens and activates
   that exact destination.
5. A fresh install with neither store uses a new empty shared store. A
   nonempty unverified shared store is rejected rather than silently selected.

The activation transition accepts only `eligible-for-cutover` plus
`verified-not-activated`; it preserves the source fingerprint, mappings,
source store, and `cloudSeedingEverBegun == false`. A second activation attempt
is rejected. XCTest-hosted Mac app launches use an in-memory shared repository,
so tests never select or migrate a live legacy source.

## Mac integration

`MacSharedStore` publishes immutable `MacNoteSnapshot` values built from
`TildoneRepository` domain snapshots. `Desktop` and `Note` no longer use
`@Query`, `ModelContext`, shared stored models, or legacy model mutations.
Note/task creation, rename/edit, completion, insertion ordering, deletion,
empty-row cleanup, and termination cleanup all use typed repository calls.
The adapter calculates fractional order tokens before inserting tasks.

The macOS-specific window coordinator remains outside shared code: manual
`NSWindow` creation, frame autosave, focus tracking, minimize gauges, arrange
commands, AppKit keyboard/pasteboard handling, Focus Filter effects, and fade
animation stay in the app target. Migrated notes retain their released
creation-date window-autosave key.

Legacy system/update notes are already intentionally excluded by Stage 6 and
are not converted into shared user data. `UpdateChecker` therefore no longer
constructs legacy models. It preserves the update-note experience as a
Mac-local `UserDefaults`-backed window, which is deliberately outside shared
content CRUD and cannot enter a future sync data set.

## Tests and validation

- Added a persistence test proving activation rejects partial migrations,
  accepts only verified/eligible state, persists activation, does not seed
  cloud state, and cannot be repeated.
- Replaced the placeholder Mac unit test with an in-memory integration test
  covering shared snapshot CRUD, ordering, completion, deletion, and note
  removal through the domain repository.
- Added a Mac migration integration test that runs Stage 6 on a generated
  fixture, activates only its verified destination, and byte-compares the
  legacy source before and after.
- `swift test --disable-sandbox --filter TildonePersistenceTests` passed:
  30 tests.
- `xcodebuild -project Tildone.xcodeproj -scheme Tildone ... build` passed for
  macOS Debug with signing disabled.
- `xcodebuild -project Tildone.xcodeproj -scheme Tildone ...
  -only-testing:TildoneTests test` passed with the test-host shared-store guard.
- `xcodebuild -project Tildone.xcodeproj -scheme 'Tildone iOS' ... build`
  passed for generic iOS with signing disabled.

## Retention and rollback

The released legacy source, Stage 6 mapping evidence, fingerprints, and shared
destination remain intact. No source deletion, automatic rollback, or cloud
seeding was introduced. As documented in Stage 6, automatic rollback is not
safe after shared-only edits; future removal of the legacy path still requires
the owner-approved retention window and support/release gates.
