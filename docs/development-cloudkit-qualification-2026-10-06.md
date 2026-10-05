# Development CloudKit qualification — 2026-10-06

**Verdict: step 2 is incomplete.** Current local checks pass and selected physical
iPhone pause/restart behavior is verified. The retained missing-task discrepancy
has not been compared on the final Mac/iPhone pair, its cause is not demonstrated,
and the remaining live matrix is open. This report does not close Stage 12C or
authorize Stage 12E. The [2026-10-05 failure](development-real-device-revalidation-2026-10-05.md)
remains historical evidence to investigate, not a passing qualification.

## Source, scope and artifacts

The repository was inspected before changes: clean at
`06f75c15d87866efd783362d86a317fd9d3a5d3a`. This differs from both the initial
October 5 device candidate and its paused-count repair. The qualification run made
no commit or push; the owner subsequently requested committing these changes.

Final candidate: that base plus
[`candidate-source.patch`](evidence/development-qualification-2026-10-06/candidate-source.patch),
SHA-256 `2ae8046a21d530f60deec3bdaa0c5774f354767d9c5f9aa76a43a83f315db0dd`.
The patch includes application/package diagnostics and the new regression file;
documentation is excluded. A fresh patch comparison after builds confirmed that
application and test source still matched. Earlier builds in this session are
interim artifacts and are not the final candidate evidence.

Changes add Debug-only aggregate boundary messages and an opt-in read-only probe
for the specifically labelled retained synthetic fixture. The probe emits counts,
never title/task payloads, account/workspace IDs, record names or error descriptions.
`--inspect-retained-qualification-fixture` also forwards these fixed categories
and counts to the attached device console. It never changes the fixture, cursor,
outbox, zone or workspace. Release ignores the probe and emits no boundary messages.
No demonstrated delivery cause has been repaired; these are investigation tools
and regression coverage, not a claimed convergence fix.

The existing authorization for signed Debug Development builds, installation and
existing-note sync to the owner's private database remains applicable. The owner
also requested using the same account/devices during this session. This supplies
no second account or isolated old-version workspace. No live account switch,
adoption, recovery, downgrade or reset was performed. The affected task was not
edited, deleted, reseeded or reset. No pre-existing note was deliberately edited.
**Personal-data preservation was not compared to a baseline and is unverified.**

Cloud transport remains CKSyncEngine, private database of
`iCloud.studio.cuatro.tildone`, custom zone `TildoneUserData`; shared SwiftData
configurations remain `.none`. Production, Console record queries, schema edits,
signing-setting changes, archives and uploads were not performed.

| Property | Final Mac artifact | Final physical-iPhone artifact |
| --- | --- | --- |
| Build configuration | Signed Debug, arm64 | Signed Debug, arm64 |
| Application ID | `F6HFAVTS49.studio.cuatro.tildone` | Same |
| Effective CloudKit container/environment | `iCloud.studio.cuatro.tildone` / `Development` | Same |
| Effective CloudKit service | `CloudKit` | Same |
| Effective APNs environment | `development` | `development` |
| Debug task access | `com.apple.security.get-task-allow = true` | `get-task-allow = true` |
| Version/build, SDK | 1.6.0/24, macosx27.0 | 1.0/1, iphoneos27.0 |
| `Tildone` SHA-256 | `dd4f885ab868766ad664a7a8b5415c5650761418e363f26707630b9e2d287326` | `4d4c3f20f15e80b797bc7b41822ee43d61ef22ff9b10a7403b2210c868700c25` |
| `Tildone.debug.dylib` SHA-256 | `85c647e85679172612754d0080827fce5b2f0ad0f65eb404b1c965e209958fc6` | `80e9f3348b44619a8e4b4ef81f1ed5cea1676d5c7c4086d78f6da1947d3e143b` |
| Live use in this report | Built/verified, launch held | Installed over existing bundle, launched and paused-relaunched |

Complete signatures passed system verification. Final effective entitlement
extractions matched the earlier verified Development values. Profile UUIDs and
expiration dates, artifact paths and effective entitlements are retained in
[`mac-artifact.json`](evidence/development-qualification-2026-10-06/mac-artifact.json)
and [`ios-artifact.json`](evidence/development-qualification-2026-10-06/ios-artifact.json).
Existing profiles were used without provisioning updates.

