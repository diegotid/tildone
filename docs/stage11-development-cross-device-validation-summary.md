# Stage 11 — Development cross-device validation and reliability hardening

Date started: 2026-07-22

## Status and recommendation

Stage 11 is in progress and is **not ready to plan Stage 12 controlled
production rollout**. The repository audit, automated baseline, and opt-in
Development CloudKit smoke test pass, and one privacy-hardening defect found by
the audit has been fixed and covered by a deterministic regression test. The
foreground/relaunch gate then exposed a separate duplicate Mac-window defect;
its minimal fix and deterministic regression pass locally, and the corrected
signed Debug build passed the affected live relaunch retest. The
owner clarified that a second physical device is available: an iPad signed into
account B. The account-isolation prerequisite is therefore no longer blocked,
subject to confirming that the signed Debug iPhone app installs and launches in
iPhone compatibility mode on that iPad.

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
- Mac task add, edit, completion toggle, and reorder refreshed the open
  physical-iPhone checklist after the strict Boolean-decoding defect was fixed.

This evidence does not pass the complete foreground round-trip gate. Stage 11
has now exercised part of the iPhone-to-Mac direction, but final note deletion,
relaunch stability, duplicate prevention, and resurrection checks remain
pending.

## Repository and configuration audit

The Stage 11 audit confirmed:

- Shared schemes exist for `Tildone`, `Tildone iOS`, and the three package
  products; the Mac/iPhone application and test targets are present.
- Both application entitlements select
  `iCloud.studio.cuatro.tildone`, CloudKit, the Development environment, and
  the development push service.
- Debug synchronization requires `TILDONE_ENABLE_CLOUDKIT_SYNC=1`; both Mac
  and iPhone feature gates compile to `false` outside `DEBUG`.
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
| Full `Packages/TildoneCore` suite | 75 passed, 0 failed | 76 passed, 0 failed |
| Signed hosted Mac unit tests | 11 passed, 2 intentional skips, 0 failed | 13 passed, 2 intentional skips, 0 failed; opt-in test then passed separately |
| Signed iPhone unit tests, iPhone 17 Pro simulator, iOS 26.4.1 | 8 passed, 0 skipped, 0 failed | 8 passed, 0 skipped, 0 failed |
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
current user's private CloudKit database. The iPad model/iPadOS version and
signed Debug compatibility-mode launch remain to be confirmed before Phase 5.

## Gate ledger

| Gate | Status | Evidence and next boundary |
| --- | --- | --- |
| Phase 1 repository audit and automated baseline | Passed | Results above; one audit defect fixed and all affected checks rerun. |
| Phase 2 hosted Development CloudKit smoke | Passed | Owner-authorized signed Development test passed in 2.600 seconds and removed its synthetic record. |
| Phase 3 complete foreground round trip | Passed | An iPhone-created note appeared on Mac. Its later rename, task reorder, and task deletion converged automatically after an uncertain owner-estimated 5–10 minutes without manual sync or relaunch. Final note deletion reached Mac in about one minute and did not resurrect after relaunch; surviving notes remained. Relaunch exposed duplicate windows for some older Mac notes while iPhone showed them once. The account store had 10 unique active notes but the running app had two desktop coordinator windows and 18 note-sized windows. After the singleton-scene fix passed its regression and automated checks, the owner relaunched the corrected signed Debug build and confirmed everything ran smoothly, including one window per surviving note. The Mac account outbox remained at zero. |
| Phase 4A background notification and foreground catch-up | Passed; background wake inconclusive | With iPhone backgrounded and locked, a Mac-created task was already visible at the first foreground presentation. The owner could not distinguish a true background wake from effectively immediate foreground catch-up. No manual **Sync Now**, data loss, or duplication was observed; everything else remained healthy. The mandatory foreground-catch-up requirement therefore passed without overstating background delivery. |
| Phase 4B iPhone offline durability | Passed | Offline mutations survived force-quit, offline relaunch, and an additional post-relaunch mutation. The independent Home Screen launch temporarily disabled Development sync because it lacked the scheme environment; no reinstall/reset occurred. Relaunching from Xcode with `TILDONE_ENABLE_CLOUDKIT_SYNC=1` recovered and drained the durable outbox, Mac converged, and the owner confirmed the final two-client relaunch retained the exact state without loss, duplication, or resurrection. |
| Phase 4C Mac offline durability | Passed | With only the Mac offline, multiple local mutations remained correct through a flagged Debug force-quit/relaunch, and an additional post-relaunch mutation also persisted. After reconnecting the Mac, its durable outbox drained and the online iPhone converged exactly. The owner then confirmed the final flagged relaunch of both clients retained stable state with no loss, duplication, or resurrection. |
| Phase 4D concurrent conflicts | In progress; cases 1–3 passed, case 4 blocked on Mac UI | The different-property case passed after the regression-backed checkbox fix and final flagged relaunch. Mac's complete text won the same-task-text case, and Mac's incomplete value won the opposing-completion case. In each, both clients converged to one exact internally consistent value without hybrid, duplicate, or oscillation, retained it after flagged relaunch, and returned to pending 0. The owner then confirmed that the Mac app has no reordering feature, so the required cross-device conflicting-reorder case cannot currently be executed. No reorder attempt was made. Delete-versus-edit also remains pending. |
| Phase 5 account isolation | Pending iPad prerequisite check | An account-B iPad is available. Its model/iPadOS and ability to install/launch the signed Debug iPhone app in compatibility mode must be confirmed before the gate. |
| Phase 6 Development zone deletion/latch | Pending | General disposable Development-zone permission was confirmed; destructive execution still requires immediate final confirmation when reached. |
| Phase 6 explicit Development recovery | Pending | May occur only after the latch is proven and the owner separately approves recovery. |

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

