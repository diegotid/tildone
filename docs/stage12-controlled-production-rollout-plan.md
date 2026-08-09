# Stage 12 — Controlled Production rollout plan

**Plan reconciled:** 2026-08-09, after Stage 12B repository and Development revalidation
**Current authorization:** repository-local work and the completed explicitly approved Development validation scopes only
**Production authorization:** none
**Production actions performed by Stage 12B:** none; Production was not inspected, modified, or deployed

## Executive decision

Do not inspect or deploy the Production CloudKit schema, create Production records/zones, sign a Production candidate, upload a build, or begin TestFlight from the Stage 12B revision.

Stage 12B closes the post-Stage-11 repository data-contract regressions: Release transport defaults off symmetrically, color migration has an explicit authority rule, the real V2 store path is frozen/tested, Mac post-fetch failures are typed and latch attention, and the three-record Development contract is source-generated. It does not close Stage 12C product/containment blockers or provide new signed physical-device evidence by itself.

The remaining rollout is deliberately split so access to Production cannot be mistaken for authority to change it:

1. complete current signed Development revalidation;
2. implement and qualify Stage 12C containment/attention/recovery policy;
3. separately authorize read-only Production inspection;
4. stop, review the exact diff, and separately authorize irreversible schema deployment;
5. qualify an exact signed Production artifact on disposable accounts;
6. separately authorize TestFlight and later release cohorts.

## Frozen repository contract

### Local persistence

- Current shared store: `TildoneSchemaV3`, metadata version 3.
- V1: content, outbox, workspace metadata, quarantine.
- V2: additive legacy migration/cutover evidence.
- V3: additive `StoredNoteColor` sidecar keyed by stable note ID.
- V1 and V2 `StoredNote`/`StoredTask` models remain unchanged; V2→V3 is lightweight, then an explicit repository migration creates sidecars and outbox evidence atomically.
- Every shared persistent and in-memory `ModelConfiguration` explicitly uses `cloudKitDatabase: .none`. `CKSyncEngine` is the only cloud transport.
- The released 1.6.0 legacy store is never opened through the shared schema or mutated in place.

Frozen fixture hashes:

| Fixture | SHA-256 |
| --- | --- |
| Shared V1 | `a36abb3b0f597118b28c155db5ab074e8a2af7f0838f7194ea783e9957426ee6` |
| Shared V2 | `e034619f0701283acfbc62f9817ac7f25149eb4061a1a98b7712980e03b6bb25` |
| Released Mac 1.6.0 | `2ec613cc46f73561136daa025abe31f79186cdae8867abc8e0e0ff0c6811c5e4` |

### Development CloudKit

- Container: `iCloud.studio.cuatro.tildone`.
- Database: private only.
- Zone: `TildoneUserData`, owner `CKCurrentUserDefaultName`.
- Subscription: `tildone-private-zone-v1`.
- Record contracts: `TDNote` V1/V2, `TDTask` V1, `TDClient` V1.
- Canonical source-derived field/type/optionality/name manifest: [Development CloudKit contract manifest](development-cloudkit-contract-manifest.md).
- `TDClient` is content-free advisory device activity, outside the content outbox. CloudKit server modification time supplies last-seen evidence.
- There is no schema-marker or fourth application record type.

The manifest generator and exact-key test use the mapper's encoder/decoder field constants. A source change that adds or removes a mapped field must fail or update that evidence; prose alone is not the schema authority.

### Transport default matrix

| Context | macOS | iOS |
| --- | --- | --- |
| Debug app, not a test process | automatic Development transport | automatic Development transport |
| XCTest/UI-test process | off; isolated test repository | off; injected/isolated repository |
| Release | off | off |

The shared `TransportDefaultPolicy` owns the matrix. Workspace selection remains distinct from coordinator activation: disabling Release transport must not silently fork an already selected account workspace into `local-only`.

This matrix is a default, not the final shipping pause control. Stage 12C still needs a tested transport-paused mode that retains the account workspace, serialized engine state, tombstones, and durable outbox.

### Note-color migration authority

For the one-time V1/V2-to-V3 backfill:

1. an existing explicit `TDNote` V2 color wins over any synthesized backfill;
2. a legacy Mac per-note color, or its legacy global fallback, wins over platform default;
3. iPhone/platform-default yellow wins over only implicit V1 yellow;
4. values within the same authority class retain deterministic Lamport/replica ordering;
5. later ordinary user color edits are explicit V2 values and beat migration markers.

Authority is encoded in reserved, content-free migration replica prefixes while retaining a source-replica suffix for deterministic ties. No CloudKit field or product behavior was added. Each sidecar/schema/outbox update remains one local transaction, and V1 notes remain readable.

## Stage 12B evidence boundary

