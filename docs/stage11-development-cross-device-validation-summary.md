# Stage 11 — Development cross-device validation and reliability hardening

Date started: 2026-07-22
Date completed: 2026-07-28

## Status and recommendation

Stage 11 is complete historical baseline evidence. Stage 12A later found that
post-Stage-11 schema/protocol changes required Stage 12B stabilization and a new
Development revalidation before any Production action. Every original Stage 11 Development gate passed with owner-supplied physical
evidence or directly observed automated evidence: foreground/relaunch sync,
offline durability in both directions, deterministic conflict convergence,
physical concurrent reorder, account isolation, Development-zone deletion and
durable reset latching, and explicitly approved zone recreation/reseeding.

Validation exposed defects in diagnostic typing, Mac scene ownership, remote
checkbox rendering, outbound mutation claiming, Mac task-reorder interaction,
iPhone note navigation, zone-reset status latching, and initial zone/reseed
sequencing. Each demonstrated correctness defect received a focused fix and
regression coverage before its affected physical gate was repeated. The final
Development replica drained to pending zero and remained stable after both
clients relaunched.

No Production CloudKit schema was inspected, changed, or deployed. Release
synchronization remains disabled. No build was uploaded.

## Scope and explicit non-goals

This stage is limited to validating the existing Development CloudKit path on
a signed Mac and physical iPhone, hardening only defects demonstrated by the
validation gates, and preserving evidence for a later readiness decision. It
does not authorize Production schema promotion, Release synchronization,
TestFlight/App Store upload, a production build configuration, automatic zone
recovery, a shipping account-reset/adoption flow, or unrelated product work.

## Starting repository state

- Branch: `main`.
- Starting commit: `83d3817 Harden CloudKit sync for cross-device reliability`.
- The tracked tree matched that commit before Stage 11 edits.
- The root `AGENTS.md` was already untracked and has been preserved unchanged.
- Required architecture, ADR, and Stage 5–10 summaries were read before edits.

## Stage 10 behavior accepted as baseline

Stage 11 accepts only the live evidence actually recorded in the Stage 10
summary:

- The Development schema contained `TDNote` and `TDTask`, and the Development
  private database contained custom zone `TildoneUserData`.
- Signed Debug Mac and physical-iPhone apps opened normally.
- Mac-authored notes reached the iPhone.
- Mac title changes refreshed an open iPhone editor without an unchanged local
  draft reverting the rename.
- Mac task add, edit, and completion toggle refreshed the open physical-iPhone
  checklist after the strict Boolean-decoding defect was fixed. Although the
  earlier summary also described a Mac-originated reorder, the owner has now
  confirmed that the Mac app has no reordering feature; Stage 11 therefore does
  not treat that historical wording as executable reorder evidence.

That baseline evidence alone did not pass the complete foreground round-trip
gate. The later Stage 11 evidence and current outcomes are recorded in the gate
ledger below.

## Repository and configuration audit

The Stage 11 audit confirmed:

- Shared schemes exist for `Tildone`, `Tildone iOS`, and the three package
  products; the Mac/iPhone application and test targets are present.
- Both application entitlements select
  `iCloud.studio.cuatro.tildone`, CloudKit, the Development environment, and
  the development push service.
- Stage 12B replaced the historical launch flag with a shared default policy:
  Debug synchronizes automatically outside tests; tests and both Release
  platforms are transport-off.
- The shared persistent and in-memory SwiftData constructions explicitly use
  `cloudKitDatabase: .none`. The isolated legacy migration reader also uses
  `.none`. `LegacyStoreDiscovery.releasedShippingURL()` intentionally mirrors
  the released legacy configuration only to resolve its exact URL; it does not
  construct or open a shared production store.
- The local package dependency direction remains Domain → Persistence/Sync,
  with `TildonePersistence` explicitly depending on `TildoneDomain` in
  `Package.swift`.
- The source entitlements and explicit Info.plists pass `plutil -lint`.
- Both post-change built iPhone Info.plists contain
  `UIBackgroundModes = [remote-notification]`.
- The signed Debug and Release app products retain Development CloudKit and
  push entitlements. Release compilation does not enable synchronization.
- Debug diagnostic call sites now accept only aggregate values or closed safe
  categories; no logging API parameter accepts an arbitrary content string.
- `git diff --check` passes.