## Manual procedures and observed results

The owner supplied the prerequisite/device information recorded above and
authorized the hosted Development smoke test. Codex directly observed that
test passing. The owner subsequently supplied an account-B iPad, removing the
previous account-isolation device blocker.

Phase 3 is now in progress. An iPhone-created note appeared on the open Mac.
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
with `TILDONE_ENABLE_CLOUDKIT_SYNC=1`; the slashed/disabled state cleared, the
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
completion without relaunch or manual **Sync Now**. No later conflict case has
started. The owner then confirmed the final flagged two-client relaunch retained
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

Phase 4D stopped before case 4 when the owner confirmed that the Mac app has no
reordering feature. The required physical cross-device conflicting-move case
therefore has no valid Mac-side operation in the current product. No result is
inferred and no reorder attempt was made. The gate remains pending until that
product/UI scope is resolved; delete-versus-edit has not started.

In particular:

- background delivery was not conclusively distinguishable from immediate
  foreground catch-up; mandatory foreground recovery passed;
- iPhone and Mac offline mutation durability, flagged relaunch persistence, and
  durable-outbox recovery passed in both directions;
- the different-property and same-task-text conflicts passed with stable
  corrected-build relaunches, and the opposing-completion conflict also passed;
  reorder is blocked by the absent Mac reordering UI, and delete-versus-edit
  remains unconfirmed;
- account A/B visibility and upload isolation have not been observed; and
- zone-reset latching, absence of silent reseeding, durable relaunch state, and
  explicit Development recovery have not been observed.

## Remaining limitations and risks

- The hosted Development smoke test and complete foreground/relaunch gate pass,
  including the duplicate-window fix's corrected-build live retest. Phase 4A
  foreground recovery and both Phase 4B/4C offline directions also pass.
  Phases 4D–6 remain uncompleted.
- APNs/background delivery was not conclusively observed, but this is
  nondeterministic and the mandatory foreground recovery passed immediately
  enough that the owner could not observe a stale foreground frame.
- Conflict convergence, account privacy, and zone-loss safety remain unproven.
  Account privacy now has a candidate account-B iPad but still requires
  compatibility-mode installation and live validation.
- Stage 11 now has aggregate iPhone-to-Mac diagnostic evidence and an uncertain
  owner estimate of 5–10 minutes to earlier foreground convergence. Later
  deletion and background/foreground observations converged in about one minute
  or by the first foreground presentation respectively.
- The Xcode dependency-scan warning described above should continue to be
  watched, although the declared package dependency and all builds/tests pass.
- Production remains intentionally unconfigured for this stage; no conclusion
  about production-signed behavior may be drawn from Development builds.

## Binary readiness decision

**Not ready to plan Stage 12 controlled production rollout.**

Exact blockers to readiness: all concurrent conflict cases, account isolation
using the account-B iPad, and
Development zone-reset latch/explicit recovery have not passed. The opt-in
Development CloudKit smoke test did pass.
A Stage 12 scope will be proposed only after every mandatory Development gate
has owner-supplied or directly observed evidence and no unresolved correctness
or privacy failure remains.