Repository-local evidence must cover:

- shared Debug/test/Release default matrix and platform test defaults;
- real V2 open through the V3 plan, migration interruption/rollback, retry, idempotence, offline relaunch, and outbox chains;
- both Mac/iPhone upgrade and upload orders;
- late V1 delivery, existing V2 remote winner, and `serverRecordChanged` retry semantics;
- mapper round trips and exact manifest keys for all four versioned contracts;
- Mac migration/reload error propagation plus frozen-status behavior;
- full `TildoneCore`, hosted Mac/iPhone units, safe UI smokes, four Debug/Release builds, plist/entitlement lint, `.none` scan, fixture hashes, manifest regeneration diff, and `git diff --check`.

These checks establish deterministic local behavior and compilation only. They do not prove signed entitlements, APNs, live CloudKit, a physical iPhone, background wake, Production, TestFlight, or App Store processing.

## Mandatory Development revalidation before Production access

Use only a confirmed disposable Development Apple account/container and a signed Debug Mac plus physical iPhone. Obtain explicit approval before any live Development mutation or destructive Development-zone/reset case. Record exact device/OS/build identities and do not reuse Stage 11 as evidence for fields introduced afterward.

Required matrix:

| Case | Required evidence |
| --- | --- |
| V2 account replica upgrade | Existing Mac color retained after Mac/iPhone upgrade in each order; no yellow replacement; pending returns to zero. |
| Existing V2 cloud color | Remote explicit winner remains on both clients through conflict/retry and relaunch. |
| Mixed records | `TDNote` V1 and V2 plus `TDTask` V1 decode/merge; no quarantine of valid records. |
| `TDClient` | One canonical content-free registration per replica; platform values and active-device summary correct; record conflicts converge. |
| Offline/relaunch | Both directions retain edits and color through termination/relaunch; reconnect converges without duplicate/resurrection. |
| Foreground catch-up | Open Mac/iPhone views reload current snapshots; refresh persistence/reload failure produces attention, never healthy idle. |

If the disposable environment, physical device, signing, account identity, or approval is unavailable, record the case as **not run/blocked**. Never infer it from local tests.

Development revalidation must occur before any authenticated Production inspection.

## Stage 12C — Repository/product containment gate

Stage 12C is required before a Production-capable artifact or limited TestFlight cohort.

Implement only:

- transport pause/resume that retains the selected account workspace, local CRUD, outbox, tombstones, system fields, and engine serialization;
- a compact accessible Mac sync-attention/paused surface, not a broad dashboard;
- owner-approved explicit local-only adoption and Production zone-reset recovery entry points;
- deterministic configuration/release controls that make enabled, paused, and disabled intent inspectable in an artifact;
- local qualification for pause/resume, account switch, adoption refusal/approval, zone-reset latch, restart, and outbox recovery;
- privacy/support/incident ownership decisions required for external testers.

Stage 12C must not inspect or deploy Production merely because its source work is complete.

Exit only when:

- pausing cannot change workspace identity or hide/fork data;
- Mac presents all durable attention states needed for safe limited distribution;
- adoption and recovery are explicit, non-destructive, and approved;
- all local suites/builds pass on the exact candidate revision;
- release, privacy, support, and incident owners are named.

## Stage 12D — Read-only Production inspection

This is an external operation and requires narrowly scoped written approval. Approval to read does not authorize deployment.

Read-only scope:

- confirm team, container identity, environment, roles, and current Production deployment state;
- export/capture the Production schema, record types, fields, indexes, and security roles without creating or editing anything;
- compare Production, Development, and the source-generated manifest;
- record timestamps, operator, tool/Console view, and exact diffs without user content.

Immediate stop conditions:

- wrong team/container/environment;
- unexpected existing type, field, index, role, or deployment state;
- insufficient read-only access or ambiguous Console state;
- source/Development manifest drift;
- any tool flow that requires a write to continue.

After capture, stop. Produce a reviewed deployment packet. Do not deploy in the same authorization or session by assumption.

## Stage 12E — Irreversible schema deployment

Production schema deployment is a separate sensitive action. Require a new written authorization naming the exact reviewed additive diff and operator.

Preconditions:

- Development revalidation passed on the frozen revision;
- Stage 12C exited;
- Stage 12D read-only diff is understood and independently reviewed;
- ordinary/encrypted field decision, indexes, roles, privacy disclosures, signing capabilities, rollback/containment, and incident staffing are accepted;
- the deployment packet contains only the approved `TDNote` V1/V2, `TDTask` V1, and `TDClient` V1 contract.

Deployment rules:

- deploy only the exact approved additive schema;
- do not create/delete a zone or record;
- do not clean up, rename, remove, or guess around unexpected Production state;
- capture post-deploy schema read-only and compare to the packet;
- treat deployment as non-reversible; containment is transport/build based, never schema rollback.