One Xcode dependency-scan warning appeared during hosted Mac tests:
`TildonePersistence` was reported as missing a dependency on
`TildoneDomain`. The package manifest declares that exact dependency, all
package tests and application builds pass, and the warning did not appear in
the four quiet generic builds. It is retained as a build-system observation,
not treated as a functional pass/fail gate or silently ignored.

## Automated baseline and post-fix results

Toolchain: MacBook Pro (`MacBookPro18,3`), macOS 26.5.2 (25F84), Xcode 26.4.1
(17E202), Apple Swift 6.3.1 in Swift 5 package language mode. All Swift package
scratch data and Xcode Derived Data used fresh locations under `/tmp`.

| Check | Initial result | Final post-fix result |
| --- | --- | --- |
| Full `Packages/TildoneCore` suite | 75 passed, 0 failed | 81 passed, 0 failed |
| Signed hosted Mac unit tests | 11 passed, 2 intentional skips, 0 failed | 16 passed, 2 intentional skips, 0 failed; opt-in test then passed separately |
| Signed iPhone unit tests, iPhone 17 Pro simulator, iOS 26.4.1 | 8 passed, 0 skipped, 0 failed | 9 passed, 0 skipped, 0 failed |
| Isolated Mac UI smoke test | Not part of the initial count | 1 passed, 0 skipped, 0 failed |
| Isolated iPhone UI smoke test | Not part of the initial count | 1 passed, 0 skipped, 0 failed |
| macOS Debug generic build | Passed | Passed |
| macOS Release generic build | Passed | Passed |
| iOS Debug generic-device build | Passed | Passed |
| iOS Release generic-device build | Passed | Passed |
| Source entitlement/Info.plist lint | Passed | Passed |
| Built iPhone `UIBackgroundModes` inspection | `remote-notification` present | `remote-notification` present in Debug and Release |
| Shared SwiftData CloudKit scan | Explicit `.none` at each shared-store construction | Passed |
| `git diff --check` | Passed | Passed |

The ordinary hosted suite's two skips remain intentional and are not counted as
ordinary-suite passes:

- `TildoneTests.testDevelopmentCloudKitRoundTripWhenExplicitlyEnabled` is the
  opt-in live Development test. It was subsequently authorized and passed in a
  separate single-test run described below.
- The destructive Stage 6 developer migration-tool test is unrelated and
  requires explicit paths/enablement.

## Opt-in Development CloudKit smoke test

Status: **Passed.**

The owner confirmed a signed Debug Mac host, a disposable Development iCloud
account, disposable test data, and that CloudKit Console was unambiguously set
to `iCloud.studio.cuatro.tildone` / Development. The owner explicitly
authorized the test.

The first single-test command skipped because a shell-prefixed opt-in variable
did not propagate into the hosted XCTest process. The result bundle confirmed
the exact skip reason, so this was classified as a test-procedure issue rather
than an account, provisioning, schema, or product-code failure. Codex generated
a normally signed `.xctestrun` under `/tmp`, added
`TILDONE_RUN_DEVELOPMENT_CLOUDKIT_TESTS=1` only to that temporary hosted-test
environment, and ran the single test without rebuilding or changing the
repository scheme. It passed in 2.600 seconds. The test created, fetched,
decoded, and removed one synthetic `TDNote`; no Production environment was
used.

## Devices, accounts, and Development environment

Current local automated host:

- Mac: MacBook Pro (`MacBookPro18,3`), macOS 26.5.2.
- Simulator used only for automated iPhone tests: iPhone 17 Pro simulator,
  iOS 26.4.1. Simulator evidence is not physical-device evidence.
- Owner's physical device: iPhone 14 Pro, iOS 27.0.

The owner freshly confirmed that the Mac and physical iPhone use the same
disposable account, that CloudKit Console is set to the Development environment,
and that test data plus later Development-zone deletion are
disposable/authorized. The owner then clarified that an iPad is available under
account B, so no current device needs an account switch. Account A and B belong
to the same Family Sharing group; this does not change Tildone's use of each
current user's private CloudKit database.

The account-B device was confirmed as an iPad (7th generation) running iPadOS
18.7.9. It installed and launched the signed Debug iPhone app in compatibility
mode and completed the account-isolation gate.

## Gate ledger