Mac: Apple Silicon MacBook Pro, macOS 27.0.1 (`26A434`), Xcode 27.0 (`27A266a`).
Physical device: Diego's iPhone 14 Pro (`iPhone15,2`), iOS 27.2 (`24B5089g`),
paired over Wi-Fi. The serial/UDID remains in temporary local device metadata.
The iPhone 18 Pro, iOS 27.0 (`24A434`),
`E28173F6-B86C-42E3-96C1-4BB961DFFD2F`, was used only for isolated hosted tests.
The available iPad was not substituted for the requested physical iPhone.

The Mac was running an unverified-source Xcode DerivedData copy (PID 28915).
Automation could read its Window menu but could not select the synthetic window;
repeated menu selection returned invalid element IDs and its screenshot was
unavailable. It is not the final candidate. Automatic approval review rejected
normal quit because an unsaved edit might be discarded. The owner was asked to
save and quit it. No force-kill, indirect quit or concurrent live-store candidate
launch was used. The final verified bundle is ready at ignored
`build/Stage12Qualification-20261006/Tildone.app`.

## Missing-task investigation

Observation method: physical screen through Device Hub controlled with the native
computer-use interface; fixed-category console diagnostics through an attached
`devicectl` launch; source inspection and isolated pipeline tests. No server
record export or Console query was used. Times below are Europe/Madrid.

At approximately 00:59–01:00, the current iPhone candidate displayed the retained
`Stage12 Device Check` checklist, including `Paused count repair`. Existing
completion, bold subtask, indentation and other synthetic rows were visible.
The final probe candidate was subsequently rebuilt, signed, installed and launched.
Its startup checkpoint reported:

| Boundary | Final iPhone evidence | Final Mac evidence |
| --- | --- | --- |
| Local persistence | One matching synthetic note and one matching stored task | Not run |
| Lifecycle visibility | One matching active task under an active note | Not run |
| Outbound evidence | Zero matching active/superseded pending rows at inspection | Not run |
| Attempt evidence | Zero attempted matching rows still retained; removed historical attempts cannot be inferred | Not run |
| CloudKit system fields | One matching task has retained decodable system fields | Not run |
| Fetch/checkpoint | Fetch and send start events observed at startup; no new scheduling in this checkpoint | Not run |
| Merge and rendering | Matching task presented before and after startup reload | Not run |

Retained system fields indicate earlier server metadata, not a new exact-payload
server comparison. An empty outbox does not by itself prove delivery. The probe
cannot recover an already-deleted acknowledgment history. No missing-item
re-enqueue or forced reconciliation was performed to make it arrive.

An optional read-only Mac shared-store inspection was attempted against the
explicit account-store path identified from the running process's open files.
SQLite returned `authorization denied`, including with local tool access. No
store rows were read or exported; no store/permission change was made. This does
not establish that the task is absent from Mac persistence.

Source trace on the current candidate:

1. Repository task insertion saves the task, parent meaningful-edit stamp and both
   durable target mutations in one local transaction. Paused UI edits still use it.
2. Resume reconstructs the coordinator from the retained account repository and
   envelope. `refreshPendingEngineChanges` schedules the durable targets, and
   `preparePendingMutation` atomically claims the current row and domain snapshot.
3. A sent-save callback consumes the corresponding in-flight mutation ID and
   acknowledges only that ID's predecessor chain. An older acknowledgment must
   leave a later active edit queued.
4. Fetched modifications decode, merge parents before tasks and call the platform
   remote-refresh handler. Stored cursor updates are staged until fetch completion;
   local refresh failures freeze the coordinator and preserve attention.
5. Mac reload rebuilds domain snapshots; per-note presentation objects and task
   views consume those snapshots. Determining whether the fixture stops before
   fetching, at merge, or at presentation requires the final Mac probe/UI evidence.

The new paused-insertion and old-acknowledgment regressions pass locally. They
do not demonstrate that either race caused the historical device failure.
**Current-pair reproduction: not run; historical failure remains unresolved.**

## Physical iPhone pause observations

The final iPhone launch initially reported Connected to iCloud, no pending row,
and "This iPhone, 6 iPhones, and 1 Mac." This is rendered advisory-summary
evidence, not independently verified device identity or registration uniqueness.

