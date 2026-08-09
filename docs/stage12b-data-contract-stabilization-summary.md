# Stage 12B — Post-Stage-11 data-contract stabilization

**Repository work completed:** 2026-08-09
**Scope:** local/shared persistence, Development CloudKit contract, tests, and rollout documentation
**Production actions:** none

## Outcome

Stage 12B stabilizes the repository's post-Stage-11 data contract without inspecting, modifying, or deploying Production.

- One shared transport-default policy enables automatic synchronization only in non-test Debug processes. macOS and iOS tests and Release builds are transport-off.
- Mac workspace selection is independent of transport activation. A transport-off Release launch can retain the resolved account workspace and local persistence without constructing `CKSyncEngine`; an unrelated nonempty local-only workspace is not adopted automatically.
- V2-to-V3 note-color migration has a deterministic authority order and remains an atomic local sidecar/schema/outbox transaction.
- Mac remote-change migration/reload errors propagate into coordinator freeze/attention handling and cannot be overwritten by a later healthy checkpoint.
- The exact Development contract is source-derived and checked in as `development-cloudkit-contract-manifest.md`.
- A real frozen V2 SQLite fixture exercises the actual missing-color-sidecar migration path.

## Color migration policy

Color conflict authority is ordered independently of launch, upgrade, reconnect, and delivery order:

1. an existing explicit `TDNote` V2 color;
2. a synthesized legacy Mac per-note color, falling back to the legacy Mac global color;
3. a synthesized platform-default color;
4. the implicit yellow used when decoding a V1 note.

The one-time synthesized authorities are encoded in reserved migration replica prefixes while retaining the source replica suffix. Values of the same authority keep normal Lamport counter/replica ordering. This avoids a new CloudKit field and preserves V1 decoding. Repository migration writes the V3 color sidecar, advances workspace schema evidence, and enqueues the V2 note save in one SwiftData transaction. A failed save leaves none of those effects committed; retry and relaunch are idempotent.

## Frozen V2 fixture

The frozen store is:

`Packages/TildoneCore/Tests/TildonePersistenceTests/Fixtures/TildoneSharedStoreV2/TildoneSharedStore-v1/accounts/abcdef00-0000-0000-0000-000000000010/tildone-shared.sqlite`

SHA-256: `e034619f0701283acfbc62f9817ac7f25149eb4061a1a98b7712980e03b6bb25`

It contains representative V2 workspace metadata and migration evidence, serialized sync envelope and zone evidence, active/attempted/superseded outbox work, quarantine evidence, legacy identity mappings, notes and a task, and no V3 `StoredNoteColor` table. The opt-in fixture generator requires an explicit `TILDONE_GENERATE_V2_FIXTURE_PATH`; normal tests only copy and open the frozen artifact.

Released fixture hashes remain unchanged:

- Stage 5 V1 shared-store fixture: `a36abb3b0f597118b28c155db5ab074e8a2af7f0838f7194ea783e9957426ee6`
- Released macOS 1.6.0 build 24 legacy fixture: `2ec613cc46f73561136daa025abe31f79186cdae8867abc8e0e0ff0c6811c5e4`

## Automated evidence

The complete `TildoneCore` suite passed in both configurations on 2026-08-09:

| Check | Result |
| --- | --- |
| Debug `swift test` | 96 tests, 0 failures |
| Release `swift test -c release` | 96 tests, 0 failures |
| `git diff --check` | Passed |
| Entitlement/plist `plutil -lint` | Passed for Mac/iOS entitlements and Info plists |
| Contract generator output versus checked manifest | Exact match |
| Frozen fixture SHA-256 values | Exact match; V1 and released-1.6.0 hashes unchanged |
| Shared `ModelConfiguration` source audit | Every shared persistent/in-memory configuration explicitly uses `cloudKitDatabase: .none` |

The executed shared-package regression set covers:

- the complete Debug/test/Release transport-default matrix;
- real V2 reopen, a forced save interruption with atomic rollback, retry, offline migration, relaunch, and idempotent reopen;
- Mac-first and iPhone-first upgrades and both upload/delivery orders;
- existing explicit V2 remote color authority over either backfill;
- late V1 delivery after V3 migration;
- `serverRecordChanged` merge/retry behavior retaining the pending winner;
- manifest equality with every field emitted by the `TDNote` V1/V2, `TDTask` V1, and `TDClient` V1 encoders, plus optionality and private-zone invariants;
- preservation of attention while the coordinator is frozen after a local refresh failure.

Hosted Mac and iPhone regression tests additionally assert each platform's test-process transport default. The Mac hosted test exercises typed migration and reload failures, including preventing reload after a migration failure.

Fresh platform validation completed on 2026-08-09:

