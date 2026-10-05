# Stage 12D — Read-only Production CloudKit inspection

**Status:** Verified with conditions: the current source and Development field contract agree, and Production has no visible Tildone application schema or deployment history. This does not establish that a deployment never occurred. Stage 12E remains on hold pending the qualification evidence and decisions below; it needs separate authorization.

**Source revision:** `bb8240d17c36dbf9afdc84fb8af1d55572a7d77a`.

**Original inspection window:** 2026-10-04 17:04–17:10 Europe/Madrid (15:04–15:10 UTC), as recorded by the original inspection.

**Independent review window:** 2026-10-04 18:36–18:43 Europe/Madrid (16:36–16:43 UTC), against a fresh live Console view. Source and the regenerated contract were reviewed first; this document was read last. The original review was not used as evidence.

**Authenticated operator:** Diego Rivera, Apple team `F6HFAVTS49`, confirmed by Console's account menu and container URL. Container Permissions showed Manage Permissions, Edit Development, and Edit Production enabled. No permissions were changed. These are container capabilities; the formal Apple team-role label was not shown and remains unverified.

**Scope:** Schema metadata only. No record query, user content, Production write, export, deployment, signing change, or build upload was performed.

## What this means

No CloudKit field repair is indicated by this inspection. The app's expected fields are present in Development, and the three app record types are absent from Production. Publishing the database structure is the later Stage 12E action; it does not upload or release a build, and it does not enable the app's currently disabled Release sync.

The local automated tests and unsigned builds now pass after the separately approved repairs below. The remaining work is signed real-device testing and product acceptance, choosing the field protection/index/permission settings, and approving the exact publication. The owner action list at the end separates those tasks from the completed inspection.

## Source baseline

The authoritative field contract is [`development-cloudkit-contract-manifest.md`](development-cloudkit-contract-manifest.md), generated from the current mapper constants. On this source revision, `swift run --disable-sandbox --package-path Packages/TildoneCore TildoneCloudContractManifestGenerator` produced byte-for-byte identical output. SHA-256 of the tracked manifest: `071be605a06740eaad0a94290db8b4c1338bac523c04662fb3b1df06e3a514bf`.

| Type | Latest readable/writable schema version | Application fields |
| --- | --- | ---: |
| `TDNote` | V4 | 20 |
| `TDTask` | V3 | 20 |
| `TDClient` | V1 | 3 |

The older Stage 12 plan's `TDNote` V1/V2 and `TDTask` V1 list is historical. The app uses `CKContainer(identifier: "iCloud.studio.cuatro.tildone").privateCloudDatabase`, zone `TildoneUserData`, and subscription `tildone-private-zone-v1`. The Console's schema is container-wide; its default public-database Records view was not queried.

## Console evidence

The visible Console URL identified team path `F6HFAVTS49`, container `iCloud.studio.cuatro.tildone`, and the selected environment on each page. No search/filter text was entered. This was a Console view capture, not a schema-file export. The selected Development and Production Record Types, Indexes, Security Roles, and Schema History pages were inspected read-only.

| Metadata | Development | Production |
| --- | --- | --- |
| Record types | `TDClient` (9 Console fields), `TDNote` (26), `TDTask` (26), `Users` (7) | `Users` (7) only; no Tildone application types |
| Application fields | 3, 20, 20 respectively; plus six CloudKit metadata fields per type | None |
| Single-field indexes | `TDClient` 8; `TDNote` 51; `TDTask` 49; total 108 | No indexes |
| Security roles | Default `_world`, `_icloud`, `_creator` with Tildone assignments below | Same three default roles; `_world` and `_creator` list `Users`, `_icloud` lists no type |
| Schema history | Tildone type, field, index, and role changes dated July–September 2026; latest visible entry 2026-09-13 | “No schema history available” |
| Console deploy control | Enabled in Development; **not clicked** | Disabled |