| Gate | Status | Evidence and next boundary |
| --- | --- | --- |
| Phase 1 repository audit and automated baseline | Passed | Results above; one audit defect fixed and all affected checks rerun. |
| Phase 2 hosted Development CloudKit smoke | Passed | Owner-authorized signed Development test passed in 2.600 seconds and removed its synthetic record. |
| Phase 3 complete foreground round trip | Passed | An iPhone-created note appeared on Mac. Its later rename, task reorder, and task deletion converged automatically after an uncertain owner-estimated 5–10 minutes without manual sync or relaunch. Final note deletion reached Mac in about one minute and did not resurrect after relaunch; surviving notes remained. Relaunch exposed duplicate windows for some older Mac notes while iPhone showed them once. The account store had 10 unique active notes but the running app had two desktop coordinator windows and 18 note-sized windows. After the singleton-scene fix passed its regression and automated checks, the owner relaunched the corrected signed Debug build and confirmed everything ran smoothly, including one window per surviving note. The Mac account outbox remained at zero. |
| Phase 4A background notification and foreground catch-up | Passed; background wake inconclusive | With iPhone backgrounded and locked, a Mac-created task was already visible at the first foreground presentation. The owner could not distinguish a true background wake from effectively immediate foreground catch-up. No manual **Sync Now**, data loss, or duplication was observed; everything else remained healthy. The mandatory foreground-catch-up requirement therefore passed without overstating background delivery. |
| Phase 4B iPhone offline durability | Passed | Offline mutations survived force-quit, offline relaunch, and an additional post-relaunch mutation. The independent Home Screen launch temporarily disabled Development sync because it lacked Stage 11's historical scheme opt-in setting, which Stage 12B has since removed; no reinstall/reset occurred. Relaunching from Xcode with that historical setting recovered and drained the durable outbox, Mac converged, and the owner confirmed the final two-client relaunch retained the exact state without loss, duplication, or resurrection. |
| Phase 4C Mac offline durability | Passed | With only the Mac offline, multiple local mutations remained correct through a flagged Debug force-quit/relaunch, and an additional post-relaunch mutation also persisted. After reconnecting the Mac, its durable outbox drained and the online iPhone converged exactly. The owner then confirmed the final flagged relaunch of both clients retained stable state with no loss, duplication, or resurrection. |
| Phase 4D concurrent conflicts | Passed | The different-property, same-task-text, opposing-completion, task delete-versus-edit, note delete-versus-edit, and repeated concurrent-reorder cases all converged automatically with every task present once, pending 0, and stable flagged relaunches. The task deletion case initially exposed an outbox claim race followed by forbidden CKSyncEngine delegate reentrancy; after the deterministic regression-backed fix, deletion won without crash or resurrection. In the note subcase, Mac's automatic completed-note fade-and-delete defeated the isolated iPhone title edit; the note and child task remained absent after **Sync Now** and repeated relaunches. A minimal native Mac reorder interaction removed the final product-operation blocker. |
| Phase 5 account isolation | Passed | The signed Debug iPhone app installed and launched in compatibility mode on the account-B iPad (7th generation), iPadOS 18.7.9. The owner completed the A/B visibility, upload-isolation, and relaunch checks with all results as expected. Family Sharing did not bridge either private CloudKit database. |
| Phase 6 Development zone deletion/latch | Passed | After immediate explicit authorization, the owner deleted account A's Development private `TildoneUserData` zone. No client silently recreated it. The iPhone displayed **Sync needs attention**; the Mac, which has no warning surface, retained content and emitted aggregate `zoneResetRequired` / `attentionNeeded` / `zoneReset` status across distinct process relaunches. |
| Phase 6 explicit Development recovery | Passed | After separate explicit approval, account A's disposable Development replica was reset and reseeded from the intact Mac local-only snapshot. The first attempt exposed a zone/record scheduling race and was stopped without touching the iPhone. After the focused sequencing fix, the owner repeated the approved recovery: `TildoneUserData` was recreated, all 46 durable seed mutations drained to pending 0, the recovered 4-note/29-task snapshot survived Mac relaunch, and a clean physical-iPhone install fetched the same content without a warning. Both clients remained identical at pending 0 after final relaunch. |

## Defects found and repaired

### Free-form diagnostic categories weakened the content-free logging boundary

Audit evidence: Stage 10 documented that Debug logging could not accept titles,
task text, record IDs, account IDs, or workspace paths, but the account-change,
failure, and quarantine logging methods accepted arbitrary `String` values.
Existing call sites supplied safe constants, so no content leak was observed,
but the invariant was convention-based rather than compiler-enforced.