At about 01:05, Pause Sync produced a `pause-completed` diagnostic after operation
cancellation. A separate new synthetic note, ultimately labelled `Stage12 Phone`,
with saved unfinished task `Paused phone task` was created. The paused menu
reported **2 changes waiting to sync** before restart. No operation-start,
scheduling, preparation, acknowledgment or zone-operation boundary followed
`pause-completed` during the observed paused edit interval through 01:09.

Device Hub's paste action initially inserted the phone's existing clipboard
instead of the supplied synthetic label. It was replaced in this new note by
direct typing while transport remained paused, before any resume. No original
note was changed and the retained discrepancy fixture was untouched. The final
saved label/task were visually checked. This automation incident is retained
here; it is not a passing clipboard test or evidence of audited personal-data
preservation.

At about 01:09, terminate-existing/relaunch was performed with the editor closed
and saved row verified. On relaunch the synthetic note/task and paused preference
were retained; the menu again showed **2 changes waiting to sync**. The attached
console reported a presentation reload and the old fixture still presented, but
no CKSyncEngine construction or record/database operation start. This is direct
instrumented evidence beyond the status label. Independent before/after opaque
workspace-ID comparison was not captured. Resume/send results are recorded in
the final observation addendum below.

## Required current-candidate live matrix

Passed means the specific observation below was completed on the final physical
artifact. Not run includes a partially observed case whose required end-to-end
acceptance is still missing. Local/simulator results are listed separately.

| Required application field | Mac → physical iPhone | Physical iPhone → Mac | Supporting current local result |
| --- | --- | --- | --- |
| Title | Not run | Not run | Passed, pipeline/mapper equality |
| Color | Not run | Not run | Passed, green plus color-authority regressions |
| Note kind | Not run | Not run | Passed, eligible one-task memo conversion |
| Memo font | Not run | Not run | Passed, Permanent Marker round trip |
| Task text | Not run | Not run | Passed, paused insertion and newer-edit receipt |
| Rich text | Not run | Not run | Passed, bold/underline spans and text equality |
| Ordering | Not run | Not run | Passed, explicit move and duplicate/reordered deliveries |
| Indentation | Not run | Not run | Passed, indent and outdent |
| Completion | Not run | Not run | Passed, partial checklist completion |
| Deletion | Not run | Not run | Passed, task/note tombstones reject late stale delivery |

The retained old fixture's rendered styles on iPhone are observations, not new
both-direction edits/receipt on this candidate. No intentional field/deletion
test was run against that affected item.

| Required case | Current physical result | Evidence or prerequisite |
| --- | --- | --- |
| Missing-task discrepancy, final pair | Not run | iPhone persists/presents it; final Mac launch held; no demonstrated cause/fix |
| Offline edit, terminate/relaunch, reconnect: Mac → iPhone | Not run | Final Mac launch and controlled disconnection required |
| Offline edit, terminate/relaunch, reconnect: iPhone → Mac | Not run | A pause is not a network-offline test; cable needed to preserve control during Wi-Fi disconnection |
| Conflicting edits in both directions | Not run | Final pair, synchronized checkpoints and explicit two-sided fixture needed |
| Duplicate/resurrection check and final queue on both replicas | Not run | Local duplicate/tombstone tests pass; no final-pair content comparison |
| Pause/edit on iPhone | Passed | Separate saved labelled synthetic note/task; paused queue immediately showed 2 |
| Restart while paused on iPhone | Passed | Same synthetic note/task, old retained fixture and paused queue survived relaunch |
| No iPhone content send/fetch/zone operations while paused | Passed within recorded interval | Active cancellation boundary, no later operation starts; paused relaunch creates no engine; see addendum for final interval |
| Exact live workspace identity retention on iPhone | Not run | Rendered content/queue retained; independent UUID comparison missing |
| Resume and outbound queue on iPhone | Passed, sender side only | Two prepared saves, acknowledgment count 2, scheduling returns to 0, Connected UI with no pending row |
| iPhone paused-edit receipt on final Mac | Not run | Final Mac launch held |
| Mac pause/edit/resume and restart while paused | Not run | Final Mac launch held |
| Mac no paused record/database operations and exact workspace retention | Not run | Instrumented candidate and interval needed |
| Foreground reentry and automatic catch-up, both directions | Not run | Timing acceptance below; no manual Sync Now substituted |
| Failure attention and recovery, both platforms | Not run | Approved local failure injection passes; current physical attention/recovery not induced |
| V2 upgrades: Mac first, iPhone first | Not run | Isolated historical installations/artifacts; current account is not an old-version fixture |
| Mixed supported record versions | Not run | Explicit synthetic record fixtures and isolated live delivery required |
| Existing V2 color authority/conflicts | Not run | Local authority/retry tests pass; live fixture setup missing |
| Canonical TDClient registration per current replica | Not run | UI summary observed; no final-pair canonical registration audit |
| Correct platform/device summary | Not run | Rendered counts alone do not identify the six other installations |
| Registration conflict handling | Not run | New isolated state/mapper retry regression passes, no server conflict induced |
| Account isolation | Not run | Account B and isolated session required; same-account approval cannot supply this |
| Relevant keyboard workflows | Not run | Phone direct typing/Return used, full checklist/attention navigation acceptance incomplete |
| VoiceOver | Not run | Physical owner-assisted or operable accessibility session required |
| Dynamic Type | Not run | Physical largest-size and clipping/focus review required |
| English UI | Not run | Selected phone status seen; full current-pair UI review incomplete |
| Spanish UI | Not run | Current signed physical review required |
| French UI | Not run | Current signed physical review required |
| Simplified Chinese UI | Not run | Current signed physical review required |
| Personal-content preservation comparison | Not run | No pre-run inventory/backups comparison; never infer from visible notes |

