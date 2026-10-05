# Isolated Development fixture preparation — 2026-10-06

This is a prepared test procedure, not evidence of a completed live historical
upgrade or account switch. Current-account approval allows ordinary synthetic
edits. It supplies neither an account B nor an isolated historical installation.
Do not downgrade either personal-content installation or copy fixture content
over its store. Do not adopt, reset, reseed, or recreate a zone under this plan.

## Identified historical artifacts

All three existing on-disk artifacts were rehashed on 2026-10-06. Tests copy them
to explicitly named temporary destinations and leave their source unchanged.
The [fixture provenance](../Packages/TildoneCore/Tests/TildonePersistenceTests/Fixtures/README.md)
identifies their generation method, toolchain, and synthetic content.

| Artifact | SHA-256 | Intended use |
| --- | --- | --- |
| `TildoneLegacy160/default.store` | `2ec613cc46f73561136daa025abe31f79186cdae8867abc8e0e0ff0c6811c5e4` | Released legacy model import, never opened through the shared schema |
| `TildoneSharedStoreV1/TildoneSharedStore-v1/local-only/tildone-shared.sqlite` | `a36abb3b0f597118b28c155db5ab074e8a2af7f0838f7194ea783e9957426ee6` | Frozen shared V1 migration/reopen evidence |
| `TildoneSharedStoreV2/TildoneSharedStore-v1/accounts/abcdef00-0000-0000-0000-000000000010/tildone-shared.sqlite` | `e034619f0701283acfbc62f9817ac7f25149eb4061a1a98b7712980e03b6bb25` | Actual V2 workspace with migration evidence, attempted/superseded work, tombstone and no color sidecar |

Paths in this table are relative to
`Packages/TildoneCore/Tests/TildonePersistenceTests/Fixtures/`.
Released tag `1.6.0` resolves to `02be4e06f67b52edd8f962a7ef81f4dc561f52c1`;
Stage 12B resolves to `857e0561d0b2397f71fb43171d67ca1ff75d08ed`.
Neither is a newly verified signed historical iPhone/Mac artifact. In particular,
the released legacy store and a V2 shared store are different fixtures. The
August Stage 12B transferred Intel ZIP hash is historical evidence only; its
availability, effective entitlements and exact executable source have not been
requalified today.

## Prepared synthetic record cases and local checks

The exact existing executable fixtures live in
`Packages/TildoneCore/Tests/TildoneSyncTests/TildoneSyncTests.swift`:

- `testMacColorBackfillConvergesOverPhoneDefaultInBothUpgradeOrders`: fixed
  synthetic IDs, V1 note, Mac legacy orange versus phone default yellow,
  Mac-first and phone-first migration/upload, final color authority and zero queue.
- `testExistingV2RemoteColorBeatsBackfillDuringServerConflictRetry`: explicit
  V2 purple with a lower ordinary counter beats the synthesized Mac green;
  the queued retry contains the winning color and version.
- `testCloudMapperReadsV1NotesWithoutColorAndUsesDeterministicFallback`,
  `testCloudMapperReadsV1ThroughV3NotesWithoutFontAsOverlock`,
  `testCloudMapperReadsV1TasksWithoutIndentationAndUsesOrderVersion`, and
  `testCloudMapperReadsV2TaskAsPlainRichText`: deliberately versioned records
  rather than a current UI note labelled "old".
- Late V1 note/task delivery tests verify acceptance, upgrade and new durable work.
- `DevelopmentQualificationTests` adds current-field bidirectional pipeline
  fixtures, paused insertion, reordered duplicate delivery, deletion with late
  stale delivery, old-save/new-edit acknowledgment and canonical client retry.

These passed in the current Debug and Release package runs. The source-generated
contract still describes `TDNote` V1–V4, `TDTask` V1–V3 and `TDClient` V1.
Local record objects and on-disk migration fixtures do not prove live CloudKit
upgrade order or registration-conflict handling.

## Required isolated live procedure

1. Identify account A, account B, a disposable Mac user/session and a physical
   test iPhone workspace. Record only opaque account labels in published evidence.
   Obtain an explicit scope for any fixture adoption or recovery action. Leave
   the existing affected item and personal installations intact.
2. Produce identified signed historical artifacts using their original contracts
   and an explicit fixture-store path. Reverify entitlements, Debug transport,
   private database/zone, store URL and signatures. A historical source commit
   alone is insufficient. Do not change signing settings to obtain a build.
3. Seed only approved synthetic fixtures through an isolated CKSyncEngine client,
   using canonical stable IDs and the existing types/fields. No Console record
   query, schema edit or zone reset is part of this procedure.
4. On two independently prepared partitions, upgrade Mac then iPhone, and iPhone
   then Mac. Retain untouched source fixtures and compare IDs, field values,
   tombstones, queue evidence, colors and authority stamps after relaunch.
5. Deliver identified old/current record versions in interleaved and duplicate
   batches. An accepted older schema must not enter quarantine. Inject an
   explicitly approved synthetic registration save conflict; require a canonical
   retry, one own-replica key and correct platform/recent-device summary.
6. For account isolation, place different labelled fixtures in A and B. Switch
   only the disposable installation, require immediate old-workspace removal,
   verify B never displays/uploads A, and recheck after relaunch and return to A.
   One account cannot establish this case. Do not use sign-out, adoption or reset
   of the personal-content installations to simulate it.

Each live case needs its own recorded starting state, artifact hashes, observation
times, rendered result, content-free transport evidence, final queue and explicit
passed/failed/not-run result. Do not reset a failed partition to manufacture a pass.