Root cause: the diagnostics facade modeled fixed categories as strings.

Minimal fix:

- account events now use a closed account-change enum;
- quarantine diagnostics accept `QuarantineCategory` directly;
- failures use a closed diagnostic category whose classifier discards all
  associated persistence-error details and maps other errors to a fixed label;
- CloudKit errors pass only the numeric `CKError.Code` raw value.

Regression coverage:
`testDiagnosticFailureCategoriesDiscardContentBearingErrorDetails` supplies a
persistence error with synthetic associated details and an unrelated error
with synthetic description data, then verifies that only fixed aggregate
labels remain. The package suite increased from 75 to 76 tests.

Live retest: not applicable to sync semantics; the change only narrows the
compile-time diagnostic API. All package, hosted app, simulator, build, plist,
and static checks were rerun successfully.

### A multi-instance primary scene reopened duplicate Mac note windows

Live evidence: after the iPhone-created note was deleted, its Mac window closed
in about one minute and the note did not return after both apps relaunched.
Surviving content remained, but the owner observed that a couple of older Mac
notes appeared more than once while each appeared only once on iPhone.

The read-only account-store inspection found 10 unique active notes and no
active notes sharing a title or the same title/task content shape. Content-free
Core Graphics metadata for the running Mac process instead found two invisible
zero-size desktop coordinator windows and 18 note-sized windows. The defect was
therefore duplicate presentation windows, not duplicate CloudKit records or a
migration write during this gate.

Root cause: the primary SwiftUI scene was a `WindowGroup`. Apple defines
`WindowGroup` as multi-instance on macOS, but every `Desktop` instance acts as
the process-wide owner of all manually created note windows. A restored second
scene therefore opened another set. The app now wraps the primary coordinator
in a uniquely identified `Window`, which Apple defines as a single, unique
window. No repository, migration, sync, note, or task data is changed by the
fix.

Regression coverage: `testPrimarySceneUsesSingleUniqueCoordinatorWindow`
requires the primary scene body to be `SwiftUI.Window` and rejects
`SwiftUI.WindowGroup`. It failed on the extracted pre-fix scene and passed after
the one-line scene-type correction. At that checkpoint, the complete signed Mac
suite passed 12 tests with the same 2 intentional skips; the isolated UI smoke
passed 1 test; generic macOS Debug and Release builds passed.

Live retest: passed. The owner launched and relaunched the corrected signed
Debug Mac build and reported that everything ran smoothly. The previously
repeated surviving notes opened once, with no missing note or new iPhone
duplication reported.

### Checkbox retained stale completion during remote live updates

Live evidence: in the first different-property conflict case, the Mac-authored
note title and iPhone-authored task completion both converged. Mac immediately
rendered the task text as completed with a strikethrough, proving that the
updated task value reached the open view, but its checkbox remained visually
unchecked until the Mac app relaunched.

Root cause: `Checkbox` copied its incoming `checked` value into SwiftUI
`@State`. The task row's text branch rendered directly from
`task.isCompleted`, while the checkbox rendered from its retained local copy,
allowing the two completion indicators to disagree after a parent-driven
remote update.

Minimal fix: `checked` is now an ordinary parent-owned view input. Tap handlers
invoke the existing store mutation callback and no longer toggle a second
local copy. Both the checkbox and task text therefore render from the same task
snapshot.

Regression coverage:
`testCheckboxDoesNotRetainParentOwnedCompletionAsLocalState` deterministically
rejects a checkbox `_checked` state wrapper and requires the ordinary `checked`
input. It failed before the fix. After the fix, the targeted regression and
the complete signed Mac suite pass: 13 tests passed with the same 2 intentional
skips. The isolated UI smoke passes after clearing a stale debugger-held prior
Debug process, and generic macOS Debug and Release builds pass.

Live retest: the exact partition passed on the corrected signed Debug Mac
build. Mac first reported `sent-records saved=1 failed=1` while still available,
syncing, and pending 1 with no issue. Without owner or Codex intervention, the
task converged seconds later and both the strikethrough and checkbox updated
together without **Sync Now** or relaunch. The final corrected-build stability
relaunch then passed on both flagged Debug clients with the title and completion
retained, both Mac completion indicators correct, and no duplication or
oscillation. Case 1 is closed.

The delayed iPhone-to-Mac update described below did not lose a mutation and
does not justify a speculative transport or merge change. The imprecise
5–10-minute observation remains recorded as latency evidence for the later
readiness decision.

