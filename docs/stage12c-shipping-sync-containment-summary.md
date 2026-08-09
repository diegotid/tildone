# Stage 12C — Shipping sync containment and recovery UX summary

**Date:** 2026-08-09  
**Repository boundary:** Stage 12B was already committed separately as `857e056` and the working tree was clean before Stage 12C began.  
**Production actions:** none. Production CloudKit, Production entitlements/provisioning, archives, uploads, TestFlight, and App Store state were not inspected or changed.

## Outcome

Stage 12C closes the remaining repository-local containment blockers identified by the Stage 12A architecture review and Stage 12B stabilization summary. It adds durable account-scoped transport pause/resume, compact sync/attention presentation, one narrowly bounded local-only adoption flow, non-destructive reset/incompatibility guidance, and deterministic shared schemes/configuration assertions.

This work does not enable Release transport. The Stage 12B matrix remains authoritative:

| Build context | Default transport | Persisted pause effect |
| --- | --- | --- |
| Debug app outside tests | Enabled for the resolved account workspace | Can keep that otherwise-enabled transport paused |
| XCTest/UI-test process | Disabled | Cannot enable transport |
| macOS Release | Disabled | Cannot enable transport |
| iOS Release | Disabled | Cannot enable transport |

## Implemented behavior and invariants

### Account-scoped transport pause/resume

- Active/paused intent is stored outside the content and migration schemas in installation-local `UserDefaults`, keyed by the opaque account workspace UUID. A missing value preserves the existing active Debug default; an invalid value fails closed to paused.
- The build/test default remains authoritative. A persisted preference may pause transport that would otherwise be enabled, but it cannot enable Release or test transport.
- Pausing persists intent before cancellation, detaches local CRUD from the coordinator, freezes the coordinator, and cancels CloudKit engine operations. The selected account repository stays open.
- Once frozen, late engine data/checkpoint callbacks are ignored. They cannot apply fetched data, serialize a newer engine checkpoint, or acknowledge durable outbox work after pause. Account-change callbacks remain enabled solely to preserve account isolation.
- Paused local CRUD continues to create ordinary durable outbox mutations and tombstones in the same account workspace. The workspace UUID, replica identity, system fields, serialized sync envelope, attempt counts, and pending acknowledgements are not reset or rewritten by pause.
- A paused relaunch opens the same account workspace and does not construct a `CKSyncEngine`; therefore it performs no zone/record send or fetch work. Resolving the current iCloud account identity is still required before an account workspace can be opened safely.
- Resume re-resolves and compares the current account identity before changing the persisted state to active. A mismatch invalidates the old workspace presentation. A match constructs a new coordinator from the same repository and serialized engine state, then schedules the existing durable work normally.
- Pause/resume never selects `local-only`, creates or recreates a zone, reseeds data, clears a tombstone, or acknowledges a mutation merely because the transport state changed.

### Compact macOS sync and attention UI

- The menu-bar item and a compact fixed-size **iCloud Sync** window expose active, paused, attention-needed, and disabled states with distinct text and symbols.
- The surface reports only content-free state: transport/attention description and a pending-change count. It does not show note titles, task text, record names, or diagnostic logs.
- The menu and window provide Pause, Resume, Sync Now, Sync Status, and eligible adoption actions. Actions are disabled during a transition.
- The status item publishes an accessibility label/help/value; the compact view uses semantic labels, ordinary keyboard-accessible controls, explicit state text, and localized strings in English, Spanish, French, and Simplified Chinese.
- Attention takes precedence over a paused indicator for account change, unavailable/restricted account, required adoption, missing/reset zone, incompatible remote data, and other durable attention states.
- The iPhone status menu also exposes persisted pause/resume for the same account-scoped transport contract.

### Explicit adoption and recovery containment