`Users` appears in both environments. Apple documents user records as a [CloudKit system record type](https://developer.apple.com/documentation/cloudkit/ckrecord/recordtype-6v7au), and a local, network-free check of the installed framework's `CKRecord.SystemType.userRecord` returned `Users`. The independent review opened its field definition in both environments, without opening user records. Both contained exactly the following metadata, with no custom fields and no indexes:

| Metadata field | Console type |
| --- | --- |
| `createdTimestamp` | Date/Time |
| `createdUserRecordName` | Reference |
| `___etag` | String |
| `modifiedTimestamp` | Date/Time |
| `modifiedUserRecordName` | Reference |
| `recordName` | Reference |
| `roles` | Int(64) List |

Production has no visible Tildone application schema or index to preserve, and no visible schema deployment history. That conclusion is limited to the Console metadata views; it is not a claim about record contents or the complete historical deployment record.

### Development field comparison

The 43 Development application field names and Console types matched the latest source manifest, with one representation note: `TDTask.isCompleted` is a Swift `Bool` in the mapper and appears as `INT(64)` in Console. Apple [documents Boolean record values as stored in Int(64)](https://developer.apple.com/documentation/cloudkit/designing-and-creating-a-cloudkit-database); the decoder explicitly accepts only canonical `0` and `1` when CloudKit returns that representation. No application field was missing or extra. Console metadata rows include `createdTimestamp`, `createdUserRecordName`, `___etag`, `modifiedTimestamp`, `modifiedUserRecordName`, and `recordName` for each type; these are not mapper fields.

The Console field table does not expose the manifest's decoder optionality. The source marks `TDNote.title` and `TDTask.completedAt` optional, while all other current fields are required by the decoder. That part of the source/Development comparison remains source-derived rather than independently observable in this Console view.

The following transcribed field inventory records the independent comparison of every current application field. Each listed field was present in Development and absent in Production. The source's `Boolean` label is normalized to Console's `Int(64)` for `isCompleted`; it is not a separate CloudKit field type to deploy.

| Record type | Console type | Exact application fields |
| --- | --- | --- |
| `TDNote` | String | `color`, `colorVersionReplicaID`, `kind`, `kindVersionReplicaID`, `lastMeaningfulEditVersionReplicaID`, `lifecycle`, `lifecycleVersionReplicaID`, `singleMemoFont`, `singleMemoFontVersionReplicaID`, `title`, `titleVersionReplicaID` |
| `TDNote` | Int(64) | `colorVersionCounter`, `kindVersionCounter`, `lastMeaningfulEditVersionCounter`, `lifecycleVersionCounter`, `schemaVersion`, `singleMemoFontVersionCounter`, `titleVersionCounter` |
| `TDNote` | Date/Time | `createdAt`, `lastMeaningfulEditAt` |
| `TDTask` | String | `completionVersionReplicaID`, `indentVersionReplicaID`, `lifecycle`, `lifecycleVersionReplicaID`, `noteID`, `orderToken`, `orderVersionReplicaID`, `text`, `textVersionReplicaID` |
| `TDTask` | Int(64) | `completionVersionCounter`, `indentLevel`, `indentVersionCounter`, `isCompleted`, `lifecycleVersionCounter`, `orderVersionCounter`, `schemaVersion`, `textVersionCounter` |
| `TDTask` | Date/Time | `completedAt`, `createdAt` |
| `TDTask` | Bytes | `richTextJSON` |
| `TDClient` | String | `platform`, `replicaID` |
| `TDClient` | Int(64) | `schemaVersion` |

### Development indexes

The visible index list exactly covered each application field. Every `String` field had Queryable, Searchable, and Sortable indexes. Every `Int(64)`, Date/Time, and Bytes field had Queryable and Sortable indexes. This yields 8 indexes on `TDClient`, 51 on `TDNote`, and 49 on `TDTask` (108 total). `TDTask.richTextJSON` is Bytes and has Queryable and Sortable indexes. No Production index was listed. The source field manifest does not prescribe indexes, so whether all 108 should be promoted is a Stage 12E review decision, especially for content fields.

### Development security roles

For each of `TDClient`, `TDNote`, and `TDTask`, the Development Console showed:

| Role | Create | Read | Write |
| --- | ---: | ---: | ---: |
| `_world` | off | on | off |
| `_icloud` | on | off | off |
| `_creator` | off | off | on |

Production has no Tildone assignment on any role. The independent review opened all three roles in both environments. For `Users`, both environments grant `_world` Read only and `_creator` Write only; `_icloud` has no `Users` assignment. Production `_icloud` has no record types assigned at all. No additional security roles were listed.

Apple states [security roles govern public-database permissions](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitQuickStart/Glossary/Glossary.html). The Tildone coordinator uses the private database, so the public grants do not grant another user access to its private custom zone. They still need explicit review: any records stored under these types in the public database would be world-readable with these grants. No public record contents were inspected.

### Schema history comparison

The Development history listed the following additive changes by `DR Diego`. Later field additions were expanded to verify their names and types. The type and index totals agree with the current field and index views.

| Console date | Development change | Added indexes |
| --- | --- | ---: |
| 2026-07-18 | Created `TDNote` and `TDTask`; changed their default-role assignments | 27 + 40 |
| 2026-08-03 | Created `TDClient`; changed its default-role assignments | 8 |
| 2026-08-04 | Added note color fields | 8 |
| 2026-08-28 | Added task indentation fields | 7 |
| 2026-09-07 | Added `richTextJSON` as Bytes | 2 |
| 2026-09-11 | Added note kind fields | 8 |
| 2026-09-13 | Added single-memo font fields | 8 |

Production's loaded history view said “No schema history available.” Neither that message nor the disabled Production deployment control is evidence that no deployment ever occurred. The current Production type/field/index/role views are the baseline for the proposed additive diff.

This document retains a transcription of the metadata inspected in the independent review. It is not a raw screenshot archive or a schema export. Before an eventual deployment approval, refresh and retain a dated Console capture or export of the final chosen schema, with its source revision and manifest hash. If the chosen schema differs from this inventory, review that new diff before authorization.

## Proposed additive Production diff for review

This is the observed Development-to-Production diff, **not** permission to deploy:

1. Add custom types `TDNote`, `TDTask`, and `TDClient` with exactly the 20, 20, and 3 application fields and CloudKit types in the current source manifest. Preserve system `Users` unchanged. `TDTask.isCompleted` is represented by CloudKit as `INT(64)`.
2. If the Development schema is promoted unmodified, add its 108 single-field indexes: `TDClient` 8, `TDNote` 51, `TDTask` 49, with the per-type and per-field rules recorded above.
3. If the Development schema is promoted unmodified, assign the three Tildone types to the three default public-database roles with the permissions in the table above. Preserve the existing `Users` assignments.
4. Do not add a zone or record as part of schema deployment. The private custom zone and subscription are runtime contracts, not application record types in this schema diff.

**What the owner needs to do:** Do not recreate Development's types or fields manually in Production. Before distributing a Production-sync-enabled artifact, the reviewed schema needs to be promoted as Stage 12E under separate authorization. The independent source/Console comparison has now been completed; it does not establish live sync correctness or satisfy the other rollout gates. It is a project release safeguard, not an Apple-mandated outside audit.

**Review holds before Stage 12E:** The owner must approve the exact field, index, and role diff, including whether all 108 indexes and public-database grants are intentional. Console optionality is not a separately verified server requirement: the required/optional behavior above is the app decoder's versioned contract. The ordinary-versus-encrypted field decision remains open. Current source uses ordinary fields; [Apple documents](https://developer.apple.com/documentation/cloudkit/encrypting-user-data) that encrypted fields cannot have indexes and existing ordinary fields cannot be converted in place. Choosing encrypted fields therefore requires a separately scoped source/Development schema change, requalification, and a fresh reviewed diff before Stage 12E.

The [rollout plan](stage12-controlled-production-rollout-plan.md#stage-12e--irreversible-schema-deployment) also requires signed Development revalidation on the frozen candidate revision and full Stage 12C exit. The August baseline does not establish live correctness for note kind, task indentation/rich text, or single-memo font added afterward. This inspection supplies no new physical-device sync, signed Production-artifact, privacy, recovery-policy, or incident-ownership acceptance. A new, explicit Stage 12E authorization must name the final reviewed diff and operator. Neither read-only inspection approval nor approval to edit this document authorizes deployment.

## Initial local qualification — 2026-10-04

At the owner's subsequent request, local tests and unsigned builds were run against the same source revision. Only this inspection document was edited. These checks did not query CloudKit records, change either environment, change signing settings, upload a build, or perform Stage 12E.

Toolchain: Xcode 27.0 (`27A266a`), macOS 27.0.1 (`26A434`), Apple Silicon. The iPhone hosted tests used the iPhone 18 Pro simulator, iOS 27.0 (`24A434`), device ID `E28173F6-B86C-42E3-96C1-4BB961DFFD2F`. Temporary build/test output is under `/tmp/tildone-12d-*`; retain it elsewhere if durable diagnostics are needed.

| Check | New result | Local evidence |
| --- | --- | --- |
| Full shared package, Debug | 150 tests passed; zero failures (45 domain, 59 persistence, 46 sync) | `/tmp/tildone-12d-local-debug.log` |
| Full shared package, Release | Same 150 tests passed; zero failures | `/tmp/tildone-12d-local-release.log` |
| macOS and iOS generic builds, Debug and Release | All four unsigned builds succeeded | `/tmp/tildone-12d-{mac,ios}-{debug,release}-build.log` |
| Release scheme/settings assertions | Passed | `/tmp/tildone-12d-release-settings.log`; `scripts/verify-release-configuration.sh` |
| Hosted Mac units | **Failed:** 208 passed, 13 failed; 221 selected tests | `/tmp/tildone-12d-mac-unit.xcresult`, `/tmp/tildone-12d-mac-unit-summary.json`, `/tmp/tildone-12d-mac-unit.log` |
| Hosted iPhone units, first run | **Incomplete:** 47 passed, then the memo-editor case stalled with repeated observation-feedback-loop messages; the run was cancelled | `/tmp/tildone-12d-ios-unit.xcresult`, `/tmp/tildone-12d-ios-unit-summary.json`, `/tmp/tildone-12d-ios-unit.log` |
| Remaining hosted iPhone units | Log reports 53 selected tests passed with the stalled case excluded; Xcode then stalled during completion and required termination. **Not a clean overall pass** | `/tmp/tildone-12d-ios-unit-remainder.log`; result bundle was not finalized |
| Contract regeneration and document inventory | Manifest remained byte-for-byte identical; all 43 transcribed fields/types matched it | `/tmp/tildone-12d-independent-manifest.md`; SHA-256 above |
| Frozen fixture hashes | Released, V1 and V2 hashes exactly match the rollout-plan baseline | Explicit fixture files under `Packages/TildoneCore/Tests/TildonePersistenceTests/Fixtures` |
| Plist/entitlement lint and persistence configuration | Both platform plists/entitlements passed lint; shared repository configurations explicitly use `.none` | Tracked platform files and `TildoneRepository.swift` |

The first sandboxed Release/settings attempts failed due to denied Xcode cache/tool access. They were rerun successfully with local build-tool access. No application code or project settings were changed to obtain those successes. The iOS builds also report actor-isolation warnings in `TildoneiOSUndoOverlay.swift` and an unused coordinator-start result; a successful compile does not resolve these warnings.

Package commands used `swift test --disable-sandbox --package-path Packages/TildoneCore` with separate temporary scratch/cache paths, adding `--configuration release` for Release. App builds used `xcodebuild -project Tildone.xcodeproj`, schemes `Tildone` and `Tildone iOS`, configurations Debug/Release, destinations `generic/platform=macOS` and `generic/platform=iOS`, temporary derived data and `CODE_SIGNING_ALLOWED=NO`.

Hosted Mac tests used `platform=macOS`, Debug, `-only-testing:TildoneTests`, and explicitly excluded `testDevelopmentCloudKitRoundTripWhenExplicitlyEnabled` and `testDeveloperToolRequiresExplicitPathsAndNeverDefaultsToProduction`. Hosted iPhone tests used `platform=iOS Simulator,id=E28173F6-B86C-42E3-96C1-4BB961DFFD2F`, Debug, `-only-testing:TildoneiOSTests`, and explicitly excluded `testDevelopmentCloudKitNoteLookupWhenExplicitlyEnabled`. The second iPhone run also excluded `testSingleMemoHostedEditorKeepsTypedTextAndCaretInsideViewport` and enabled test timeouts (60-second default, 120-second maximum). Tests used in-memory or explicit fixture stores; the released user's store was not opened.

### Failures that must be investigated before accepting the local gate

The Mac result bundle reports these 13 failed tests. Their root causes have not been established; do not assume they are harmless outdated assertions or infer CloudKit defects from them.

| Test (class prefix omitted unless different) | Recorded failure |
| --- | --- |
| `testActualGreenNoteTextContrastInDarkMode` | Expected color component approximately 0.8039, received 0 |
| `testBackgroundTransparencyDefaultMarkerDetectsCrossingInBothDirections` | Boolean assertion failed |
| `testBottomRightGatherPreviewMovesScrollChevronsToTheLeftEdge` | Expected preview offset 4, received 0 |
| `testDraggingRootIntoAnotherRootsChildrenSnapsToRootBoundary` | Expected a task ID, received nil |
| `testHelpMenuSearchMatchesTopicNamesAndAliases` | Expected Gather Notes match, received empty results |
| `testHelpMenuSearchRespectsResultLimits` | Expected Gather Notes match, received empty results |
| `WhatsNewReleaseTests.testMacHighlightsCoverEveryProFeatureAfterFreeImprovements` | Expected companion step, received welcome |
| `testMacTaskRowsExposeDedicatedDragHandlesAndDropTargets` | Boolean assertion failed |
| `testMinimizedRestoreControlUsesTheFullTitlebarHeight` | Restore-control x-coordinate 227.5 versus expected 229 |
| `LegacyMigrationTests.testMissingCollisionDifferentCopyChangedSourceAndInvalidRelationshipFailTyped` | Expected `differentSource` failure was not observed |
| `LegacyMigrationTests.testReaderPreservesNilDuplicateNoncontiguousOrderAndClassifiesEmptyAndSystemRows` | Unexpected `sourceChanged` error |
| `testSixScrollChevronsWrapOnlyWhileTransparentAtTheEdges` | Expected preview offset 4, received 0 |
| `testUndoPrefersAFocusedTextEditorOnlyWhenItHasTypingHistory` | Test host crashed |

The unresolved iPhone case is `TildoneiOSTests.testSingleMemoHostedEditorKeepsTypedTextAndCaretInsideViewport`. The result bundle labels its failure “Testing was canceled”; the test had stalled, so this is an incomplete case, not a completed assertion failure.

The second iPhone run reported all 53 selected cases passing at 23:14:44 Europe/Madrid, then failed to exit or finalize its result bundle. Cancellation printed in-flight Xcode operation diagnostics; termination was needed. Its log is useful case-level evidence, but the simulator runner's completion problem must also be resolved before calling the hosted suite fully passed.

**This initial local run did not fully pass.** Its failed-test status is superseded by the repair qualification below. UI smoke suites, manual accessibility checks, signed Development/physical-device tests and all Production behavior remain unqualified by these local runs. August's local pass does not establish current-revision readiness.

## Authorized local repairs and final qualification — 2026-10-04

The owner subsequently authorized investigating and fixing the local failures. Qualification used base revision `bb8240d17c36dbf9afdc84fb8af1d55572a7d77a` plus the application/localization/test patch in `/tmp/tildone-local-qualification-fixes.patch`, SHA-256 `9bd48e08247fe4091f910af6445318f8ef7291c79509bdf144294505f3e759ca`. Those repairs are now committed as `29b756eb1fc37eea885f10117e02e3c52643efdb`; committing did not alter the tested application or test source. The later signed Development run must identify its exact frozen candidate revision. Documentation changes are outside that source patch hash. No CloudKit environment, mapper contract, signing setting or build upload was changed.

The failures were resolved as follows:

| Cause | Repair and evidence |
| --- | --- |
| Missing Help search aliases | Restored the original English, Spanish, French and Simplified Chinese aliases. Marked the dynamically looked-up catalog entries manually maintained so extraction does not discard them. Both search regression tests now pass. |
| Settings preview edge and slider boundary | Restored the intended four-point right margin. Marker crossing now tolerates the one-step floating-point difference between decimal `0.3` and `1 - 0.7`; existing boundary tests pass. |
| Older or incorrect test expectations | Updated the restore-control geometry for its current 3.5-point margin, checked the actual child index after moving a root, recognized the current padding property and welcome-first release tour. No hierarchy, restore-control or release-tour product behavior was changed. |
| Contrast test inspected an invisible focus helper | The inactive row's transparent native helper was being measured as visible text. The test now activates the row and checks its actual editor. Dark-mode colors pass at all three tested opacities. The app's appearance behavior was preserved. |
| Undo test used an expired target | Retained the synthetic target through undo and ran the AppKit test on the main actor. The crash trace pointed to undo invocation; Apple [documents that the undo manager holds an unowned target reference](https://developer.apple.com/documentation/foundation/undomanager/registerundo%28withtarget%3Ahandler%3A%29). App undo behavior was unchanged. |
| Generated migration fixture changed after saving | SwiftData wrote to a separate temporary writer URL; the test helper now freezes a synthetic source with the [SQLite backup API](https://www.sqlite.org/backup.html). The migration source is not opened by that writer. Both migration regressions pass, including explicit interruption setup checks. Production migration/fingerprint checks were preserved. |
| iPhone focus interference between tests | An isolated memo-editor run passed before any iPhone changes. Temporary test windows now end editing, detach their controllers and restore the previous key window. The app's shake-undo responder cannot reclaim focus from a hidden/non-key window, and its main-queue notification handlers explicitly respect main-actor isolation. The full suite, including the memo editor and hidden-responder check, now passes and exits cleanly. |

Final results on this repaired checkout, using the same toolchain and simulator identities above:

| Check | Final result | Local evidence |
| --- | --- | --- |
| Full shared package, Debug and Release | 150 passed in each configuration; zero failures | `/tmp/tildone-fix-package-debug.log`, `/tmp/tildone-fix-package-release.log` |
| Complete hosted Mac unit target | 221 passed; zero failures; clean command exit | `/tmp/tildone-fix-mac-final.xcresult`, `/tmp/tildone-fix-mac-final-summary.json`, `/tmp/tildone-fix-mac-final.log` |
| Complete offline hosted iPhone unit target | 54 passed; zero failures; clean command exit | `/tmp/tildone-fix-ios-full.xcresult`, `/tmp/tildone-fix-ios-full-summary.json`, `/tmp/tildone-fix-ios-full.log` |
| Four generic unsigned app builds | macOS Debug/Release and iOS Debug/Release all succeeded | `/tmp/tildone-fix-{mac,ios}-{debug,release}-build.log` |
| Release settings | Assertions passed | `/tmp/tildone-fix-release-settings.log` |
| Contract, fixtures, plist/entitlements, localization and whitespace | Manifest unchanged; frozen hashes unchanged; lint, four-language search entries and diff checks passed | `/tmp/tildone-fix-contract-manifest.md`; tracked files and hashes above |

Hosted tests retain the same explicit live-operation exclusions above. The full iPhone run included the previously stalled memo case and used 45-second default/60-second maximum test allowances; no memo case was excluded. Final Mac builds used `/tmp/tildone-fix-mac-generic` derived data and included arm64 and x86_64. The iPhone app builds used the physical-device arm64 target and were not installed or signed. Existing unused-result warnings in unrelated tests remain; the repaired iPhone notification handlers no longer emit their earlier actor-isolation warnings.

**The reported local test failures and runner stalls are closed by these results.** They do not supply signed entitlements, live Development sync, physical-device/background delivery, manual accessibility/UI acceptance, owner policy decisions or Production qualification. Stage 12E remains blocked by the remaining rollout gates, not by the 13 initial Mac failures or the simulator stall.

## Remaining owner actions and assistance

The original packet needed documentation corrections, rather than a CloudKit repair: its absolute deployment-history claim exceeded the visible evidence; it had not inspected the `Users` fields; it omitted the exact application field inventory, Production `Users` role grants and operator capabilities; and it did not distinguish the current schema comparison from the missing current-revision live qualification. Those points are corrected above. No application field/type mismatch was found.

The rollout plan places signed Development revalidation before authenticated Production inspection. This inspection has already occurred under the owner's explicit read-only instruction, without fresh evidence for the frozen current candidate. Record that sequencing deviation; completion of the inspection does not retroactively satisfy that prerequisite or waive it before Stage 12E.

| Work | Assistant can do | Owner needs to supply or approve |
| --- | --- | --- |
| Current local qualification | Run package tests, unsigned app builds, configuration/fixture/contract checks; record failures and limits | No further input for those local checks |
| Signed Development and physical-device qualification | Prepare a checklist; guide and assess the approved run | Disposable account, Mac/physical iPhone identities, exact builds, and separate approval for live Development operations |
| Field protection | Explain ordinary versus optional encrypted-field tradeoffs and prepare a proposed contract | Explicit protection decision for title, text, and rich-text content |
| Indexes and public permissions | Propose a minimal configuration based on the private-zone transport; prepare its exact diff | Approve the chosen index list and public-role grants; any environment edits require a separate scope |
| Stage 12C acceptance | Collect local evidence and manual checks for pause/resume, note adoption, account isolation, attention, and preservation on reset | Accept the tested behavior, UI/accessibility checks, and the recovery policy |
| Ownership and release readiness | Draft the support/containment checklist | Name privacy, support, incident and release owners; approve disclosures, signing capabilities and containment policy |
| Final Stage 12E decision | Refresh the read-only baseline and prepare the final publication list | Separate written authorization naming the exact reviewed diff and operator |

Do not infer a Production build, signing change, schema publication, upload, or release from completion of any local check.

### Checklist for a separately approved real-device run

The subsequently authorized 2026-10-05 signed Mac/physical-iPhone run is recorded in [Development real-device revalidation](development-real-device-revalidation-2026-10-05.md). It confirms selected current-field and paused-restart cases on `f0da03bc69615d55ef57d1b1f4fb0af5a84e32e8`, with manual refresh and a stale paused pending-count finding. The same report records the owner's later repair request, the frozen repair patch, passing local qualification and signed Mac/physical-iPhone count rechecks without app relaunch. After resume, the Mac-created repair note reached iPhone, but the iPhone-created repair task remained absent from Mac despite manual checkpoints and no presented pending work; that delivery/presentation discrepancy is unresolved. The count repair does not close the full matrix below or authorize Stage 12E. The owner explicitly allowed existing non-test content in their private Development database; the disposable-content assumption was waived for that run, and exact personal-data preservation was not audited.

1. Owner identifies a disposable test Apple account, Mac and physical iPhone, and approves the Development-only run. Record the account identity without credentials, device/OS identities, exact source revision, build identities and effective signed Development entitlements. No personal notes or Production records are needed.
2. Verify both upgrade orders using explicit V2 fixtures: existing Mac and cloud colors survive, valid old record versions merge, and the pending outbox returns to zero. Check one canonical, content-free `TDClient` registration per replica.
3. With synthetic notes, confirm title, color, note kind, single-memo font, task indentation, completion and rich text arrive correctly in both directions. Repeat with offline edits, termination/relaunch, reconnect and conflicts; check for duplicates or resurrected content.
4. Check foreground refresh and failure attention, pause/resume with continued local editing, restart while paused, and safe account separation. Pausing must preserve the workspace and pending edits. Evaluate the Mac attention surface with keyboard and VoiceOver, and the iPhone with Dynamic Type and accessibility settings.
5. Review adoption and zone-reset recovery policy before testing those paths. Any live mutation or destructive zone/reset case needs its own explicit approved scope. Never reset the environment to hide a failed case.
6. Retain dated results and failures, obtain Stage 12C acceptance and owner decisions, then refresh the schema comparison. Only afterward request separate Stage 12E authorization for the exact final schema diff.