### Concurrent deletion raced outbound preparation and re-entered CKSyncEngine

Live evidence: when the owner deleted the conflict task on Mac, the app
terminated with CKSyncEngine's client-fatal diagnostic forbidding an awaited
engine call from within a delegate callback. The immediately preceding
content-free diagnostic was
`sync-failure category=persistence-missing-mutation`.

Root cause: outbound preparation selected an active outbox row, read its domain
record, and marked its mutation ID attempted in three separately awaited actor
calls. A concurrent local deletion could replace the still-unattempted row
between those calls, leaving preparation to mark a vanished ID. Error handling
then froze the coordinator and awaited `cancelOperations()` while still inside
the CKSyncEngine delegate callback, triggering CloudKit's reentrancy precondition.

Minimal fix:

- persistence now snapshots the current active outbox payload and marks that
  same row attempted in one repository-actor transaction;
- the sync pipeline claims that atomic prepared value instead of retaining an
  ID across actor suspension points; and
- defensive CKSyncEngine cancellation reachable from delegate handling is
  scheduled in a detached task, so it is never awaited on the delegate stack.

Regression coverage:
`testOutboundPreparationSurvivesConcurrentTaskDeletion` pauses preparation at
the former race boundary, deletes the task so its unattempted row is replaced,
then resumes. It deterministically failed before the fix with
`missingPendingMutation`; afterward it prepares the replacement task tombstone
and proves that exact mutation is marked attempted. The full shared package
suite now passes 77 tests. The signed Mac suite passes 13 tests with 2
intentional skips, the iPhone unit suite passes, and all four generic macOS/iOS
Debug and Release builds pass from fresh temporary DerivedData. The isolated
UI-smoke rerun was interrupted before execution and is not counted as new
post-fix evidence.

Live retest: passed. The owner repeated task delete-versus-edit with the
corrected flagged Debug clients and confirmed the task disappeared on both,
remained deleted after **Sync Now** and repeated relaunches, and both clients
returned to pending 0 without a crash, resurrection, or duplicate.

### Mac lacked a physical task-reorder operation

Live evidence: the mandatory concurrent-reorder case could not begin because
the Mac app had no reorder interaction, despite the domain, repository, and
iPhone app already supporting fractional ordering.

Minimal product fix:

- each Mac task row now exposes a dedicated native drag handle, leaving its
  checkbox and editable text outside the drag source;
- same-note typed drag payloads are accepted at row boundaries and explicit
  list drop targets, while malformed and cross-note payloads are rejected;
- native feedback opens space between surrounding tasks and draws one centered
  accent insertion line;
- `MacSharedStore.moveTask` derives the new `OrderToken` from the same lower and
  upper neighbor rules as iPhone, calls `TildoneRepository.moveTask`, reloads
  local snapshots immediately, and notifies the existing sync coordinator; and
- moves preserve task identity and content and neither recreate nor delete a
  task.

Regression coverage verifies beginning, middle, end, and no-op moves; exact
task identity/content preservation; durable outbox creation; reconstruction
from persistence; malformed/cross-note rejection; and the dedicated handle and
drop-target structure. The signed Mac suite and isolated UI smoke passed.

Live retest: passed after iterative physical feedback corrected drag-preview
composition and insertion-space cleanup. The owner then completed the repeated
concurrent-reorder gate on Mac and physical iPhone. Both clients converged to
one common deterministic order, retained every task exactly once, returned to
pending 0, and remained stable after relaunch.

### Typed iPhone navigation could stall when re-entering a note

Live evidence: while checking the first concurrent-reorder attempt, navigating
from an open note back to the iPhone notes list and then re-entering the note
left the app unresponsive. The supplied debugger snapshot showed the main
thread in the ordinary application run loop rather than a crashing repository
or sync stack.

Minimal fix: existing-note rows now use direct `NavigationLink` destinations
instead of appending note identifiers to the typed navigation path. The
programmatic newly-created-note transition uses
`navigationDestination(item:)`, preserving that workflow without the shared
typed path that stalled.

Regression coverage requires direct existing-note destinations, the item-based
new-note destination, and rejects the prior type-based destination. The signed
iPhone unit suite and isolated create/back/re-enter UI smoke passed.

Live retest: the repeated physical concurrent-reorder procedure completed
without the navigation stall.