- An unadopted local-only Mac workspace remains the active workspace. This is true even if the resolved account workspace already contains data; startup cannot silently change workspace mode or hide the local workspace.
- Adoption is offered only when the local workspace has content and the account workspace is empty. The UI requires an explicit confirmation explaining the target, source retention, and absence of zone/remote deletion.
- Confirmed adoption copies the existing notes/tasks through the established deterministic adoption operation, retains the local source, records a content fingerprint, and waits for relaunch before account-mode activation. It does not merge into a non-empty target or change the live workspace during the copy.
- If both workspaces contain data, the app preserves the local workspace and explains that neither side will be merged or overwritten automatically. No merge action is exposed because no approved merge policy exists.
- Missing/reset-zone and incompatible-data states provide preservation guidance only. They expose no automatic reset, recreate, reseed, delete, or overwrite operation.
- The former Debug environment hatches for automatic local adoption and account-workspace reset were removed.

### Release reproducibility

- Shared `Tildone` and `Tildone iOS` schemes are present under `Tildone.xcodeproj/xcshareddata/xcschemes`, and `.gitignore` now permits both files to be versioned. They remain untracked in this working tree only because Stage 12C was explicitly requested without a commit.
- Both schemes use Debug for Test/Launch/Analyze and Release for Profile/Archive, with no forced launch language.
- `Scripts/verify-release-configuration.sh` asserts those scheme settings and the effective unsigned Release build settings for bundle IDs, entitlements paths, platform minimums, and absence of the `DEBUG` compilation condition.
- No project build setting, Production entitlement, CloudKit container/schema record contract, local persistence schema, or migration contract changed.

## Automated evidence

All commands below ran on the Stage 12C working tree on 2026-08-09. Tests used local/in-memory stores unless explicitly noted; live CloudKit mutation tests remained opt-in and skipped.

### Shared package

- `swift test --package-path Packages/TildoneCore ... --disable-sandbox` in Debug: **98 tests, 0 failures**.
- The same suite with `--configuration release`: **98 tests, 0 failures**.
- Focused coverage includes per-account preference isolation, Release/test activation refusal, paused relaunch, unchanged workspace identity and serialized engine state, untouched outbox attempt evidence, tombstone retention, and safe post-resume draining.
- Existing Core Data store-notification diagnostics appeared during persistent-store tests; they did not fail a test.

### Hosted application and UI tests

- macOS hosted `TildoneTests`: **28 tests executed, 0 failures, 2 opt-in tests skipped**. This includes active/paused/attention presentation, confirmation-gated adoption, refusal to switch away from an unadopted local workspace, removal of reset hatches, deterministic scheme assertions, Mac CRUD, and legacy migration coverage.
- iPhone hosted `TildoneiOSTests` on an iPhone 17 simulator (iOS 26.5): **12 tests executed, 0 failures, 1 opt-in Development CloudKit test skipped**. This includes paused CRUD, per-account preference isolation, workspace revalidation, and paused status presentation.
- iPhone UI launch smoke: **1 test, 0 failures** using the in-memory UI-test workspace.
- The macOS UI runner did not start a test: two bounded attempts remained at `waiting for workers to materialize` with `IDEInstallLocalMacWorker`/`IDELaunchServicesLauncher` unfinished and were stopped. Hosted Mac tests passed, but this is not Mac UI-smoke evidence.

### Builds and configuration

- Unsigned generic macOS Debug and Release builds: passed.
- Unsigned generic iPhone Debug and Release builds: passed.
- The final source state was recompiled by the macOS hosted Debug suite, a generic iPhone Debug build, and fresh generic macOS/iPhone Release builds after the last containment changes.
- `Scripts/verify-release-configuration.sh`: passed with `Release scheme and build-setting assertions passed.`
- The unsigned builds establish compilation/configuration only. They do not establish effective signed entitlements, provisioning, APNs, archive export, or store processing.

### Contract and repository containment

- `plutil -lint` passed for the Mac/iPhone Info plists and entitlement plists.
- `xmllint --noout` passed for both shared schemes; `jq empty` passed for both string catalogs.
- Frozen fixture checksums remained exact: V1 `a36abb3b0f597118b28c155db5ab074e8a2af7f0838f7194ea783e9957426ee6`, V2 `e034619f0701283acfbc62f9817ac7f25149eb4061a1a98b7712980e03b6bb25`, and legacy `2ec613cc46f73561136daa025abe31f79186cdae8867abc8e0e0ff0c6811c5e4`.
- The source-generated Development CloudKit manifest matched `docs/development-cloudkit-contract-manifest.md` exactly.
- The explicit local-store assertion still finds all four expected `cloudKitDatabase: .none`/configuration sites.
- A protected-scope diff found no changes in `project.pbxproj`, either entitlement file, either Info plist, the Development CloudKit manifest, or `Packages/TildoneCore/Sources/TildonePersistence`.
- `git diff --check` passed.