## Acceptance criteria for remaining live checks

These are qualification criteria for the next observations, not current latency
claims. Record timestamps for committed edit, receiver foreground activation,
first matching rendered snapshot, acknowledgment and queue zero.

- Keep both clients foreground and online: matching synthetic field values on the
  receiver within **120 seconds**, and both durable queues drained within
  **180 seconds** after the last committed edit. No Sync Now for an automatic case.
- Foreground reentry after a remote edit: matching open snapshots within **60
  seconds** of foreground activation, queue zero within **180 seconds**. A later
  manual checkpoint is a separate diagnostic case and cannot turn that result
  into an automatic pass. Background/APNs delivery is opportunistic and separate.
- Offline edits survive termination/relaunch byte-for-byte in the labelled
  fixture. After reconnect, require deterministic field/stamp convergence, the
  same stable IDs, no extra task/note, no resurrected tombstones, and zero queues
  within **180 seconds**. Conflicts must compare both final replicas, not just labels.
- Pause: after cancellation completes, observe at least **120 seconds** including
  saved synthetic edits, with zero content/zone starts and no engine created on
  paused relaunch. Compare workspace identity, outbox, tombstones and engine state.
  Repeat independently on Mac. Account identity resolution remains permitted.
- Failure: a deterministic non-destructive local reload/save failure must remain
  attention, retain queued content and avoid advancing the successful checkpoint;
  remove the fault/relaunch and require correct catch-up within **180 seconds**.
  Do not inject malformed data or delete a zone in the personal account.
- Historical/client/account cases must follow the
  [isolated fixture plan](development-isolated-fixture-plan-2026-10-06.md), with
  identified starting artifacts and explicit payload/version/stable-ID comparison.
- UI acceptance: keyboard navigation/actions and attention recovery; VoiceOver
  names, state and focus without relying on color; largest accessibility text with
  no clipped action; English, Spanish, French and Simplified Chinese expansion.

## Current local qualification

| Check | Final result | Evidence |
| --- | --- | --- |
| Shared package Debug and Release | Passed: 153 tests each, zero failures (45 domain, 59 persistence, 49 sync) | `core-{debug,release}-probe.log` |
| New qualification regressions | Passed: 3 in both configurations | `DevelopmentQualificationTests.swift`; package logs |
| Full isolated Mac hosted units | Passed: 225/225, zero skips/failures, clean exit | [summary](evidence/development-qualification-2026-10-06/mac-unit-summary.json), `mac-unit-probe.xcresult` |
| Full isolated iPhone hosted units | Passed: 56/56, zero skips/failures, clean exit | [summary](evidence/development-qualification-2026-10-06/ios-unit-summary.json), `ios-unit-probe.xcresult` |
| Signed Mac/iPhone Debug builds | Passed; signatures and Development entitlements verified | `mac-debug-probe.log`, `ios-debug-probe.log`, artifact JSONs |
| Unsigned Mac/iPhone Release builds | Passed; Mac arm64+x86_64, iPhone arm64 | `{mac,ios}-release-probe.log` |
| Release scheme/settings assertions | Passed | `release-settings.log` |
| Source-derived contract | Passed, byte-identical tracked manifest | `manifest-final.md`, SHA-256 `071be605a06740eaad0a94290db8b4c1338bac523c04662fb3b1df06e3a514bf` |
| Three immutable fixture hashes | Passed, exact historical hashes retained | Isolated fixture plan above |
| Plist/entitlement lint, SwiftData `.none`, whitespace | Passed | Source/configuration checks and `git diff --check` |
| UI smoke suites | Not run | Hosted units are not UI-smoke or manual accessibility evidence |

