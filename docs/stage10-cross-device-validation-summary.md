# Stage 10 — Cross-device validation and production-readiness

Date: 2026-07-19

## Status

The implementation audit, reliability fixes, deterministic tests, Debug
diagnostics, Debug builds, and Release compilation are complete.

Live CloudKit validation is not complete. No success is inferred from simulator
or local tests. The physical-device gates in this document must be performed by
the project owner and their results recorded here before sync is enabled in a
shipping build.

Current shipping safeguards remain intentional:

- CloudKit sync is enabled only in Debug when
  `TILDONE_ENABLE_CLOUDKIT_SYNC=1`.
- Both application entitlements still target the Development CloudKit
  environment and development push service.
- The development schema has not been declared production-ready or promoted by
  this stage.
- The local-workspace adoption and account-workspace reset hatches remain
  explicit, Debug-only operations.

## Specification audited

The audit used `AGENTS.md`, the repository structure ADR, the iPhone product and
architecture document, and the Stage 5 through Stage 9 summaries. The existing
architecture was retained:

- `TildoneDomain` owns immutable snapshots, version stamps, ordering, and merge
  rules.
- `TildonePersistence` owns account-scoped local SwiftData replicas and the
  durable outbox. Every production `ModelConfiguration` explicitly uses
  `cloudKitDatabase: .none`.
- `TildoneSync` maps the durable outbox to `CKSyncEngine` pending changes and
  synchronizes `TDNote` and `TDTask` records in private custom zone
  `TildoneUserData`.
- macOS and iPhone presentation code reads domain snapshots through
  `TildoneRepository`; neither UI talks directly to CloudKit or SwiftData.
- A stable opaque iCloud identity selects the account workspace. Sign-out and
  account-switch events invalidate the open workspace.
- Custom-zone loss remains a latched, non-destructive recovery state. It does
  not silently reseed a deleted zone.

## End-to-end pipeline audit

### Local mutation to upload

1. A UI operation calls a `TildoneRepository` mutation.
2. The repository atomically writes the new domain state, its field-level
   version stamps, and a durable pending mutation.
3. The presentation layer reloads immutable snapshots immediately and notifies
   the coordinator without waiting for the network.
4. The coordinator rehydrates `CKSyncEngine` pending record changes from the
   durable outbox.
5. `nextRecordZoneChangeBatch` asks the pipeline for the current mutation,
   maps it to `TDNote` or `TDTask`, caps the request at CloudKit's 250-record
   server limit, and tracks the exact mutation UUID in flight.
6. A successful `sentRecordZoneChanges` event acknowledges only that exact
   durable mutation. A newer mutation for the same record is not accidentally
   removed.

### Download to UI refresh

1. `CKSyncEngine` fetches private-database changes for `TildoneUserData`.
2. The mapper validates record type, zone, identifier, schema version, field
   types, version stamps, ownership, lifecycle, completion, and ordering.
3. Valid records enter the deterministic field-level merge pipeline.
4. Physical CloudKit deletions become local tombstones. Malformed or
   future-schema records are quarantined and surfaced as an attention state.
5. Repository snapshots are reloaded and the open macOS/iPhone views refresh.
6. The serialized engine checkpoint is persisted beside the local replica so
   relaunch can resume from the last durable state.

### Conflict, retry, and privacy paths

- `serverRecordChanged` merges the server record locally, retains the durable
  local mutation, and schedules the merged record again.
- Duplicate/reordered deliveries and process restarts are covered by
  deterministic merge/outbox tests.
- Account workspaces remain isolated; the iPhone now re-resolves account
  identity every time it becomes active as a defense independent of delivery
  timing for the engine's account event.
- Zone deletion freezes the coordinator and latches `zoneResetRequired`.
- Debug logs accept only categories and aggregate counts. Record IDs, workspace
  IDs, titles, and task text are not accepted by the logging API.

## Defects and weaknesses fixed

### Task-only remote delivery did not necessarily refresh an open checklist

An open iPhone checklist observed equality changes to the note array. A task
record can arrive in a different engine batch while its owning note is
unchanged, so the task list could remain stale.

