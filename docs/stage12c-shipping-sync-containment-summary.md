# Stage 12C — Shipping sync containment and recovery UX summary

**Date:** 2026-08-09  
**Repository boundary:** Stage 12B was already committed separately as `857e056` and the working tree was clean before Stage 12C began.  
**Production actions:** none. Production CloudKit, Production entitlements/provisioning, archives, uploads, TestFlight, and App Store state were not inspected or changed.

## Outcome

Stage 12C closes the remaining repository-local containment blockers identified by the Stage 12A architecture review and Stage 12B stabilization summary. It adds durable account-scoped transport pause/resume, compact sync/attention presentation, explicit non-destructive note-location and combine choices, non-destructive reset/incompatibility guidance, and deterministic shared schemes/configuration assertions.

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

- The menu-bar item and a compact fixed-size **iCloud Sync** window expose active, paused, attention-needed, and disabled states. The menu-bar item retains the Tildone icon in every state and overlays a small exclamation badge for attention instead of replacing the product icon.
- The surface reports only content-free state: transport/attention description and a pending-change count. It does not show note titles, task text, record names, or diagnostic logs.
- The menu and window provide Pause, Resume, Sync Now, Sync Status, and eligible adoption actions. Actions are disabled during a transition.
- The status item publishes an accessibility label/help/value; the compact view uses semantic labels, ordinary keyboard-accessible controls, explicit state text, and localized strings in English, Spanish, French, and Simplified Chinese.
- Attention takes precedence over a paused indicator for account change, unavailable/restricted account, required adoption, missing/reset zone, incompatible remote data, and other durable attention states.
- The iPhone status menu also exposes persisted pause/resume for the same account-scoped transport contract.

### Explicit adoption and recovery containment

- An unadopted local-only Mac workspace remains active until the user makes an explicit choice. This is true even if the resolved account workspace already contains data; startup cannot silently change the presented notes or hide the Mac copy.
- If iCloud has no Tildone notes, the app offers a confirmation-gated copy. The account is revalidated and its emptiness is checked again after sync is stopped, so newly discovered iCloud notes cannot silently turn an empty-copy approval into a merge.
- If both locations contain notes, **Review Options…** replaces the same status window's content with three plain-language, confirmation-gated actions: **Combine Notes — Recommended**, **Use iCloud Notes**, and **Use Notes on This Mac**. The compact cards have consistent left alignment, wrapped details, and ordinary corner radii. Confirmation also remains in the same window. **Decide Later** returns to status, leaves the Mac notes selected, and changes nothing.
- Combine copies a stable snapshot of the Mac notes/tasks into the account repository through the existing stable-ID, field-level deterministic sync merge. Distinct notes are retained; matching records use the already-frozen domain merge rules; the complete resulting account content is queued for sync. The Mac repository remains intact and available.
- If the Mac source changes during the copy, the app does not hide it or record the location change. The user sees a non-destructive failure and can retry; the merge operation is safe to repeat.
- Choosing Mac or iCloud only changes which existing repository is presented. It does not run startup cleanup, delete, upload, merge, or overwrite content. The explicit choice is persisted per opaque account UUID and restored on relaunch.
- After the user chooses the Mac copy, every Mac-only note shows a quiet `icloud.slash` button immediately left of its color picker. Its tooltip and accessibility label say **Only on this Mac — not syncing with iPhone or iCloud.** Pressing it opens the existing iCloud Sync window directly to the same non-destructive choices. The indicator is added to already-open notes when the choice changes and removed when the account copy becomes active; transport pause does not show it.
- The same status window shows a dismissible plain-language reminder immediately after the Mac choice: **These notes won’t appear on your iPhone or in iCloud. You can combine them later.** It contains no note content and is not a persistent alert.
- Before an iCloud selection or combine, the app re-resolves the current account and requires the same account UUID. A mismatch stops the transition rather than exposing or mutating the wrong account.
- A successful live change closes the old repository's managed note windows before opening the selected repository's windows, preventing notes from different locations from being shown together accidentally.
- Missing/reset-zone and incompatible-data states provide preservation guidance only. They expose no automatic reset, recreate, reseed, delete, or overwrite operation.
- The former Debug environment hatches for automatic local adoption and account-workspace reset were removed.

### Release reproducibility

- Shared `Tildone` and `Tildone iOS` schemes are included in the Stage 12C candidate under `Tildone.xcodeproj/xcshareddata/xcschemes`, and `.gitignore` permits both files to be versioned.
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

- macOS hosted `TildoneTests` on the final current tree: **32 tests executed, 0 failures, 2 opt-in tests skipped**. This includes retained-source combine/outbox coverage, per-account relaunch choice persistence, active/paused/attention presentation, same-window confirmation-gated actions, the accessible actionable Mac-only note indicator, retention of the Tildone menu-bar icon with a rendered attention badge, removal of reset hatches, deterministic scheme assertions, Mac CRUD, and legacy migration coverage.
- iPhone hosted `TildoneiOSTests` on an iPhone 17 simulator (iOS 26.5): **12 tests executed, 0 failures, 1 opt-in Development CloudKit test skipped**. This includes paused CRUD, per-account preference isolation, workspace revalidation, and paused status presentation.
- iPhone UI launch smoke: **1 test, 0 failures** using the in-memory UI-test workspace.
- The macOS UI runner did not start a test: two bounded attempts remained at `waiting for workers to materialize` with `IDEInstallLocalMacWorker`/`IDELaunchServicesLauncher` unfinished and were stopped. Hosted Mac tests passed, but this is not Mac UI-smoke evidence.

### Builds and configuration

- Unsigned generic macOS Debug and Release builds: passed.
- Unsigned generic iPhone Debug and Release builds: passed.
- The final source state was recompiled by the macOS hosted Debug suite and a fresh unsigned universal macOS Release build. The Stage 12C iPhone source had already passed hosted tests plus generic Debug/Release builds and was not changed by the Mac-only note-resolution follow-up.
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
3. With backups and an approved disposable Development account, exercise cancellation and each confirmed note choice: empty-account copy, combine, use Mac, use iCloud, changing the choice later, relaunch persistence, source retention, and same-ID conflict results. Verify that switching closes the previously shown note windows and never mixes both sets on screen. For the Mac choice, confirm the slashed-cloud button appears beside the color picker on every already-open and newly opened note, remains after relaunch, has the documented tooltip/VoiceOver text, opens the choices in the existing window, and disappears after choosing iCloud or combining.
4. Exercise forced local presentation of zone-reset and incompatible-data attention states. Verify copy, accessibility, and that no reset/reseed/overwrite action exists.
5. Produce and inspect an exact signed candidate only under later authorization. Verify effective entitlements/provisioning and the Release-off transport assertion from the artifact, not merely source settings.
6. Name and approve privacy/App Privacy, support, incident-command, rollback/containment, test-account/device, and distribution owners. Stage 12C code cannot close those organizational gates.

No physical-device, signed Production-candidate, APNs/background-wake, Production CloudKit, TestFlight, or App Store validation was performed in this Stage 12C implementation.

## Unresolved policy decisions

Stage 12C could safely proceed without inventing the following policies, so the corresponding destructive or ambiguous actions were intentionally not implemented:

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