All temporary names above are under `/tmp/tildone-step2-20261006/`. Debug signed
builds used the existing settings, no `-allowProvisioningUpdates`. Release builds
used generic destinations and `CODE_SIGNING_ALLOWED=NO`. Package runs used
`swift test --disable-sandbox --package-path Packages/TildoneCore` with separate
Debug/Release scratch paths. Hosted suites used separate derived data and
`-collect-test-diagnostics never`; iPhone used 45/60-second test allowances.
The explicit live CloudKit round-trip/lookup and legacy developer-tool cases were
excluded as in the earlier local qualification. No hosted test defaulted to a
live personal store.

The iPhone hosted result retains existing FocusState-outside-View runtime warnings.
Build output includes the existing AppIntents metadata-extraction warning and
Xcode dependency-scanner warnings. No new diagnostics API compile warning/error
was found. A passing compile does not establish physical synchronization.

## Remaining prerequisites and holds

1. Owner saves and normally quits the old Mac app so the verified candidate can
   launch without the approval-review unsaved-edit concern. Then inspect the
   retained fixture on both clients, preserve the discrepancy, establish the
   demonstrated cause, repair it, and rebuild/requalify affected cases.
2. Keep the physical iPhone available; provide cable/offline device assistance
   for a controllable network-disconnection test. Complete the both-direction
   fields, offline/conflicts, Mac pause/restart, automatic timing and failure cases.
3. Supply a second disposable account and isolated historical sessions/artifacts
   for the upgrade, mixed-record, registration-conflict and account-isolation
   cases. Current-account approval does not authorize personal-store downgrade,
   adoption, reset or recovery by assumption.
4. Complete physical keyboard, VoiceOver, Dynamic Type and four-language review.
   Personal preservation remains unverified unless an actual baseline comparison
   is supplied and performed.

Full Stage 12C policy/owner acceptance and the separate Stage 12D/12E release gates
remain independent of step 2. No Production refresh or deployment occurred here.

## Final observation addendum

The conservative paused-relaunch observation window was **01:09:45–01:14:23
Europe/Madrid**, 278 seconds. The pre-restart paused window was confirmed by
01:05:46 and remained paused through 01:08:41, at least 175 seconds including
synthetic edits. The [window metadata](evidence/development-qualification-2026-10-06/pause-observation-window.json)
retains UTC bounds. The console instrument was live: it printed presentation
reloads at paused startup, then engine/operation/save events after resume.

Resume Sync was pressed after the 01:14:23 pre-action timestamp. By the 01:15:05
poll, diagnostics showed engine creation, scheduling count 2, two prepared saves,
acknowledgment count 2 and scheduling count 0. This is a **42-second upper bound**
from the conservative pre-action timestamp, not an exact send latency. No Sync
Now was used. The subsequent physical menu showed Connected to iCloud and no
pending row. The retained old fixture probe still reported one stored/active
matching task, zero matching pending rows, and retained system fields. Its receipt
on the final Mac is still unverified.

Durable content-free transcripts:

- [Active startup through pause](evidence/development-qualification-2026-10-06/iphone-active-to-pause.txt).
- [Paused relaunch before resume](evidence/development-qualification-2026-10-06/iphone-paused-relaunch-before-resume.txt).
- [Paused relaunch and resumed saves](evidence/development-qualification-2026-10-06/iphone-paused-relaunch-and-resume.txt).

The phone is left on the final signed candidate with active sync. The new
synthetic note is retained. The diagnostic console remains attached; stopping
that command with a catchable signal would also terminate the app, so it was
not stopped by an indirect app termination. No additional test edits are queued.
The earlier Mac process remained running at the final process check. Step 2
therefore remains incomplete, with the save-and-quit assistance request pending;
no automatic-review bypass or affected-item repair/reset was attempted.