Every successful repository reload now advances a presentation-only content
revision. The checklist observes that revision and reloads its tasks even when
the note snapshots compare equal.

### An idle title editor could overwrite a remote rename

The title field previously adopted a repository title only when its local text
was empty and always saved on exit. A remote rename could leave stale text in
the field, which was then written back despite no user edit.

The editor now tracks a normalized baseline. It adopts remote titles while not
focused, preserves an active draft while focused, and writes only when the user
actually changed the draft. Leaving an unchanged draft adopts the latest
remote title instead of creating a mutation.

### Foreground account identity relied on event timing

The iPhone previously resumed the existing coordinator whenever a workspace was
already open. It now re-resolves the iCloud account identity on every
foreground transition. If the identity changed while suspended, the old
workspace is closed before a new account workspace is opened.

### Account sign-in could strand the durable outbox

CloudKit clears a sync engine's pending database and record-zone changes on an
account change. The sign-in handler now rebuilds engine pending changes from
Tildone's durable outbox (and re-adds the custom zone when required) before
continuing.

### Local failures could advance beyond the last durable checkpoint

A persistence/encoding failure during an engine event previously surfaced an
attention state but left the coordinator able to accept a newer engine state.
That risks losing deterministic redelivery after relaunch.

Non-CloudKit failures now freeze the current coordinator and cancel its
operations. State-update events are ignored while frozen, preserving the last
durable checkpoint for idempotent redelivery on the next launch.

### Some persistence failures were silently discarded

Remote physical-deletion application and CloudKit system-field encoding no
longer use best-effort `try?`. Failures enter the same freeze-and-relaunch
recovery path.

### Cloud field decoding accepted coercible but wrong types

`NSNumber` bridging previously allowed Boolean values to masquerade as integer
schema/version fields and floating counters to truncate to integers. Integer
decoding now requires an exact, non-floating `CFNumber` representation.

Initial Stage 10 hardening required `CFBoolean` identity for completion values,
but live Development CloudKit validation showed that the server returns the
field as its numeric representation. That rejected two valid task records and
correctly surfaced `malformedRemoteRecord`, but prevented the tasks reaching
the UI. Boolean decoding now accepts in-process `CFBoolean` or exact server
integers 0/1, while still rejecting floats, other integers, and completion/date
inconsistency. Wrong values remain quarantined as malformed remote data.

### Outbound batches could exceed CloudKit's request limit

The delegate previously returned every pending save in one
`RecordZoneChangeBatch`. CloudKit limits one request to 250 combined record
saves/deletes, so a sufficiently large outbox could repeatedly fail with
`limitExceeded`.

The coordinator now preserves engine order while taking at most 250 pending
changes per delegate batch. The engine can request subsequent batches for the
remaining work.

## Debug diagnostics

Debug builds emit content-free messages under:

- subsystem: `studio.cuatro.tildone`
- category: `CloudKitSync`

The messages report checkpoint starts, aggregate fetched/sent counts, account
event categories, deduplicated status transitions, pending mutation counts,
safe quarantine categories, and safe error categories. Release builds compile
these calls as no-ops.

To observe macOS while validating:

```sh
log stream --style compact --level debug \
  --predicate 'subsystem == "studio.cuatro.tildone" AND category == "CloudKitSync"'
```

For iPhone, connect the device to the Mac, open Console, select the iPhone,
enable Debug messages, and use `subsystem:studio.cuatro.tildone` plus
`category:CloudKitSync` as filters.

Do not share note titles, task text, record identifiers, iCloud identifiers, or
an unfiltered device sysdiagnose. The aggregate lines above are sufficient.

## Automated validation

All validation below is local and deterministic. It does not prove CloudKit
service, APNs, background execution, or physical-device behavior.

| Check | Result |
| --- | --- |
| Swift package tests | 75 passed, 0 failed |
| macOS hosted tests | 11 passed, 2 skipped, 0 failed |
| iPhone unit tests on iPhone 17 Pro simulator, iOS 26.4.1 | 8 passed, 0 skipped, 0 failed |
| macOS Debug generic build | Passed |
| iPhone Debug generic device test build | Passed |
| macOS Release generic build | Passed |
| iPhone Release generic device build | Passed |
| Entitlement and Info.plist lint | Passed |
| Built iPhone `UIBackgroundModes` inspection | Contains `remote-notification` |
| Production SwiftData configuration scan | Explicit `cloudKitDatabase: .none` at every production store construction |
| Patch whitespace validation | `git diff --check` passed |