| Check | Result |
| --- | --- |
| macOS generic Debug build | Succeeded |
| macOS generic Release build | Succeeded |
| iOS generic Debug build | Succeeded |
| iOS generic Release build | Succeeded |
| Mac hosted/unit suite | Passed; 2 explicitly opt-in Development/tool tests skipped |
| iPhone hosted/unit suite, iPhone 17 Pro simulator (iOS 26.4) | 11 tests, 1 explicitly opt-in Development lookup skipped, 0 failures |
| Isolated Mac UI launch smoke | 8 launch/appearance variants, 0 failures |
| Isolated iPhone UI smoke, iPhone 17 Pro simulator (iOS 26.4) | Earlier isolated launch passed, 1 test and 0 failures; final 2026-08-09 rerun built successfully but the simulator test runner could not launch after CoreSimulatorService died (`NSMachError -308`), so no new UI result is claimed |

The four app builds used fresh derived-data directories and unsigned generic destinations. Hosted tests used normal local Development signing because an unsigned host cannot launch code that initializes the Development CloudKit container; the live, explicitly opt-in CloudKit tests remained skipped. The Mac and iPhone test-only source-contract assertions were reconciled with the current localized title expression and `presentedNoteID` binding before the final passing runs. Final hosted result bundles are `/tmp/TildoneStage12BFinalMacHosted/Logs/Test/Test-Tildone-2026.08.09_02-43-15-+0200.xcresult` and `/tmp/TildoneStage12BFinalIOSHosted/Logs/Test/Test-Tildone iOS-2026.08.09_02-43-15-+0200.xcresult`; the interrupted iPhone UI-runner diagnostic is separately preserved at `/tmp/TildoneStage12BFinalIOSHosted/Logs/Test/Test-Tildone iOS-2026.08.09_02-44-53-+0200.xcresult`.

The CoreData runtime emitted its pre-existing sandbox diagnostic about store-change notification registration during package tests; it did not produce a test failure.

## Development evidence boundary

Partial live Development evidence was added on 2026-08-08/09 after the owner confirmed CloudKit Console was set to Development, the account/container were disposable, and Development data mutation was approved. No Production access was used.

- A refreshed Development-provisioned x86_64 Debug app launched on a registered Intel Mac running macOS 15.7.7. The app archive was not created or distributed through Apple services. The transferred ZIP SHA-256 was `db0cf4d787ecd9a1db143c1789ea0ec310e0fc225bb6b6fa27cf76652ccf65cd`.
- An iPhone 17 Pro simulator running iOS 26.4, signed into the same disposable iCloud account, initially downloaded the Mac replica's active V2 note, deleted-note tombstone, and explicit yellow V2 color winner. Its local workspace reopened at schema V3 with an empty outbox, so this is live initial-fetch evidence for the existing-color case.
- The Mac then uploaded title `Stage12B Mac Purple` and color `purple`. A read-only, exact-record Development lookup by stable record name decoded that server record successfully with title counter 58 and color counter 60. This proves Mac persistence/upload and the Development mapper for that record; it does not prove normal iPhone convergence.
- The simulator's normal `CKSyncEngine` did not apply that later update after several minutes, foreground termination/relaunch, or a clean Debug reinstall/relaunch. Logs showed automatic sync enabled and a manual fetch for `TildoneUserData`, but it completed without delivering the newer record. The simulator store remained at title counter 6, color `yellow`, color counter 5. This case is a failed/incomplete foreground-convergence result, not a pass.
- After explicit approval to erase only the disposable simulator app data, uninstall/reinstall created a new local workspace and a fresh bootstrap downloaded `Stage12B Mac Purple` with `purple`, title counter 58, and color counter 60. The new workspace was schema V3 with a serialized engine state and an empty outbox. This narrows the failure to incremental catch-up from the prior saved engine state; fresh bootstrap works, but resetting local state is not an acceptable convergence or recovery policy.
- The simulator then edited that record to `Stage12B Mac Green`/`green`. Its local title/color counters advanced to 61/63 under the new simulator replica, the outbox drained to zero, CloudKit logged a successful `SentRecordZoneChanges` TDNote save with no failures, and a correctly prefixed exact-record lookup (`note-9198245a-5b1b-4204-a57c-04fbda527689`) decoded the same title/color/counters from Development. The owner then confirmed the already-running signed Intel Mac consumed and displayed the green update. This establishes simulator-to-Development upload and normal Development-to-physical-Mac catch-up for that record; a physical-iPhone round trip remains a separate check.
- The Mac next uploaded `Stage12B Mac Blue`/`blue`; exact Development lookup decoded counters 74/76. The simulator remained on green counters 61/63 after waiting and normal foreground relaunch. An experimental Debug build using an all-database manual fetch scope instead of the production zone-specific scope also returned immediately without a CloudKit fetch operation or delivery; that unproven change was reverted. Incremental Development-to-simulator catch-up therefore failed reproducibly while direct exact-record lookup and fresh bootstrap continued to work.
- The CloudKit Console query error `Field 'recordName' is not marked queryable` was not worked around by changing schema. Exact record fetch does not require a query index, and no Development schema mutation was made.

The opt-in exact lookup passed in 0.817 seconds. After its temporary simulator environment variables were removed, the complete iPhone hosted suite was rerun: 11 tests executed, the live lookup skipped as designed, and the other 10 passed. Its result bundle is `/tmp/TildoneStage12BFinaliOSTests/Logs/Test/Test-Tildone iOS-2026.08.09_01-36-23-+0200.xcresult`.