### Zone-reset status could regress after the safety latch

Live evidence: after the owner explicitly deleted account A's Development
private `TildoneUserData` zone, the iPhone displayed **Sync needs attention**.
The Mac has no warning surface, but aggregate logs initially showed
`zoneResetRequired` / `attentionNeeded` and then incorrectly regressed to
available activity as later checkpoint events arrived.

Root cause: ordinary checkpoint and local-change status publications did not
preserve the durable zone-reset state.

Minimal fix: status publication now resolves through a latch policy backed by
the persisted coordinator state. Checkpoint completion, ordinary refresh, and
bootstrap cannot publish available status while `zoneResetRequired` remains
set.

Regression coverage:
`testZoneResetStatusStaysLatchedAcrossCheckpointAndLocalChanges` verifies that
idle and syncing publications retain zone-reset availability, attention
activity, the original successful-sync timestamp, and the zone-reset issue.

Live retest: passed. Distinct relaunched Mac process IDs emitted the same
latched aggregate status, the iPhone warning persisted across relaunch, local
content stayed intact, and neither client silently recreated the deleted zone.
The absence of a Mac warning UI is retained as a product limitation, not a sync
failure.

### Initial Development reseed raced records ahead of zone creation

Live evidence: the first explicitly approved recovery successfully adopted the
Mac local-only snapshot into a fresh account-A replica, leaving 4 active notes,
29 active tasks, and 46 durable pending mutations. The coordinator then entered
zone-reset handling and CloudKit cancellation before `TildoneUserData` appeared
in the Development private database. The iPhone was deliberately left
untouched.

Root cause: bootstrap registered both the custom-zone save and its record saves
at once. CKSyncEngine could request records before CloudKit confirmed the zone,
even though custom-zone records cannot be saved until that zone exists. A late
zone-save callback could then clear the persisted reset flag after the
coordinator had already frozen, leaving inconsistent durable and in-memory
state.

Minimal fix:

- bootstrap queues only the zone while it is unconfirmed;
- record changes and scoped fetches remain gated until a successful saved-zone
  event marks the zone created;
- expected missing-zone observations before first creation do not become a
  destructive-reset latch; and
- a late saved-zone callback cannot clear a frozen reset latch.

Deterministic coverage verifies the pre/post-creation scheduling policy,
missing-zone policy, successful creation transition, and late-callback latch
preservation. The final full package suite passed 81 tests; signed Mac units
passed 16 with 2 intentional skips; iPhone units passed 9; isolated Mac and
iPhone UI smokes passed; and all four macOS/iOS Debug/Release builds succeeded.

Live retest: passed after repeating the same explicitly approved
Development-only reset/adoption with the corrected Debug build. The custom zone
was recreated before records were sent, all 46 mutations drained to pending 0,
and the local snapshot survived relaunch. Reinstalling the disposable physical
iPhone app cleared its old latch and fetched identical recovered content. Both
clients remained stable and at pending 0 after final relaunch.

## Manual procedures and observed results

The owner supplied the prerequisite/device information recorded above and
authorized the hosted Development smoke test. Codex directly observed that
test passing. The owner subsequently supplied an account-B iPad, removing the
previous account-isolation device blocker.

During Phase 3, an iPhone-created note appeared on the open Mac.
The owner then reported that its task reorder, task deletion, and rename had
not yet updated on the Mac. The supplied iPhone diagnostics showed repeated
successful sends (`saved=1` or `saved=2`, `failed=0`) with the durable pending
count returning to zero. The Mac diagnostics showed a fetch of seven
modifications and return to available/idle with pending zero and no issue. The
owner later reported that the note updated after an estimated 5–10 minutes,
while noting that this was not a precise measurement.

The owner confirmed that the delayed update required neither manual **Sync
Now** nor a relaunch. Deleting the iPhone-created note then closed its Mac window
in about one minute. It did not reappear after relaunch, and the other notes
remained. Relaunch did expose repeated windows for a couple of older Mac notes;
the same notes appeared once on iPhone. The duplicate-window defect and fix are
recorded above. The owner then launched and relaunched the corrected signed
Debug Mac build and confirmed smooth behavior with the repeated windows gone.
Phase 3 therefore passed.