The two macOS skips are intentional:

- the live Development CloudKit round-trip is opt-in and was not run;
- the destructive developer migration tool test is opt-in and unrelated to
  normal application behavior.

The first unsigned simulator launch trapped before XCTest because disabling
code signing also removed the CloudKit entitlement. The correctly signed
simulator run passed all eight tests. This was a test-harness configuration
issue, not a product test failure, and is why device/simulator test runs must
retain normal entitlement signing.

### Added deterministic coverage

- wrong-but-bridgeable CloudKit integers are rejected, and server-normalized
  Boolean 0/1 values are accepted without permitting broader numeric coercion;
- outbound CloudKit record batches preserve order and stop at 250 changes;
- task-only remote delivery advances the iPhone content revision and refreshes
  tasks while the note array remains equal;
- foreground workspace resolution revalidates account identity and does not
  expose the previous account's notes.

Existing package coverage continues to exercise atomic repository/outbox
mutations, exact acknowledgement, duplicate/reordered delivery, convergence,
restart checkpoints, tombstones, quarantine, account isolation, custom-zone
reset latching, and legacy migration safety.

## Manual validation performed by the project owner

Validation began on 2026-07-22. Results below are recorded only from the
project owner's observations; unperformed gates remain pending.

| Gate | Status | Evidence |
| --- | --- | --- |
| Development schema/zone inspection | Passed | Owner confirmed `TDNote` and `TDTask` under Development Schema → Record Types and `TildoneUserData` in the Development private-database zone selector on 2026-07-22. CloudKit Console and both devices use the same iCloud account. |
| Signed Mac ↔ physical iPhone foreground round-trip | Passed | On 2026-07-22 both signed Debug apps opened normally and Mac-authored notes appeared on the physical iPhone. Stage 11 added iPhone→Mac evidence: an iPhone-created note appeared, while its later rename, task reorder, and task deletion converged automatically after an uncertain owner-estimated 5–10 minutes without manual sync or relaunch. The iPhone reported successful saves with zero failures and pending returning to zero; Mac reported seven fetched modifications and no issue. The final note deletion reached Mac in about one minute and did not resurrect after relaunch; surviving notes remained. Relaunch exposed duplicate Mac windows for a couple of older notes while iPhone showed them once. A content-free inspection found unique account records but two invisible Mac desktop coordinators and excess note-sized windows. After the singleton-scene fix passed its regression and automated Mac checks, the owner launched and relaunched the corrected signed Debug build and confirmed smooth operation with each surviving note appearing once. |
| Open-view task-only and title-refresh behavior | Passed | On 2026-07-22 a Mac note-title change updated correctly on the open physical-iPhone view, and leaving the unchanged iPhone title editor did not revert it. New Mac tasks and completion changes initially exposed an overly strict `CFBoolean` identity check. After correcting the mapper and cleanly reinstalling the physical-iPhone Debug build, the owner confirmed initial task download plus live add, edit, completion toggle, and reorder all updated correctly in the open checklist. |
| Remote notification/background catch-up | Passed mandatory foreground catch-up; background wake inconclusive | With the physical iPhone backgrounded and locked, a Mac-created task was already present at the first foreground presentation. The owner could not distinguish a background wake from effectively immediate foreground catch-up. No manual **Sync Now**, data loss, or duplication was observed. |
| Offline edits, force-quit, relaunch, and reconnect | Passed in both directions | During the iPhone offline gate, local mutations survived force-quit, offline relaunch, and an additional mutation. The independent Home Screen launch initially showed `icloud.slash` because it did not inherit the Xcode scheme's `TILDONE_ENABLE_CLOUDKIT_SYNC=1` process environment. No data/reset action was taken. Relaunching the existing app from Xcode with the flag restored cleared the disabled state, drained the durable outbox, and converged on Mac. The Mac-direction gate likewise retained multiple mutations through a flagged offline force-quit/relaunch plus an additional post-relaunch mutation, then drained its outbox and converged exactly on iPhone after reconnect. The owner confirmed stable final flagged relaunches without loss, duplication, or resurrection in both directions. |
| Account sign-out/sign-in/switch isolation | Pending | The owner clarified that an iPad signed into account B is available, so no current device needs an account switch. Its model/iPadOS and signed Debug compatibility-mode launch must be confirmed before the gate. The accounts being in the same Family Sharing group does not merge their private CloudKit databases. |
| Custom-zone deletion latch and explicit recovery | Pending | No Stage 11 destructive approval or observation yet. |
| Development CloudKit opt-in smoke test | Passed | Owner-authorized signed Development test passed in 2.600 seconds after the opt-in variable was supplied through a temporary generated `.xctestrun`; it created, fetched, decoded, and removed one synthetic `TDNote`. |
| Production schema promotion and production-signed build | Blocked on all prior gates | — |