No physical iPhone was available for the disposable-account phase. Its simulator behavior is recorded only as simulator evidence and is not substituted for a physical-device result. A later, separately approved main-account physical-device phase is recorded below.

The owner later explicitly approved a restricted, non-destructive Development run using the same main iCloud account on the primary Mac and physical iPhone after confirming neither device contained important Tildone data. Account switching, zone reset/deletion, recovery, and fault injection remained excluded. CoreDevice identified the paired iPhone 14 Pro running iOS 27.0. Although command-line installation was initially blocked because Xcode 26.6 (17F113) provides only the iOS 26.5 device SDK, the owner subsequently installed and launched the developer app from Xcode. CoreDevice then confirmed `studio.cuatro.tildone.ios` as an installed developer app.

A freshly built primary-Mac Debug app was signed with Development APNs and `com.apple.developer.icloud-container-environment = Development`, then launched under the same main account. The account workspace reopened at schema V3 with an empty outbox and existing historical Development test records. The owner confirmed the physical iPhone displayed the same representative existing notes. This establishes signed physical-iPhone initial fetch/read compatibility for that existing V3 workspace. It does not yet establish incremental round trips, background delivery, mixed-record injection, or destructive recovery cases.

For incremental Mac-to-physical-iPhone delivery, the Mac created stable note `c7edbf92-f10a-466a-9fdf-bda9c124ba41` as `Stage12B Blue Physical Mac`/`blue`. Local title/color counters were 934/938 and the durable outbox drained to zero. With both apps left open and no reset or reinstall, the owner confirmed the physical iPhone displayed the new blue note. This establishes a foreground Mac-to-physical-iPhone Development delivery on the approved main-account workspace.

The physical iPhone then edited the same stable note to `Stage12B Green Physical iPhone`/`green`. The already-running Mac consumed it without reset/reinstall and persisted title/color counters 939/941 under iPhone replica `bfe8492a-2c70-4a6e-bf30-8fe1e24ef3b4`; the Mac outbox remained empty. This establishes the reverse physical-iPhone-to-Mac foreground delivery and deterministic field winner on the same record.

The Mac's persisted sync envelope decoded current content-free `TDClient` V1 registrations and system fields for the Mac replica (`platform = mac`) and physical-iPhone replica (`platform = iPhone`), plus one older iPhone registration. Zone-created evidence was true and zone-reset-required was false. This is live receipt/decoding evidence for canonical per-replica TDClient names; it does not exercise a TDClient conflict.

For physical offline/relaunch evidence, the iPhone disabled Airplane/Wi-Fi connectivity, edited the same note offline to `Stage12B offline pink iPhone`/`pink`, force-quit, reopened while still offline, and retained the edit. After reconnecting with both apps open, the owner confirmed success and the Mac persisted the iPhone replica winner at title/color counters 943/942. The Mac workspace remained schema V3, retained serialized engine state, and its outbox was zero. This establishes non-destructive physical-iPhone offline persistence, relaunch, reconnect, and foreground convergence.

The approved main-account scope is now complete. Direct synthetic V1/V2 injection, TDClient conflict injection, account switching, zone/record deletion, reset/recovery, and other fault injection were deliberately not run because they were outside the restricted non-destructive authorization. Their repository-local deterministic coverage remains the applicable evidence.

Before any Production access, the remaining synthetic mixed-version and conflict cases must either receive separate live-Development authorization and exact evidence or remain explicitly local-only evidence accepted by the release owner. See `stage12-controlled-production-rollout-plan.md`.

## Remaining Stage 12B validation boundary

The approved non-destructive physical Mac/iPhone matrix passed, including bidirectional foreground convergence, TDClient receipt, offline iPhone relaunch, reconnect, and outbox drain. The disposable simulator's saved-state incremental catch-up failure remains simulator evidence only because the physical workflow passed without reset. Live synthetic mixed V1/V2 injection, both live upgrade orders, TDClient conflict injection, account switching, deletion, and reset/recovery were not authorized; do not claim those as live results. APNs background wake was not isolated from foreground catch-up and remains unproven.

## Remaining Stage 12C blockers

- A shipping transport pause/resume control and policy that retain the selected account workspace, outbox, engine state, and tombstones.
- The broader Mac sync/attention dashboard and operator-visible recovery guidance.
- Explicit owner-approved local-only adoption and Production zone-reset recovery product flows.
- Any release-owner requirement for additional live synthetic mixed-version or TDClient-conflict evidence beyond the completed non-destructive physical matrix.
- A Production-capable artifact, read-only Production inspection, schema diff/deployment approval, TestFlight, and release qualification; none is authorized by Stage 12B.

## Files and contract documentation

The implementation changes are concentrated in shared domain/persistence/sync sources, Mac and iPhone bootstrap adapters, their tests, the new V2 fixture, `AGENTS.md`, the generated Development manifest, Stage 8–11 summaries, and the controlled rollout plan. The canonical current CloudKit field contract is `development-cloudkit-contract-manifest.md`; do not hand-maintain a parallel field list.

Production CloudKit, Production entitlements/provisioning, archives, uploads, TestFlight, and App Store Connect were untouched.