A read-only, content-free inspection of the Mac account workspace separated
transport/merge state from presentation state without exposing note or task
content. It showed that the newest iPhone-originated note had a newer remote
title version, two active tasks in the remotely assigned order, one deleted
task tombstone, and zero active pending mutations. This proves the reported
mutations reached and merged into the Mac repository. Because the open note
then updated, the observation is classified as delayed automatic convergence,
not lost upload, quarantine, merge rejection, or a persistent stale-view code
defect. The owner subsequently confirmed that the update required neither
**Sync Now** nor relaunch; the uncertain convergence estimate was 5–10 minutes.

For Phase 4A, the owner backgrounded and locked the iPhone before making the
Mac mutation. The new task was already present at the first foreground
presentation. This does not distinguish background delivery from immediate
foreground catch-up, so background wake remains inconclusive. Mandatory
foreground recovery passed with no manual **Sync Now**, loss, or duplication
observed.

Phase 4B was interrupted at reconnect by the Development-only process gate.
After the offline force-quit/relaunch and further local work, the owner restored
cellular access, but the iPhone displayed `icloud.slash` for more than 10
minutes and Mac received no changes. That symbol is emitted only for
`SyncAvailability.disabled`; network failures use the ordinary iCloud symbol
with offline activity. The independently relaunched process had not inherited
the Xcode scheme environment, so synchronization was disabled even though
cellular access had been restored. No reinstall, workspace reset, or data
deletion was performed. The owner then launched the existing app from Xcode
with the historical Debug scheme opt-in (removed by Stage 12B); the slashed/disabled state cleared, the
durable outbox drained, and Mac converged. This validates recovery of the
offline work across the interrupted process launch. The final post-drain
relaunch then passed on both clients with no loss, duplication, or deleted-task
resurrection. Phase 4B therefore passed.

For Phase 4C, the owner disconnected only the Mac, performed the required
multiple mutations, force-quit and relaunched the flagged Debug app while still
offline, confirmed the retained state, and added another mutation. After Mac
reconnected through the iPhone hotspot, its outbox drained and iPhone converged
exactly. The owner confirmed the final flagged relaunch on both clients retained
stable state without loss, duplication, or resurrection. Phase 4C therefore
passed.

Phase 4D case 1 partitioned iPhone by disabling Tildone cellular access while
the Mac remained online through Personal Hotspot. The isolated iPhone toggled
a task and Mac renamed the same note. After reconnect, both semantic edits
converged and survived relaunch, but the open Mac row temporarily disagreed
with itself: completed text was struck through while its checkbox stayed
unchecked until relaunch. The checkbox defect and automated fix evidence are
recorded above. The owner then repeated the exact partition on the corrected
signed Debug build. Mac briefly reported one failed save and pending 1 while
remaining available/syncing with no issue; seconds later automatic processing
completed, and both its strikethrough and checkbox reflected the iPhone task
completion without relaunch or manual **Sync Now**. At that observation point,
no later conflict case had started. The owner then confirmed the final flagged
two-client relaunch retained
the exact title and completion, kept both Mac completion indicators consistent,
and showed no duplication or oscillation. Phase 4D case 1 therefore passed.

For Phase 4D case 2, each partitioned client replaced the same task's complete
text value. After reconnect, Mac's value won. The owner confirmed both clients
showed that one exact value with no hybrid, duplicate, or oscillation, retained
the same winner after flagged relaunch, and returned to pending 0. No manual
**Sync Now** was reported. Phase 4D case 2 therefore passed.

For Phase 4D case 3, the isolated iPhone's final completion value was complete
and the Mac's independently written final value was incomplete. Mac's
incomplete value won. The owner confirmed both clients remained incomplete
after flagged relaunch, Mac showed neither a checked checkbox nor a
strikethrough, no oscillation or duplication occurred, and both clients
returned to pending 0. No manual **Sync Now** was reported. Phase 4D case 3
therefore passed.

Phase 4D initially stopped before case 4 when the owner confirmed that the Mac
app had no reordering feature. A focused native drag interaction was added
through the existing repository/store architecture and physically refined
until its preview, insertion space, centered accent line, and post-drop cleanup
behaved correctly. The owner then repeated the physical concurrent-reorder
case. Mac and iPhone converged to one common order with every task present
exactly once, pending 0, and stable relaunches. Case 4 therefore passed.

The first task delete-versus-edit attempt then exposed the outbox/CKSyncEngine
crash documented above, so the gate stopped immediately. After the
regression-backed fix, the owner repeated the case and confirmed the task
tombstone won on both clients, survived **Sync Now** and repeated flagged
relaunches, and left both clients at pending 0 without crash, resurrection, or
duplication. The task subcase therefore passed.