Possessing credentials, completing Stage 12D, or approving this plan is not deployment authorization.

## Stage 12F — Signed Production smoke

Only after schema deployment and separate release/signing approval:

- archive/export an exact internal artifact; do not upload yet;
- inspect effective signed entitlements for both nested app products and confirm bundle/team/container/APNs environment;
- install only on controlled devices/accounts through an approved path;
- run fresh install, upgrade, cross-device CRUD/color/order/completion/deletion, offline/relaunch, `TDClient`, account isolation, foreground recovery, conflict, malformed/future handling, and pause/resume;
- use generated non-sensitive data and content-free diagnostics;
- never delete a Production zone unless a separately reviewed disposable-account fault-injection plan explicitly authorizes it.

Any data loss, wrong workspace, hidden attention, unexpected record/schema change, unbounded outbox, or entitlement mismatch is an immediate hold. Preserve stores/evidence and pause transport; do not reset or reseed automatically.

## Stage 12G — TestFlight and release

TestFlight upload, tester assignment, and release are separate external actions requiring explicit approval at each boundary.

Before limited TestFlight:

- exact artifact hash matches the Production-qualified artifact;
- App Store Connect metadata, privacy answers/policy, export compliance, support contact, feedback route, incident owner, and containment build path are ready;
- Apple-processed Mac/iOS installs receive their own smoke pass;
- cohort size, observation window, latency/outbox thresholds, and stop authority are written.

Before App Store release:

- limited cohort completed with no open severity-1/2 correctness, privacy, or data-safety issue;
- background delivery is described as opportunistic; foreground catch-up is the correctness requirement;
- phased release limitations, including manual downloads outside the phase percentage, are accepted;
- a tested transport-paused update can be shipped if containment is required.

## Open blockers after Stage 12B

- Final Mac/iPhone hosted tests and fresh generic Debug and Release builds succeeded on 2026-08-09. The Mac UI launch smoke passed all 8 launch/appearance variants. An earlier isolated iPhone UI launch passed; the final rerun built successfully but produced no new test result because CoreSimulatorService died before launching the runner. These are local build/test results, not live CloudKit evidence.
- The disposable-account phase established a signed Intel Mac launch, simulator initial/fresh bootstrap, exact Development record lookup, simulator upload, and physical-Mac catch-up. That simulator reproducibly failed to consume later Mac updates incrementally from saved engine state, including a server-verified blue record; resetting local state is not a shipping recovery policy.
- A later owner-approved, non-destructive main-account run used a physical iPhone 14 Pro on iOS 27.0. CoreDevice confirmed the developer bundle, and a separately verified Development-signed Mac Debug build opened the existing schema-V3 account workspace with an empty outbox.
- The physical workflow passed existing-workspace initial fetch, incremental Mac-to-iPhone and iPhone-to-Mac title/color convergence without reset, canonical content-free TDClient V1 receipt for both current replicas, offline iPhone edit persistence across force-quit/relaunch, reconnect convergence, and final empty Mac outbox.
- The physical success narrows the disposable simulator failure to simulator/saved-environment evidence rather than a demonstrated physical-device product defect. APNs background wake was not isolated from foreground catch-up.
- Synthetic mixed V1/V2 delivery/upgrade orders, TDClient conflict injection, account switching, deletion, and reset/recovery remain local-only evidence because the approved live scope deliberately excluded them.
- Shipping transport pause/resume is not implemented.
- Mac lacks the Stage 12C compact attention/paused UI.
- Shipping local-only adoption and Production zone-reset recovery policy/UX remain unapproved.
- Effective Production schema, signing, provisioning, APNs, and App Store Connect state are unknown because Production is intentionally untouched.
- Privacy policy/App Privacy, encrypted-field decision, support, incident command, thresholds, accounts/devices, and distribution authority remain open.
- Stage 11 background wake remained inconclusive; reliable foreground catch-up remains mandatory.

## Authorization ledger

| Action | Current state |
| --- | --- |
| Repository-local Stage 12B edits/tests/builds | Authorized by Stage 12B request |
| Signed Development validation | Completed for the explicitly approved disposable and restricted non-destructive main-account scopes; synthetic/destructive expansion requires new approval |
| Read-only Production inspection | Unauthorized; separate Stage 12D approval required |
| Production schema deployment | Unauthorized; separate post-diff Stage 12E approval required |
| Production records/zones/fault injection | Unauthorized |
| Production entitlements/provisioning/signing changes | Unauthorized |
| Archive/export/upload/TestFlight/App Store release | Unauthorized |

No later operator may infer permission from repository access, credentials, Development approval, prior historical validation, or this plan.