### Gate 1 observations — 2026-07-22

- The owner confirmed `TDNote` and `TDTask` in the Development schema and
  `TildoneUserData` in the Development private database.
- CloudKit Console and both devices use the same iCloud account.
- Both signed Debug applications opened normally.
- Mac-authored notes were visible in the physical iPhone application.
- Mac diagnostics contained no `sync-failure`; one observed save completed
  with one success, zero failures, and the durable pending count returned to
  zero.
- No iPhone diagnostic lines were visible in Console.app, but the attached
  Xcode Debug console showed `checkpoint-started pending=0`, available/syncing
  status, and return to available/idle with pending 0 and issue `none`. The
  missing Console.app output was therefore a viewing/filter issue rather than
  evidence of a failed checkpoint.
- Open-checklist task refresh, title refresh, iPhone→Mac mutations, relaunch,
  duplicate, and resurrection checks were initially unperformed.
- Subsequent live testing confirmed that note-title refresh and unchanged-title
  protection passed. New Mac tasks and Mac completion changes did not update
  the open iPhone checklist on the original build, so Gate 1 requires a
  corrected-build retest. Task reorder remains unvalidated.
- A controlled repeat isolated the failure: Mac reported
  `sent-records saved=2 failed=0`; iPhone reported
  `fetched-records modifications=2 deletions=0`, then availability
  `available`, activity `attentionNeeded`, issue `malformedRemoteRecord`.
  Manual **Sync Now** fetched no new versions and did not make tasks appear.
- The task records had already been consumed into the iPhone engine checkpoint
  and quarantined. Code inspection plus the live server round trip showed that
  completion arrived as CloudKit's numeric `NSNumber` representation rather
  than retaining in-process `CFBoolean` identity. The corrected decoder accepts
  only exact 0/1 server values (or `CFBoolean`) and continues rejecting floats,
  other integers, and completion/date inconsistency. A clean reinstall was
  required to reset the disposable iPhone replica/checkpoint before retest.
- After a clean physical-iPhone reinstall with the corrected signed Debug
  build, the owner confirmed the previously uploaded tasks and completion
  state appeared, then confirmed live Mac task add, edit, completion toggle,
  and reorder all refreshed correctly in the open iPhone checklist. The
  corrected task/title open-view portion of Gate 1 therefore passed.

## Owner-run live validation gates

Run these gates in order. Stop after each gate and report its observations
before code or documentation that depends on the result is finalized.

### Gate 1 — Development foreground round-trip and open-view refresh

Devices: one development Mac and one physical iPhone, both signed into the same
disposable Development iCloud account.

1. In CloudKit Console, select `iCloud.studio.cuatro.tildone` and confirm the
   **Development** environment. Do not select Production.
2. In both Debug schemes, set `TILDONE_ENABLE_CLOUDKIT_SYNC=1`.
3. If the Mac reports that local-workspace adoption is required, use only
   disposable development data. Quit the Mac app, add
   `TILDONE_ALLOW_LOCAL_WORKSPACE_ADOPTION=1` for one launch, confirm the
   expected content, quit, and remove that variable before continuing. Never
   enable this merely to bypass an unexplained error.