## Remaining owner manual checks

These checks are still required before Stage 12C can satisfy the rollout plan's full product/owner exit criteria:

1. Review the compact Mac menu/window in all four supported languages, light/dark appearance, keyboard-only navigation, VoiceOver, and larger accessibility text. Confirm attention remains understandable without opening a log or exposing user content.
2. On separately approved disposable Development accounts, use a signed Debug Mac and physical iPhone to pause, edit/delete offline, terminate/relaunch, inspect that no CloudKit zone/record work occurs while paused, resume, and confirm convergence with an empty outbox. Record exact devices, OS/builds, account/container, and observation method.
3. With backups and an approved disposable empty account workspace, exercise the adoption confirmation, cancellation, successful copy, source retention, and relaunch activation. Also verify that a non-empty account target offers guidance only and continues showing the local workspace.
4. Exercise forced local presentation of zone-reset and incompatible-data attention states. Verify copy, accessibility, and that no reset/reseed/overwrite action exists.
5. Produce and inspect an exact signed candidate only under later authorization. Verify effective entitlements/provisioning and the Release-off transport assertion from the artifact, not merely source settings.
6. Name and approve privacy/App Privacy, support, incident-command, rollback/containment, test-account/device, and distribution owners. Stage 12C code cannot close those organizational gates.

No physical-device, signed Production-candidate, APNs/background-wake, Production CloudKit, TestFlight, or App Store validation was performed in this Stage 12C implementation.

## Unresolved policy decisions

Stage 12C could safely proceed without inventing the following policies, so the corresponding destructive or ambiguous actions were intentionally not implemented:

- **Non-empty workspace conflict:** decide whether local/account workspaces remain separately selectable or receive a reviewed merge flow. Any merge policy must define authority, conflict handling, backup/rollback, confirmation copy, and support ownership.
- **Missing/reset zone recovery:** decide whether a zone may ever be recreated and whether any local replica may reseed it. The decision must name the authoritative source, required backups, multi-device coordination, confirmation and authentication, audit evidence, stop conditions, and incident owner.
- **Release transport enablement:** decide the exact reviewed build control and artifact assertion that may change the current Release-off matrix. Pause state must remain account-scoped and must not become the release feature gate.
- **External release ownership:** App Privacy/privacy policy compatibility, ordinary-versus-encrypted field decision, support/incident thresholds, disposable Production accounts/devices, signing authority, and distribution authority remain open.
- **Production state:** effective Production schema, roles/indexes, signing/provisioning, APNs, and App Store Connect state remain unknown because Production access was not authorized.

## Exact recommended Stage 12D scope

Stage 12D should be **read-only Production inspection only**, matching `docs/stage12-controlled-production-rollout-plan.md`, and should start only after a narrowly scoped written owner authorization and acceptance of the Stage 12C manual/ownership gates.

Authorized work should be limited to:

1. Confirm the Apple team, container identifier, Production environment, operator role, and current deployment state before viewing schema details.
2. Capture/export, without edits, the Production custom-zone schema metadata: record types, fields, indexes, and security roles. Do not capture user content.
3. Compare that capture against the frozen source-generated manifest and the accepted Development evidence for `TDNote` V1/V2, `TDTask` V1, and advisory content-free `TDClient` V1.
4. Record timestamp, operator, tool/Console view, exact revision, and every exact diff. Stop immediately for a wrong/ambiguous environment, unexpected state, insufficient read-only access, manifest drift, or any tool flow that requires a write.
5. Produce a reviewed, content-free deployment packet and stop. Do not deploy schema in the same authorization or session.

Stage 12D must not enable transport, change source or Production entitlements, deploy schema, create/delete a zone or record, reseed data, sign/archive/upload a candidate, start TestFlight, or change App Store state. Any exact additive Production schema deployment belongs to a separately authorized Stage 12E after independent review.