For note delete-versus-edit, both clients began with the same disposable note
and one incomplete task. With iPhone isolated, the owner renamed the note
there; completing the final task on Mac then triggered the product's automatic
fade-and-delete behavior. The note tombstone won after reconnect. The owner
confirmed that the note and child task disappeared from both clients, remained
absent after **Sync Now** and repeated flagged relaunches, both clients returned
to pending 0, and no crash, resurrection, duplicate, or orphaned task appeared.
The note subcase therefore passed.

For Phase 5, the owner installed and launched the signed Debug iPhone app in
compatibility mode on the account-B iPad (7th generation), iPadOS 18.7.9. The
owner completed the account A/B visibility, mutation-upload isolation, and
relaunch checks and reported every result as expected. Account A content did
not become account B private content, account B writes did not enter account
A's private workspace, and both account-keyed replicas remained stable.
Phase 5 therefore passed.

For Phase 6A, the owner gave immediate explicit authorization and deleted only
account A's `TildoneUserData` zone from the Development private database. The
iPhone eventually displayed **Sync needs attention**. The Mac provides no
warning UI, but its content-free logs proved the same durable
`zoneResetRequired` latch across separate process relaunches. Local content
remained intact, the zone remained absent, and neither client silently
reseeded. Phase 6A therefore passed.

For Phase 6B, the owner separately approved resetting account A's disposable
Development replica and reseeding from the Mac local-only snapshot. The first
attempt adopted the intended 4-note/29-task snapshot and created 46 durable
pending mutations but exposed the zone/bootstrap sequencing defect documented
above, so the procedure stopped before changing the iPhone. After the
regression-backed fix, the owner repeated the same approved recovery. The
Development custom zone was recreated, every seed mutation drained to pending
0, and the recovered Mac state survived relaunch. A clean physical-iPhone
install then fetched identical content without the prior attention warning;
both clients remained identical at pending 0 after final relaunch. Phase 6B
therefore passed.

In particular:

- background delivery was not conclusively distinguishable from immediate
  foreground catch-up; mandatory foreground recovery passed;
- iPhone and Mac offline mutation durability, flagged relaunch persistence, and
  durable-outbox recovery passed in both directions;
- the different-property and same-task-text conflicts passed with stable
  corrected-build relaunches, and the opposing-completion conflict also passed;
  task and note delete-versus-edit passed; repeated concurrent reorder passed
  after the focused Mac product operation was added;
- account A/B visibility and upload isolation passed on two physical devices;
  and
- zone-reset latching, absence of silent reseeding, durable relaunch state, and
  explicitly approved Development recovery all passed.

## Remaining limitations and risks

- The hosted Development smoke test and complete foreground/relaunch gate pass,
  including the duplicate-window fix's corrected-build live retest. Phase 4A
  foreground recovery and both Phase 4B/4C offline directions also pass.
  Every Phase 4D conflict case passes, including physical concurrent reorder.
  Phases 5 and 6 also pass.
- APNs/background delivery was not conclusively observed, but this is
  nondeterministic and the mandatory foreground recovery passed immediately
  enough that the owner could not observe a stale foreground frame.
- macOS has no user-facing synchronization warning surface. Its durable
  zone-reset behavior was proven through content-free logs across process
  relaunches, while iPhone supplied the visible warning.
- Stage 11 now has aggregate iPhone-to-Mac diagnostic evidence and an uncertain
  owner estimate of 5–10 minutes to earlier foreground convergence. Later
  deletion and background/foreground observations converged in about one minute
  or by the first foreground presentation respectively.
- The Xcode dependency-scan warning described above should continue to be
  watched, although the declared package dependency and all builds/tests pass.
- Production remains intentionally unconfigured for this stage; no conclusion
  about production-signed behavior may be drawn from Development builds.

## Binary readiness decision

**Ready to plan Stage 12 controlled production rollout.**

Every mandatory Stage 11 Development gate has owner-supplied or directly
observed evidence, and no demonstrated correctness or privacy failure remains
open. This decision authorizes planning only: it does not promote the CloudKit
schema, enable Release synchronization, upload a build, or infer
production-signed behavior from Development evidence. Stage 12 must retain
explicit controls for those production actions and address the known absence of
a Mac synchronization-warning surface as a product-readiness consideration.