4. Start the aggregate Debug log filters on the Mac and physical iPhone.
5. Launch the Mac app first, then install/launch the signed Debug iPhone app
   from Xcode. Wait for both to show iCloud available/idle.
6. Return to CloudKit Console and confirm that the private database contains
   record types `TDNote` and `TDTask`, and custom zone `TildoneUserData`.
   Record whether each item is present; do not edit the schema.
7. On Mac, create one uniquely recognizable test note with two tasks. On the
   foreground iPhone, wait for it to appear exactly once. If it does not appear
   promptly, use **Sync Now** once and note that manual fetch was required.
8. Keep that iPhone checklist open. On Mac, edit only one task, toggle another,
   and reorder them. The open iPhone checklist must update without backing out
   to the note list.
9. Keep the iPhone title field unfocused. Rename the note on Mac. The iPhone
   title must update. Enter and leave the title field without typing; the Mac
   title must not revert.
10. On iPhone, create another note; add, edit, toggle, reorder, and delete
    tasks; rename the note; then delete it. Each state must appear once on Mac,
    including the final deletion.
11. Quit and relaunch both apps. The surviving note and tasks must have the same
    values/order on both devices, no records may be duplicated or resurrected,
    and pending counts should settle to zero/idle.

Expected aggregate log observations:

- `checkpoint-started` appears on explicit/foreground checkpoints;
- the sending device reports `sent-records saved` greater than zero;
- the receiving device reports `fetched-records modifications` or `deletions`
  greater than zero;
- both devices ultimately report availability `available`, activity `idle`,
  pending `0`, issue `none`;
- no `sync-failure`, `zoneResetRequired`, `incompatibleRemoteData`, or
  unexpected `account-change` appears.

Report:

- Mac model/macOS and iPhone model/iOS;
- pass/fail for steps 5 through 11;
- whether **Sync Now** was required and approximate convergence time;
- the aggregate log lines around one Mac→iPhone and one iPhone→Mac change;
- any attention banner/status, duplicate, resurrection, stale open view, or
  crash.

### Gate 2 — Push/background and offline/relaunch reliability

This gate is intentionally deferred until Gate 1 passes.

- Validate a Mac mutation while the signed physical iPhone is backgrounded and
  locked; record whether background delivery occurred and verify foreground
  catch-up.
- Disable network on one device, create and edit multiple records, force-quit
  and relaunch while offline, reconnect, and verify durable outbox convergence
  with no duplicate or lost edits.
- Repeat with simultaneous edits to different fields, then the same field, and
  verify deterministic convergence on both devices.

Exact steps and evidence requirements will be issued after Gate 1 results.

### Gate 3 — Account isolation

This gate is intentionally deferred until Gates 1 and 2 pass. It requires a
second disposable iCloud account and explicit confirmation before signing out
or switching accounts on either device.

The expected invariant is that content from account A is never visible after
account B becomes active, account A's coordinator is cancelled/frozen, and
returning to account A reopens its separate local replica without data loss.

### Gate 4 — Development custom-zone loss and recovery

This destructive gate is intentionally deferred until the earlier gates pass.
It uses only disposable data in the Development environment.

Deleting `TildoneUserData` must latch `zoneResetRequired` and must not silently
re-upload the local replica. Recovery must use the explicit Debug reset/adoption
policy and be documented from observed results.

### Gate 5 — Production promotion

Do not promote or enable Production until all Development gates pass. Apple
documents that App Store builds access Production, that schema deployment
copies types/fields/indexes but not records, and that production schema changes
are additive. Review the exact deployment diff before promoting.

## Remaining risks

- Physical-device foreground and offline/relaunch validation now passes in both
  directions. APNs/background delivery remains inconclusive, and no live
  account-change or live zone-loss observation exists yet.
- No schema has been verified or promoted in Production.
- Release synchronization remains disabled and Development-entitled, so the
  current Release build is a compile validation rather than a distribution
  candidate.
- System scheduling is intentionally nondeterministic; foreground **Sync Now**
  is an immediate checkpoint, while background timing depends on network,
  power, account, and OS scheduling conditions.
- Custom-zone recovery and local-only adoption are intentionally policy gates,
  not automatic behavior.
- Debug telemetry provides lifecycle/count evidence but deliberately omits
  record-level identifiers, so CloudKit Console inspection is still needed for
  schema/zone verification.

## Stage 11 status update — 2026-07-22

Stage 11 began from commit `83d3817`. Its fresh local baseline passed 75 Swift
package tests, the hosted Mac count remained 11 passed with the same two
intentional opt-in skips, the normally signed iPhone simulator count remained
8 passed, and all four Debug/Release generic application builds passed. Source
plists/entitlements linted successfully, and the built iPhone plist retained
`remote-notification`.

The Stage 11 audit found that three diagnostic methods still accepted
free-form category strings even though every existing caller supplied a safe
constant. The APIs were narrowed to closed safe categories and a regression
test now proves that associated persistence-error details and unrelated error
descriptions are discarded. The final package count is 76 passed; hosted Mac
tests remain 11 passed/2 skipped, iPhone unit tests remain 8 passed, and the
isolated iPhone UI smoke test passed 1 test. All four generic builds passed
again after the fix.

The owner confirmed an iPhone 14 Pro on iOS 27.0, the same disposable account
on Mac/iPhone, the Development Console environment, disposable data/zone
permission, and authorization for the hosted test. The Development hosted
CloudKit test passed separately in 2.600 seconds; its ordinary-suite skip is
still intentional. The owner then clarified that an iPad signed into account B
is available, removing the earlier account-isolation device blocker, subject to
a signed Debug compatibility-mode launch check. The foreground row above now
passes. See
`stage11-development-cross-device-validation-summary.md` for the current gate
ledger and blocker list.

During the first Stage 11 iPhone→Mac continuation, the iPhone-created note
appeared on Mac, but its rename, task reorder, and task deletion initially
looked stale. The sending iPhone drained every mutation with zero failures; the
Mac fetched seven modifications and returned to idle with no issue. The owner
then reported that the Mac note updated after an estimated 5–10 minutes, while
explicitly noting uncertainty in that estimate. A read-only
content-free inspection confirmed that the Mac repository held the newer title
version, remote task order, deleted-task tombstone, and no active outbox work.
This is retained as delayed automatic convergence rather than a demonstrated
transport or merge defect. The owner confirmed no manual sync or relaunch was
needed for that update. Final note deletion converged in about one minute and
did not resurrect after relaunch, while surviving notes remained.

That relaunch exposed a different presentation defect: a couple of older Mac
notes appeared in repeated windows although iPhone displayed each once. The
account database contained 10 unique active notes with no matching-title or
matching-content-shape duplicates, while content-free running-process metadata
showed two zero-size desktop coordinators and 18 note-sized windows. The primary
scene was a multi-instance SwiftUI `WindowGroup`, so each restored coordinator
could reopen the complete manual note-window set. It is now a uniquely
identified singleton `Window`. The new regression failed before and passes
after the fix; the complete Mac suite passes 12 tests with 2 intentional skips,
the UI smoke passes, and Debug/Release Mac builds pass. The owner then launched
and relaunched the corrected signed Debug build and confirmed smooth operation
with each surviving note appearing once. Gate 1 therefore passed.

## Recommended next stage

After the owner completes Gates 1 through 4, update this document with devices,
OS versions, observations, timings, and sanitized aggregate logs. The next
stage should then be a controlled production rollout:

1. freeze and review the Development schema;
2. deploy only the reviewed additive schema to Production;
3. add an explicit production build configuration/entitlement and enablement
   decision;
4. run signed production-container/TestFlight smoke tests with disposable
   accounts;
5. add privacy-safe operational monitoring and a rollback/feature-disable plan;
6. only then enable CloudKit sync in the shipping build.

## Apple references

- [CKSyncEngine](https://developer.apple.com/documentation/CloudKit/CKSyncEngine-5sie5)
- [CKSyncEngine account changes](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/event/accountchange)
- [Automatic sync scheduling](https://developer.apple.com/documentation/cloudkit/cksyncengineconfiguration/automaticallysync)
- [Persisting sync engine state](https://developer.apple.com/documentation/cloudkit/cksyncenginestateupdateevent/stateserialization?language=objc)
- [Deploying an iCloud container schema](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema)
