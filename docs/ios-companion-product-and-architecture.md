# Tildone for iPhone: Product and Technical Architecture

Status: proposed architecture for review  
Repository baseline: macOS Tildone 1.6.0 (build 24), inspected 2026-07-12  
Scope: planning only; this document does not authorize implementation

## How to read this document

Statements prefixed **Fact** come directly from the repository. **Platform fact** is backed by linked Apple documentation. **Recommendation** is the proposed direction. **Open decision** requires product-owner input. **Inference** is a conclusion from the available evidence and must be validated during implementation.

## 1. Executive summary

Tildone for iPhone should be a complete, local-first checklist-note app that happens to synchronize with the Mac app when the same person uses iCloud. It should not present itself as a Mac remote control, require the Mac to be reachable, or reproduce sticky windows. The first screen is a native notes list; selecting a note opens a focused checklist editor.

**Recommendation:** retain SwiftData as the local persistence technology on both platforms, but place the new sync-ready models and domain operations in a local shared Swift package, tentatively `TildoneCore`. Synchronize those local stores with the user's private CloudKit database through `CKSyncEngine` and one custom record zone. Explicitly configure SwiftData with `cloudKitDatabase: .none` so the CloudKit entitlement does not accidentally enable SwiftData automatic mirroring.

This is deliberately a hybrid architecture:

- SwiftData remains the durable, immediately writable local source of truth.
- `CKSyncEngine` schedules transfers, tracks server changes, handles notifications and retries, and reports account changes.
- Tildone owns record mapping, durable pending changes, tombstones, and deterministic field-level conflict rules.
- A side-by-side migration copies released Mac data into a new sync-ready store, verifies it, and keeps the legacy store available for rollback during a defined safety window.

This requires a substantial persistence-boundary change in the Mac app, but not an AppKit window rewrite. `Desktop`, the Mac `Note` view, window styling, menus, and settings can remain platform-specific while their direct save/delete calls are gradually routed through shared operations.

The highest-risk work is lossless adoption of the released, unversioned SwiftData store followed by idempotent cloud seeding. The next highest risk is proving merge behavior under concurrent editing, reordering, deletion, partial delivery, and account switches. These must be addressed with migration fixtures and deterministic multi-replica tests before CloudKit is enabled in production.

## 2. Product definition

Tildone is a collection of lightweight notes, and every note is fundamentally an ordered checklist. The shared product object is the note and its tasks, not the Mac window.

The iPhone app has two equal roles:

1. A companion that reads and edits the same private data as Tildone on Mac.
2. A standalone, no-signup to-do app that works before the user owns a Mac or signs into iCloud.

The app is useful immediately with local storage. If iCloud is available, synchronization starts in the background. “Saved” means saved to the current device; it never means “waiting for the Mac” or “waiting for a Tildone server.” The interface must not block creation or editing on network state.

The intended emotional character is fast, calm, and forgiving: very little setup, obvious checklist interactions, no engagement mechanics, and sync information available without dominating the product.

### Product behavior shared across platforms

- Create, rename, and delete notes.
- Create, edit, delete, complete, uncomplete, and reorder tasks.
- Preserve task order and completion state across devices.
- Remove a note from active use after its last task is completed, with a short undo opportunity.
- Work fully offline and converge when iCloud becomes available.

### Platform-specific behavior

- Mac retains sticky windows, window levels, positions, opacity, arrangement, and Mac keyboard behavior.
- iPhone uses a notes list, push navigation, standard editing affordances, touch-sized controls, Dynamic Type, and iOS accessibility behavior.
- Window geometry, minimized state, global Mac note appearance, launch-at-login, and Focus Filter window level are device/platform-local and never synchronize.
- Release/update notes (`systemContent` and `systemURL`) remain Mac-installation UI and do not synchronize.

## 3. User types and core workflows

### Standalone iPhone user

1. Launches directly into a useful empty state; no login or onboarding wall.
2. Taps **New Note**, optionally names it, and immediately types the first task.
3. Adds, edits, reorders, completes, uncompletes, and deletes tasks without a network connection.
4. If iCloud is already available, changes synchronize silently. If it becomes available later, the app explains once that local notes can be placed in the person's private iCloud storage and used on their other devices.
5. Later installs Tildone on Mac under the same iCloud account and sees the same active notes after asynchronous initial synchronization.

### Existing Mac user adding an iPhone

1. Updates the Mac app to a migration-capable release. Its local notes are copied and verified in the new store, then seeded to private CloudKit.
2. Installs and launches the iPhone app under the same iCloud account.
3. The notes list can be used immediately; cloud notes appear incrementally as initial sync completes.
4. Edits on either device save locally at once and reach the other device later.

### Multi-device offline user

1. Edits a note or creates tasks while one or both devices are offline.
2. Each device keeps a durable outbound-change queue.
3. When the devices reconnect, record-level changes merge by stable ID and property version stamps.
4. Conflicts resolve deterministically according to section 13. The UI never creates a second item merely because the same outbound save was retried.

### Completion and deletion workflow

When the last task becomes complete, show a calm completion state and a 20-second undo action, matching the existing Mac grace period. At the end of the grace period, issue a synchronized soft deletion of the note. This is represented by a tombstone, not immediate record destruction. Unchecking a task before the grace period ends cancels the pending deletion. A remote deletion that has already won is not silently reversed by editing stale local content.

This keeps the existing “completion reduces clutter” principle without relying on a window fade as the durable state transition.

## 4. First-release scope

### Required for version 1.0 on iPhone

- No Tildone account, email, password, backend, or mandatory onboarding.
- Local-first note and task storage.
- Notes list showing title or an “Untitled” fallback, remaining/total task count, and a concise preview.
- Create, rename, open, and delete a note.
- Checklist editor with task creation, inline editing, completion/uncompletion, deletion, and drag reordering.
- The existing completion grace/undo concept, implemented as native UI rather than window fading.
- Private-iCloud synchronization between supported Mac and iPhone releases.
- Correct behavior with no account, iCloud disabled, no network, quota/service failures, partial sync, and account changes.
- A small Settings screen containing iCloud state, last successful sync time, pending-change/error state, privacy explanation, app information, and relevant recovery action.
- Dynamic Type through accessibility sizes, VoiceOver, sufficient touch targets/contrast, Reduce Motion behavior, and keyboard commands for common actions.
- English plus the repository's existing Spanish, French, and Simplified Chinese localizations for shared concepts; platform-specific strings require their own translations.
- Migration of all released Mac user content without discarding the legacy store before verification.

### Valuable follow-up functionality

- Search across note titles and task text, implemented locally.
- Home Screen quick action, widget, or App Intent for fast capture after the core sync experience is proven.
- Native iPad two-column layout and richer hardware-keyboard navigation.
- User-visible conflict recovery for the rare case of two simultaneous text rewrites, if telemetry-free support evidence shows it is needed.
- Export/import or a local backup format.
- A bounded trash/recently deleted UI, only if users need recovery beyond the completion grace period.

### Explicitly out of scope

- Projects, folders, tags, priorities, due dates, reminders, recurring tasks, dependencies, subtasks, Kanban boards, or progress planning.
- Collaboration, sharing, public links, family/team spaces, or a CloudKit shared database.
- Attachments, images, files, rich text, Markdown authoring, or comments.
- Tildone accounts, social login, subscriptions required for sync, or a proprietary backend.
- Web, Android, or Windows clients.
- A remote-control relationship with a Mac.
- Synchronizing Mac window geometry, window level, minimized state, opacity, arrangement, launch-at-login, or installation-specific release notes.
- An activity feed, permanent version history, or project-management analytics.
- Native iPad-specific information architecture in the first release. The iPhone app may run in iPhone compatibility mode on iPad; a universal adaptive layout should be a separately scoped follow-up.

## 5. Explicit non-goals

The first release does not attempt to make synchronization instantaneous, expose CloudKit terminology in ordinary editing, or guarantee that a device which has never completed an initial sync contains the full corpus. It does not merge prose character-by-character, infer that two independently created tasks with the same text are duplicates, or resurrect deleted records automatically.

It also does not preserve the current implementation structure unchanged. A cross-platform sync product needs stable identity, explicit lifecycle state, and a persistence boundary; keeping view-owned saves and physical deletion would be a larger product risk than a staged internal refactor.

## 6. Proposed iPhone information architecture

### Notes list: root screen

Use a `NavigationStack` with **Notes** as the title.

- Primary action: a prominent but standard compose button in the toolbar. Creating a note should navigate directly to its editor and focus the title or first task field.
- Rows: title/Untitled, pending count, and up to one short task preview. Avoid dense metadata.
- Default order: most recently meaningfully edited note first. Do not reuse task order to order notes.
- Delete: trailing swipe plus a confirmation when the note contains incomplete tasks. Toolbar/menu deletion remains available for accessibility and keyboard users.
- Empty state: a checklist illustration or SF Symbol, “Start with a note,” one sentence explaining that every note is a checklist, and **New Note**. Do not require an iCloud decision first.
- Initial sync: show imported notes as they arrive. A small nonmodal status row/banner may say “Updating from iCloud…”; never replace the list with a blocking spinner.
- Search is deferred from the first release. The expected note volume is small and the repository has no existing search behavior. Re-evaluate from testing rather than adding scope preemptively.

### Note/checklist editor

- Navigation title is editable or a clearly placed title field. Empty title remains valid.
- Pending and completed tasks appear in one checklist, preserving the canonical order. Completed rows are visually subdued but remain available for unchecking during the note's active life.
- A persistent “New task” row or bottom input minimizes capture friction. Return commits and keeps capture nearby.
- Tapping task text edits inline. Commit on Return or focus loss; local debouncing may reduce save churn but must not risk losing the draft on backgrounding.
- Checkbox has at least a 44-by-44-point activation area and a VoiceOver action/label expressing current state.
- Drag handles appear in edit mode or while long-press dragging. Also expose **Move Up** and **Move Down** accessibility actions; drag-and-drop cannot be the only reorder mechanism.
- Delete through swipe/context menu, plus keyboard Delete when an entire row is selected. Do not delete a nonempty task merely because its text field became empty during editing without an undo path.
- Completing the last task shows the completion state with **Undo** and a visible grace countdown only if it remains calm. Respect Reduce Motion and do not depend on animation for meaning.

### Settings and status

Keep Settings short:

- iCloud: Available / Updating / Offline (changes saved here) / Not signed in / Disabled / Attention needed.
- Last successful synchronization time and count of pending local changes when nonzero.
- A retry action only for actionable errors; normal automatic scheduling should not encourage repeated manual refresh.
- A link to the system iCloud settings when no account or iCloud Drive is unavailable.
- A plain-language privacy statement: data is stored on this device and, when enabled, in the user's private iCloud storage; Tildone operates no sync server.
- App version, acknowledgements, and support/privacy links.

Do not show record IDs, zones, queues, or raw CloudKit errors outside a diagnostic export intended for support.

### Accessibility and input

- Use semantic `Button`, `TextField`, `List`, and navigation controls rather than gesture-only custom controls.
- Support all Dynamic Type categories without clipping; multiline tasks should expand and titles may wrap where sensible.
- VoiceOver reads note title, pending count, task text, and completion state in a useful order. Provide named custom actions for complete/uncomplete, delete, and move.
- Preserve color-independent completion cues. Test Increased Contrast, Differentiate Without Color, Reduce Transparency, Reduce Motion, and dark appearance.
- Hardware keyboard: Command-N new note/task according to context, Command-Return complete/uncomplete selected task, Return add/commit, arrows move selection, Option-Command-Up/Down reorder, Command-Delete delete with the same safeguards as touch, Escape cancel editing. Avoid importing AppKit numeric key codes.
- Localize accessibility labels and plural forms.

## 7. Current macOS architecture relevant to the iPhone app

### Repository facts

- [TildoneApp.swift](../Tildone/TildoneApp.swift) creates one persistent SwiftData `ModelContainer` from `Schema([Todo.self, TodoList.self])` with the default local store. No store URL, CloudKit database, App Group, or migration plan is specified.
- [TodoList.swift](../Tildone/Models/TodoList.swift) is the note entity. Persisted fields are `created: Date`, optional `topic`, optional `systemURL`, optional `systemContent`, and `items: [Todo]` inverse to `Todo.list`.
- [Todo.swift](../Tildone/Models/Todo.swift) is the task entity. Persisted fields are `what: String`, `created: Date`, optional `index: Int`, optional `done: Date`, and optional `list`.
- A task is complete when `done != nil`; checking writes the current date and unchecking sets it to nil.
- Display order is optional integer `index`, secondarily stabilized by `created`. Reading through the custom `sorted()` helper fills missing legacy indexes as a side effect.
- The current Mac UI can insert tasks at an index and reindex after deletion, but it exposes no task-reordering operation. Reordering is new product/domain behavior for the synchronized apps.
- Neither model has a UUID or another explicit distributed identifier. `TodoList.hash` and window autosave naming use an ISO-8601 representation of `created`; SwiftUI focus and `ForEach` identify tasks by `created`.
- `TodoList.createNewTask`, `delete`, and `clean` save through the model's injected context. [Note.swift](../Tildone/Views/Note.swift) also saves edits/toggles and deletes tasks directly. [Desktop.swift](../Tildone/Views/Desktop.swift) creates lists, deletes complete/empty lists at termination, and inserts system release notes.
- A final completion starts a 20-second fade after a short delay and then physically deletes the note and its children. Empty rows are physically deleted during cleaning. No tombstones, revisions, modified timestamps, undo store, archive, or sync queue exist.
- Save errors commonly terminate through `fatalError`.
- There is no `VersionedSchema` or `SchemaMigrationPlan`. Existing compatibility is ad hoc: task `index` is optional and backfilled; legacy font and color preferences are converted in UI/settings code.
- [Desktop.swift](../Tildone/Views/Desktop.swift) queries lists and manually creates an `NSWindow` per list. [Note.swift](../Tildone/Views/Note.swift), [Styler.swift](../Tildone/Views/Common/Styler.swift), [WindowAccessor.swift](../Tildone/Views/Common/WindowAccessor.swift), [Copier.swift](../Tildone/Services/Copier.swift), `FocusFilter`, and `Launcher` contain significant AppKit/macOS coupling.
- The project has only macOS app/test/UI-test targets and placeholder tests. The Mac deployment target is 14.0, Swift language mode is 5, marketing version is 1.6.0, build 24, bundle ID is `studio.cuatro.tildone`, and automatic signing uses team `F6HFAVTS49`.
- [Tildone.entitlements](../Tildone/Tildone.entitlements) enables App Sandbox, client networking, user-selected read-only files, and a development APS environment. Its iCloud container and service arrays are empty. These keys do not constitute working iCloud synchronization.

### Consequences

**Inference:** dates are adequate creation metadata but not safe distributed identity. Two records can share a date, a date can be rewritten, and clock differences are not a revision order.

**Inference:** optional contiguous integers work for one-process reorder but are conflict-amplifying: inserting or moving one task rewrites many neighbors, and concurrent devices can produce duplicate indexes.

**Inference:** automatic physical deletion makes delete-versus-edit irrecoverable and provides no durable proof to an offline device that a record was intentionally removed.

**Inference:** the Mac window coordinator currently opens the initial queried set and is not designed to reconcile remote insertions/deletions while running. Sync adoption needs an observation/reconciliation path independent of window construction.

## 8. Proposed shared domain architecture

Create a local Swift package named `TildoneCore` during implementation. It should have no AppKit or UIKit dependency and should target macOS 14 and iOS 17.

Suggested boundaries:

```text
TildoneCore
  Domain            Note/task rules, IDs, version stamps, order tokens
  Persistence       New SwiftData models, versioned schema, repositories
  SyncModel         Cloud record mapping and deterministic merge functions
  TestSupport       Fixtures, replica simulator, migration assertions

TildoneMac
  LegacyMigration   Reads released TodoList/Todo store into new store
  AppKit UI          Desktop, Note windows, Styler, commands, Focus Filter
  Platform adapters Mac clipboard, launch at login, update notes

TildoneiOS
  SwiftUI UI         Notes list, checklist editor, Settings
  Platform adapters iOS lifecycle, keyboard, system settings links
```

The UI should call typed operations such as `createNote`, `renameNote`, `addTask`, `setTaskCompletion`, `moveTask`, `deleteTask`, and `deleteNote`. A repository/service performs one local transaction, stamps the changed property, records durable outbound work, and reports recoverable errors. Views must not decide sync rules or call CloudKit.

Do not move the existing `Todo` and `TodoList` types into the package in place. Their persistence identity is part of a released store, and a module/type move may make migration harder to reason about. Instead, define the new sync-ready stored types in their final shared module and perform an explicit side-by-side import from the legacy Mac types.

The package is recommended over adding the same files to two targets because it makes platform dependencies enforceable and gives domain/migration/merge rules one testable home. It is local to the repository and introduces no third-party dependency.

## 9. Evaluation of viable iCloud synchronization approaches

Apple describes CloudKit as the structured-object option, `NSPersistentCloudKitContainer` as the managed local-replica option, and `CKSyncEngine` as the option for apps bringing their own local persistence and conflict behavior ([Apple: choosing a CloudKit approach](https://developer.apple.com/documentation/cloudkit/deciding-whether-cloudkit-is-right-for-your-app)).

| Approach | Fit with current app | Offline/local-first | Conflict control | Migration/maintenance assessment |
| --- | --- | --- | --- | --- |
| SwiftData automatic CloudKit | High code-level continuity | Yes | Limited application visibility/control | Lowest initial code, but schema constraints and opaque mirroring work against explicit reorder/tombstone semantics |
| Core Data + `NSPersistentCloudKitContainer` | Low; repository is SwiftData | Yes | Managed import plus Core Data merge policies | Mature and well tested, but requires a full persistence rewrite for no clear product gain |
| SwiftData local + `CKSyncEngine` | High | Yes | High; Tildone maps and merges records | More sync code and tests, but best match for deterministic field, order, and deletion rules |
| Custom SQLite/other local store + `CKSyncEngine` | Low | Yes | High | Replaces working local persistence unnecessarily |
| Direct `CKDatabase`/operations | Medium | Only with substantial custom work | Maximum | Reimplements scheduling, tokens, notifications, retries, and account handling already supplied by `CKSyncEngine` |
| `NSUbiquitousKeyValueStore` | Poor | Not a structured local database | Poor | Intended for small preferences; limited to 1 MB and 1,024 keys ([Apple limits](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore)) |
| iCloud Documents/ubiquitous container | Poor | Possible | File-conflict level | Tildone is a mutable object graph, not an existing `UIDocument`/`NSDocument` app; whole-file conflicts and coordination add risk |

### Decision record A: persistence and CloudKit integration

**Context:** the released Mac app already uses SwiftData and must preserve local data. Product requirements demand local-first use plus explainable conflict behavior for independently mutable task properties, reorder, and deletion.

**Options considered:** SwiftData automatic CloudKit, Core Data with `NSPersistentCloudKitContainer`, SwiftData plus `CKSyncEngine`, direct CloudKit operations, and replacing local persistence.

**Recommendation:** a new shared SwiftData store synchronized with the private database through `CKSyncEngine`; automatic SwiftData CloudKit disabled explicitly.

**Advantages:** preserves SwiftData and SwiftUI integration; keeps a real local replica; lets Tildone own stable record names, tombstones, order tokens, merge rules, and quarantine; `CKSyncEngine` still handles scheduling, change delivery, deduplication of pending engine work, transient retries, push notifications, and account-change events. Apple specifically positions it for bring-your-own persistence ([WWDC23: Sync to iCloud with CKSyncEngine](https://developer.apple.com/videos/play/wwdc2023/10188/)).

**Disadvantages:** Tildone must implement durable mapping/queue integration, conflict resolution, account-scoped stores, schema version handling, partial-result repair, and a large test matrix. This is materially more work than switching on automatic mirroring.

**Migration implications:** do not cloud-enable the released store in place. Build a new versioned store, import and verify legacy objects, then seed records by stable ID. Retain rollback evidence.

**Remaining uncertainty:** prototype `CKSyncEngine` background behavior and event handling on the exact shipping Xcode/OS versions; confirm that the chosen record batching behavior meets parent/task partial-delivery assumptions.

### Decision record B: why not SwiftData automatic CloudKit

**Context:** SwiftData can automatically synchronize when the app has CloudKit entitlements, and it is implemented using `NSPersistentCloudKitContainer`. Apple requires a CloudKit-compatible schema: unique constraints cannot be enforced in CloudKit, relationships must be optional, `deny` deletion is unsupported, and the production schema is additive ([Apple: SwiftData device sync](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)).

**Options considered:** accept framework conflict/deletion behavior; add metadata and post-import reconciliation; or own CloudKit records through `CKSyncEngine`.

**Recommendation:** reject automatic mirroring for user content in the first synchronized release.

**Advantages of rejection:** Tildone can distinguish a task text edit from completion and reorder, keep durable tombstones, use UUID record names, quarantine incompatible records, and write deterministic tests without relying on undocumented mirror internals.

**Disadvantages:** more implementation and operational responsibility; fewer behaviors arrive “for free.”

**Migration implications:** the CloudKit schema is Tildone's explicit `Note`/`Task` record schema rather than the framework-owned Core Data mirroring schema. Do not later point automatic mirroring at the same container; Apple warns that SwiftData/Core Data managed containers require compatible framework-owned schemas.

**Remaining uncertainty:** a short prototype may demonstrate that a simpler automatic-mirroring model meets all acceptance tests. If so, this decision can be revisited before production schema deployment, not after.

## 10. Recommended persistence and synchronization architecture

### Local source of truth

Each installation has a SwiftData store containing notes, tasks, tombstones, sync metadata, and pending mutations. A successful local transaction immediately updates UI and is the definition of a successful user action. Cloud synchronization is asynchronous.

Use a `VersionedSchema` and `SchemaMigrationPlan` from the first new store version. Apple provides these APIs for explicit SwiftData schema evolution ([`SchemaMigrationPlan`](https://developer.apple.com/documentation/swiftdata/schemamigrationplan)). Never make production CloudKit schema promotion the first migration test.

### Cloud topology

- One developer-owned iCloud container; proposed identifier `iCloud.studio.cuatro.tildone`, subject to availability and owner approval.
- User content only in `CKContainer(...).privateCloudDatabase`.
- One custom zone, for example `TildoneUserData`, enabling zone-change synchronization and atomic multi-record saves where the API path supports them. Apple notes that custom zones support atomic record batches ([`CKRecordZone`](https://developer.apple.com/documentation/cloudkit/ckrecordzone)).
- Explicit record types `TDNote` and `TDTask`; optional `TDSchemaMarker` for minimum-compatible schema metadata.
- Deterministic record names: `note-<UUID>` and `task-<UUID>`. Retrying a create addresses the same server record.
- A task record carries its owning note UUID/reference. The importer tolerates task-before-note delivery and does not depend on CloudKit cascade deletion.

### Sync coordinator responsibilities

Initialize `CKSyncEngine` early in app launch when an account-scoped workspace is active. Persist its serialized state atomically with the account workspace. Feed it durable pending record saves/deletes and apply fetched changes to the local store through the same pure merge functions used in tests.

`CKSyncEngine` provides scheduling, push handling, fetch/send orchestration, serialized engine state events, account change events, and automatic retry for common transient network/service/rate-limit errors. Its schedule is intentionally indeterminate; even Apple’s managed Core Data sync is described as asynchronous rather than immediate ([Apple: Core Data store sync](https://developer.apple.com/documentation/coredata/syncing-a-core-data-store-with-cloudkit)).

Tildone must provide:

- Local record-to-`CKRecord` mapping.
- Persistent mutation capture and idempotent pending work.
- `serverRecordChanged` merge and rescheduling.
- Tombstone and garbage-collection policy.
- Partial-failure application/repair.
- Account-scoped local-store selection and data isolation.
- Schema compatibility checks and quarantine.
- User-facing state derived from local/engine events.

CloudKit reports per-item partial failures and provides server/client/ancestor information for record conflicts; retry timing is included for rate limiting or service unavailability ([`CKError`](https://developer.apple.com/documentation/cloudkit/ckerror), [`CKErrorRetryAfterKey`](https://developer.apple.com/documentation/cloudkit/ckerrorretryafterkey)).

### Store separation

Use separate physical workspaces for:

1. Local-only content created while no iCloud account has ever been adopted.
2. Each confirmed iCloud account seen on the device, keyed by a non-content opaque account identity.
3. The legacy Mac store, read only after successful migration except for rollback.

This prevents one person's cached private notes from becoming visible after a confirmed account switch. A network outage does not change workspace; a confirmed sign-out/switch does.

## 11. Reasons for rejecting the other approaches

### Core Data with `NSPersistentCloudKitContainer`

It provides a local replica and extensive framework-managed CloudKit behavior, and Apple recommends it for existing Core Data apps that do not need granular sync control. Tildone is not an existing Core Data app. Rewriting both models, queries, previews, and persistence tests in Core Data would increase migration surface while still requiring product-level rules for completion and order. It is a valid fallback only if SwiftData migration proves defective or unsupported in production testing.

### Direct CloudKit APIs

Direct `CKDatabase`/`CKOperation` code would expose every knob but require Tildone to schedule operations, persist change tokens, register/listen for changes, process account changes, and implement retry behavior. Apple identifies that path as the most intricate. `CKSyncEngine` retains record-level control without reproducing this infrastructure.

### `NSUbiquitousKeyValueStore`

Its 1 MB/1,024-key quota and dictionary synchronization model suit preferences, not an unbounded graph of notes, tasks, deletions, and revisions. It may later synchronize one or two non-sensitive preferences, but should not hold user content or sync state.

### iCloud Documents

The current app does not have a document model. A monolithic file would cause unrelated note edits to conflict; a file per note would require document coordination, index discovery, deletion tracking, and cross-file consistency. Neither maps cleanly to current SwiftData relationships or fine-grained task mutation.

### Entirely custom local persistence

SQLite, GRDB, files, or another database could work but would discard the existing SwiftData investment and add a dependency or bespoke storage layer. No repository evidence justifies that cost.

## 12. Proposed data model, stable identifiers, and sync metadata

The exact Swift names are implementation details; the logical schema is:

### Note

| Field | Purpose | Sync rule |
| --- | --- | --- |
| `id: UUID` | Permanent cross-device identity and Cloud record name | Immutable |
| `createdAt: Date` | User-visible/stable creation metadata | Immutable after import |
| `title: String?` | Optional note title | Merge with `titleVersion` |
| `titleVersion: VersionStamp` | Version of title only | Deterministic maximum |
| `lifecycle: active/deleted` | Visibility/tombstone state | Merge with `lifecycleVersion`; deletion dominates ordinary field edits |
| `lifecycleVersion: VersionStamp` | Create/delete/explicit-restore version | Deterministic maximum |
| `lastMeaningfulEditAt: Date` | Notes-list sorting/display only | Derived/merged, never used as identity |
| `schemaVersion: Int` | Record decoder compatibility | Reject/quarantine unsupported future major versions |

### Task

| Field | Purpose | Sync rule |
| --- | --- | --- |
| `id: UUID` | Permanent identity and record name | Immutable |
| `noteID: UUID` | Owning note | Immutable in MVP; moving between notes is out of scope |
| `createdAt: Date` | Creation metadata and fallback diagnostics | Immutable |
| `text: String` | Task text | Merge with `textVersion` |
| `textVersion: VersionStamp` | Text edit version | Deterministic maximum |
| `isCompleted: Bool` | Explicit completion state | Merge with `completionVersion` |
| `completedAt: Date?` | Display/audit metadata, not the conflict authority | Travels with winning completion payload |
| `completionVersion: VersionStamp` | Toggle version | Deterministic maximum |
| `orderToken: String` | Position between neighboring active tasks | Merge with `orderVersion`, then sort by token and ID |
| `orderVersion: VersionStamp` | Reorder version for this task | Deterministic maximum |
| `lifecycle: active/deleted` | Task tombstone | Deletion dominates ordinary field edits |
| `lifecycleVersion: VersionStamp` | Delete/explicit-restore version | Deterministic maximum |
| `schemaVersion: Int` | Decoder compatibility | As above |

### Version stamps

A `VersionStamp` is a comparable pair `(logicalCounter, replicaID)`:

- `replicaID` is a random installation identifier stored outside user content.
- The local counter advances beyond the maximum counter observed or generated in the active account workspace.
- Compare counter first, then replica ID lexicographically as a deterministic tie-break.
- Wall-clock dates never choose a conflict winner because device clocks may be wrong.
- Each mutable property has its own stamp so toggling completion does not overwrite a concurrent text edit.

This is a Lamport-style total order, not a full causal history. It deliberately gives a deterministic winner at low metadata cost. When a `serverRecordChanged` response demonstrates divergent text payloads from the same ancestor, keep a bounded local `ConflictSnapshot` containing the losing text and record ID for diagnostic/recovery purposes; do not sync or display it in normal flow. Decide retention before implementation.

### Order tokens

Replace contiguous `index` with a variable-length lexicographically sortable fractional-position token. Creating or moving a task generates a token strictly between its intended neighbors; it does not rewrite every neighboring task. If concurrent inserts produce equal tokens, task UUID is the stable secondary sort. If token growth eventually requires compaction, perform it as an explicit, versioned maintenance operation only when no local outbound order mutations exist; compaction is follow-up work, not a prerequisite for ordinary small lists.

### Tombstones

Deleting a task/note writes a minimal tombstone record instead of physically deleting it. Tombstones are hidden locally and in UI. For the first release, retain cloud tombstones indefinitely: Tildone data volume is tiny, and permanent tombstones prevent a device offline for months from resurrecting stale content. A later compaction design must include an account-level deletion epoch or proof that all replicas have advanced; a simple 30/90-day purge is unsafe.

### Local-only fields

SwiftData may also store sync state, pending mutation IDs, quarantine information, migration provenance, and engine state. These are not content records. Mac system notes and presentation settings are marked local-only and excluded from Cloud mapping.

## 13. Conflict-resolution strategy

Merge is pure, deterministic, commutative, and idempotent. The same two logical records must produce the same result in either order and repeated application.

| Conflict | Rule | Rationale |
| --- | --- | --- |
| Different properties edited | Merge each property independently | A completion toggle must not erase a text edit |
| Same note title edited | Higher `titleVersion` wins; preserve detected losing value locally for bounded recovery | Character merge is surprising for short titles |
| Same task text edited | Higher `textVersion` wins; preserve detected losing value locally | Deterministic whole-field resolution avoids corrupt hybrid text |
| Complete vs uncomplete | Higher `completionVersion` wins; its Boolean and `completedAt` travel together | A toggle is one logical property, separate from text/order |
| Two tasks inserted at same location | Keep both; order by fractional token, then UUID | They are independent creations, not duplicates |
| Same task moved twice | Higher `orderVersion` wins | One task cannot occupy two intended positions |
| Different tasks reordered concurrently | Apply each task's winning token; sort token then UUID | Avoids whole-list last-writer-wins and preserves both moves when possible |
| Task deleted vs text/completion/order edit | Tombstone wins; ordinary edits cannot clear lifecycle deletion | Prevents stale resurrection |
| Note deleted vs child edit/create | Note tombstone hides and tombstones children during reconciliation | Explicit parent deletion wins over stale child activity |
| Explicit undo during local grace | Write a newer active lifecycle version before deletion is sent, or cancel the unsent deletion transaction | Makes the visible Undo action authoritative |
| Duplicate delivery/retry | Upsert by record name/stable UUID; merge idempotently | Network retries never create another object |
| Two independently created identical texts | Keep both | Text equality does not prove duplicate intent |

“Last write wins” is therefore used only within a single logical property and uses logical versions, not device time. Notes are not overwritten as blobs; order is not a whole-array property; deletes have explicit lifecycle semantics.

Normalize after every merged batch:

1. Hide tombstoned notes/tasks.
2. Quarantine tasks with invalid IDs/schema; retain valid orphan tasks until their parent arrives.
3. Sort active tasks by `orderToken`, then UUID.
4. Derive completion and pending counts; never sync these redundant values.
5. If a note tombstone is active, create missing child tombstones locally and enqueue them.

## 14. Offline behavior

- Every mutation commits to SwiftData first and updates the UI immediately.
- Pending cloud mutations survive termination, crashes, and device restart.
- Ordinary offline state needs no alert. Settings says “Offline — changes saved on this device,” and a subtle status appears in the editor only after a meaningful delay or actionable failure.
- Do not optimisticly claim “Synced” merely because local save succeeded. Status categories should be `saved locally`, `pending`, `syncing`, `up to date as of <time>`, and `attention needed`.
- Background suspension may delay sending. On foreground, initialize/restore the engine and allow automatic sync; offer manual retry for recoverable stuck state, not a permanent refresh button.
- Partial fetch/save results are applied per record. Successful records remain successful; failed IDs stay queued with their specific error. UI tolerates a temporarily missing parent/task rather than rolling back unrelated records.
- Temporary CloudKit/network failures use engine retry and CloudKit retry hints. Never delete cached data or block editing because the service is unavailable.

## 15. Existing-user migration plan

### Decision record C: side-by-side migration

**Context:** the released Mac store is unversioned, uses dates as practical identity, has optional legacy indexes, and physically deletes content. Existing data cannot be discarded.

**Options considered:** alter and cloud-enable the current store in place; add optional fields and backfill in place; or copy into a newly named/versioned store.

**Recommendation:** side-by-side import into a new store defined in `TildoneCore`.

**Advantages:** legacy store remains intact; mapping can be verified before cutover; new model names/module and schema are final from version 1; cloud seeding is separated from local migration; rollback and support are possible.

**Disadvantages:** temporary disk duplication, explicit migration code, and careful handling of edits during cutover.

**Migration implications:** Mac UI must be briefly read-only during the local copy transaction or migration must occur before windows open. Do not upload until verification succeeds.

**Remaining uncertainty:** exact on-disk default store URL and whether all released 1.0–1.6 stores open with the current model must be established from real fixtures, not inferred.

### Proposed stages

1. **Fixture collection:** create anonymized/reproducible stores from every obtainable released model shape, especially tasks with nil index, empty titles/tasks, completed notes, system notes, Unicode, and large lists.
2. **Migration-capable Mac release:** ship the new shared store and importer while sync remains feature-gated off.
3. **Quiesce:** before opening note windows, open the legacy container, stop user mutation, and enumerate all objects.
4. **Map:** assign a random UUID once per legacy note/task; preserve `created`, topic, text, completion timestamp, and ownership. Convert the current sorted order into initial fractional tokens. Treat nil/duplicate indexes using the released `sorted()` semantics so visible order does not change.
5. **Classify:** exclude `systemContent`/`systemURL` release notes from cloud user data. Preserve them locally only if still relevant. Do not migrate empty transient task rows as user content.
6. **Seed versions:** use deterministic migration stamps from one migration replica and increasing counters. Preserve `done` as `isCompleted` plus `completedAt`.
7. **Verify:** compare note counts, task counts per note, normalized content hashes, ownership, completion, and order. Reopen the new store in a fresh process and verify again.
8. **Cut over atomically:** write a migration-complete marker containing source fingerprint and destination schema version. Only then make the new store active.
9. **Retain rollback:** keep the legacy store read-only for at least one successful app release and a product-approved time window. Never automatically switch back after cloud edits have started; that could fork history.
10. **Cloud seed:** enqueue each migrated content record once using its stable record name. Persist a seed generation/marker. Retries upsert the same IDs.
11. **Reconcile before declaring completion:** fetch the private zone, merge any iPhone-originated records, and send remaining Mac records. This supports iPhone-first users later installing Mac.

If two Macs independently migrate equivalent pre-sync stores, they will receive different UUIDs and both copies will appear. Content-based deduplication risks deleting legitimate repeated tasks/notes and is not recommended. Document this edge case and consider a preflight user choice only if multiple-Mac evidence warrants it.

## 16. iCloud account and failure-state behavior

### New device and initial sync

Open the local workspace immediately. Start `CKSyncEngine`, create/fetch the custom zone, fetch changes, and merge incrementally. Do not send a “sync finished” signal until the current change token is drained and pending outbound work is acknowledged. Initial sync can be interrupted and resumed from persisted engine state.

### No account or iCloud disabled

The app remains a complete local-only to-do app. Show one quiet explanation in Settings, not a launch blocker. If the user later signs in, ask once whether to use private iCloud sync and merge the local-only workspace into the new account workspace. **Open decision:** whether this is opt-in or automatic with notice; explicit opt-in is safer and recommended.

### Network loss

Keep the same account workspace fully editable and queue changes. Network loss is not an account change.

### Temporary account unavailability

Keep cached data and stop new cloud operations until availability returns. Apple explicitly says not to delete cached data or enqueue extra operations for `accountTemporarilyUnavailable`, and to wait for account change notification ([Apple guidance](https://developer.apple.com/documentation/cloudkit/ckerror/code/accounttemporarilyunavailable)). Local user mutations remain durable and can be added to Tildone's local pending log even while submission is paused.

### Confirmed sign-out or account switch

Finish the current local transaction, close/lock the old account store, persist its pending state, and do not expose its content in the new account workspace. Open a fresh local-only/new-account workspace. Never upload old-account notes to the new account automatically. On returning to the prior account, reopen its cache and resume. `CKSyncEngine` reports sign-in, sign-out, and switch events; a `CKContainer` also posts account-change notifications ([Apple account notification](https://developer.apple.com/documentation/cloudkit/ckaccountchangednotification)).

### Quota, permission, and service failures

- Network/service/rate-limit: automatic backoff; nonblocking status.
- Quota exceeded: local use continues; show an actionable Settings warning explaining that other devices may not update and link to iCloud storage management.
- Permission/restriction: local use continues; stop futile retries until account/capability changes.
- Partial failure: keep only failed IDs pending and surface a general issue if it persists.
- Zone deleted/reset by user: do not blindly re-upload stale cache. Freeze sync, create a recovery snapshot, and ask whether to restore cached local content to a new zone or start empty. This decision needs product copy and destructive-action review.

### Malformed or incompatible records

Validate type, IDs, required payloads, version stamps, ownership, and schema version before applying. Store the record ID, type, error category, and safe metadata in a local quarantine; do not log note/task text. Continue applying valid records. Unsupported future major schema versions put sync in read/local-only safety mode and display “Update Tildone to continue syncing,” rather than overwriting newer data.

## 17. Privacy and security implications

- User content is stored locally and in the user's private CloudKit database only. No public/shared database and no Tildone-operated service is needed.
- Task text can be sensitive. Do not include titles/task text in logs, analytics, crash breadcrumbs, push payloads, record IDs, or support diagnostics by default.
- Do not add third-party analytics or crash collection as part of sync work. If introduced separately, it requires a privacy decision.
- Protect local stores using the platform's normal application data protection and sandbox. Evaluate stronger file protection on iOS without preventing required background CloudKit work.
- Account-scoped stores prevent data leakage across Apple Account switches on a shared device.
- CloudKit container access, production roles, and CloudKit Console access should follow least privilege. Use separate development and production environments and dedicated test accounts.
- The current App Store statement “Data Not Collected” must be re-evaluated against Apple's current App Privacy definitions before submission. Do not assume private iCloud sync automatically preserves or invalidates that label; document exactly what the developer can access and how data is used.
- Update the privacy policy to explain device storage, private iCloud transfer, lack of a Tildone account/backend, offline operation, and what happens on sign-out or deletion.

## 18. Required capabilities, entitlements, containers, and configuration

Both Mac and iOS targets require configuration for the same CloudKit container:

- iCloud capability with CloudKit service.
- `com.apple.developer.icloud-container-identifiers` containing the approved container ID.
- `com.apple.developer.icloud-services` including `CloudKit` as generated by Xcode.
- Push Notifications capability / APS environment appropriate to development or production.
- Background Modes with **Remote notifications** on iOS; configure the corresponding Mac remote-notification support required by the chosen SDK and test it.
- Existing App Sandbox/network client entitlement retained on Mac.
- Explicit `CKContainer(identifier:)` and explicit SwiftData `ModelConfiguration(cloudKitDatabase: .none)` to prevent automatic-mirroring ambiguity.

Apple says enabling CloudKit configures container entitlements and push notifications, and that containers cannot be renamed or deleted after creation ([Configuring iCloud services](https://developer.apple.com/documentation/xcode/configuring-icloud-services), [Enabling CloudKit](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app)). Therefore the container identifier and owning team are pre-implementation decisions.

Development steps include creating/associating the container with both App IDs, initializing the development schema, adding query indexes only where needed, testing in development, and promoting the exact schema to production before release. Production CloudKit schema evolution is additive; avoid speculative fields/types and never use production as a test environment.

**Proposed deployment targets:** retain macOS 14.0 and choose iOS 17.0. This aligns with the repository's SwiftData baseline and the generation in which `CKSyncEngine` was introduced, minimizes conditional persistence code, and still requires a current device-support/business check before commitment. Raising the Mac minimum is not recommended for the iPhone project.

**Open App Store decision:** whether the iPhone app is added as an iOS platform under the existing App Store product/universal-purchase arrangement or shipped as a separate listing/bundle ID. This affects product identity, review, pricing, receipt behavior, and capability setup. The iCloud container can be shared across distinct App IDs owned by the same team if configured correctly.

Signing/provisioning must be validated with team `F6HFAVTS49`, active Developer Program membership, admin permission to create/configure CloudKit, production provisioning profiles containing the shared container, and TestFlight builds using the production CloudKit environment as Apple configures it. Development and production data are separate.

## 19. Testing strategy

The existing tests are placeholders, so sync cannot rely on regression coverage that is not present.

### Pure domain tests

- Stable UUID/record-name round trips.
- Version-stamp comparison and counter advancement.
- Merge laws: commutative, associative where defined, idempotent.
- Property independence: text plus completion plus order edits all survive.
- Completion toggles, title/text conflicts, delete-versus-edit, explicit undo.
- Fractional insertion at beginning/end/between, equal-token tie, repeated moves, long-token thresholds.
- Tombstones never resurrect through stale updates.
- Fuzz/property tests over random operation sequences and delivery orders.

### Persistence tests

- CRUD and durable pending work across process/container recreation.
- Atomic local transaction: content change and outbound mutation are either both present or neither is.
- SwiftData schema migration fixtures for each new version.
- Malformed/orphan/quarantined data does not crash or block valid records.
- Account workspaces remain isolated.

### Legacy migration tests

- Realistic fixtures from released versions, especially nil/duplicate task indexes.
- Counts, content, ownership, completion timestamps, order, Unicode, empty records, and system-note classification.
- Crash/interruption at every migration phase; restart is idempotent.
- No cloud enqueue before verification marker.
- Seed retry creates no duplicate records.
- Disk-full/store-open failure leaves legacy data usable.

### Sync simulation

Build an in-memory two/three-replica harness around the pure record merger. Randomly partition replicas, reorder/deduplicate/drop deliveries, inject partial success, and assert convergence. Include:

- Concurrent new tasks at same location.
- Same-task text and completion edits.
- Different-task and same-task reorders.
- Delete note while another device creates/edits a child.
- Months-offline stale replica returning after tombstones.
- Initial Mac seed racing with iPhone-originated data.
- Account switch during pending work.
- Future-schema and corrupt records.

### CloudKit integration and device tests

- Dedicated development-container test accounts and at least two physical devices (Mac plus iPhone); simulator alone is insufficient.
- Manual send/fetch in tests where supported for deterministic checkpoints; automatic scheduling in end-to-end longevity tests.
- Airplane mode, poor network, app termination, background suspension, device lock, low power, quota/service fault injection where feasible.
- Development-to-production schema promotion rehearsal and TestFlight validation.
- Do not assume push delivery; test foreground catch-up because Apple notes notifications may be deferred/dropped.

### UI and accessibility tests

- New standalone-user flow and all CRUD/reorder paths.
- Initial sync inserts/deletes while notes list/editor is visible.
- Dynamic Type screenshots through largest sizes, VoiceOver manual scripts, contrast/dark mode, Reduce Motion, touch targets, and keyboard-only operation.
- Mac regression: multiple sticky notes, remote insertion/deletion, completion grace, windows on multiple displays, relaunch, and keyboard behavior.

## 20. Staged implementation plan

No stage should begin under this planning task; these are future implementation gates.

### Stage 0 — decisions and prototypes

- Resolve the open decisions in section 22.
- Prototype `CKSyncEngine` with throwaway records in a development container.
- Prototype new SwiftData schema/package and side-by-side access to a copied released store.
- Write conflict and migration acceptance tests before production code.

Exit: container, bundle/deployment targets, completion semantics, account adoption, and architecture are approved; prototypes retire major unknowns.

### Stage 1 — shared domain and local store

- Add `TildoneCore` with IDs, stamps, order tokens, new models, repositories, and pure merger.
- Add exhaustive domain/persistence tests.
- Keep CloudKit disabled.

Exit: local CRUD and replica simulation pass; no Mac UI behavior changed yet.

### Stage 2 — Mac migration and persistence boundary

- Implement side-by-side importer and verification.
- Route Mac UI mutations through typed repository operations incrementally.
- Teach the Mac window coordinator to reconcile live store insertion/deletion.
- Preserve AppKit behavior and keep sync feature-gated off.

Exit: released-store fixtures migrate losslessly; Mac regression suite passes; rollback is documented.

### Stage 3 — sync engine behind a development flag

- Configure development entitlements/container.
- Implement record mapping, account workspaces, pending mutations, tombstones, quarantine, and status model.
- Run multi-device destructive testing before schema promotion.

Exit: convergence and recovery matrix passes on physical Mac/iPhone devices with no data loss.

### Stage 4 — iPhone MVP UI

- Add the iOS target only after shared/local architecture is stable.
- Build notes list, checklist editor, Settings/status, accessibility, localization, and keyboard support.
- Test as a standalone app with iCloud unavailable.

Exit: complete local MVP and cross-device acceptance flows pass.

### Stage 5 — production readiness and rollout

- Finalize container ownership, provisioning, production schema, privacy policy/App Privacy answers, support diagnostics, and rollback/runbook.
- Ship the migration-capable Mac release before or with iPhone availability.
- Use phased release/feature gating so Mac migration health can be observed without content telemetry.

Exit: production schema promoted, both apps approved/configured, migration and recovery support prepared.

## 21. Main risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Legacy SwiftData store cannot be opened/mapped reliably | Existing Mac data loss or blocked update | Real release fixtures, side-by-side copy, verification, retained source, sync gated until success |
| Cloud seed repeats or races iPhone data | Duplicates or overwrite | Stable UUID record names, seed marker, fetch/merge, idempotent upsert |
| Custom sync merge defect | Silent divergence/data loss | Pure merger, property/fuzz tests, multi-replica simulator, development-container soak |
| Reorder token defects/growth | Unexpected order | Fractional tokens, UUID tie, thresholds, no automatic compaction in MVP |
| Physical/timed deletion races offline edits | Lost edits/resurrection | Durable lifecycle tombstones, delete-dominates rules, grace represented as state transition |
| Account switch leaks cached content | Privacy breach | Account-scoped stores, close/lock on confirmed switch, never cross-upload |
| Automatic SwiftData CloudKit activates accidentally | Two sync owners/corruption | Explicit `.none`, configuration test, one selected container, startup assertion in debug |
| CloudKit schema/provisioning mistake | Release cannot sync; hard-to-reverse schema | Dedicated dev testing, minimal explicit schema, preflight profiles, controlled promotion |
| Partial/late delivery breaks UI | Missing/crashing rows/windows | Orphan tolerance, reconciliation, quarantine, Mac live-window observer |
| Sync status becomes noisy or misleading | Loss of trust | Local-save semantics, small state model, nonmodal errors, last-success and pending count |
| Scope expansion weakens product | Delayed/complex release | Enforce MVP/non-goals; separately approve search, widgets, iPad, recovery UI |

## 22. Open product and technical decisions requiring owner input

These should be resolved before implementation begins:

1. **Completion semantics:** approve synchronized soft deletion after the existing 20-second grace period, or change the product to retain completed notes. The recommendation preserves current behavior with tombstones; a Completed/Archive view is not in MVP.
2. **Local-only to iCloud adoption:** when iCloud first becomes available, should the app ask before uploading local notes? Recommendation: one-time explicit opt-in with a concise privacy explanation.
3. **Container identifier and ownership:** approve the final immutable iCloud container name and confirm team `F6HFAVTS49` ownership/admin access. Proposed: `iCloud.studio.cuatro.tildone`.
4. **App Store packaging:** one existing product with an iOS platform/universal purchase versus a separate iPhone listing/bundle ID.
5. **Minimum iOS:** approve iOS 17.0, subject to current supported-device/customer data. Keeping iOS 16 would require abandoning SwiftData/`CKSyncEngine` or adding a second persistence/sync path and is not recommended.
6. **iPad:** approve iPhone-only first release with iPad compatibility mode, or accept the extra scope of a native adaptive iPad layout. Recommendation: defer native iPad UI.
7. **Conflict-copy retention:** approve a small local-only, bounded recovery cache for losing concurrent title/task text variants and decide its retention (recommendation: 30 days, never logged or synced).
8. **Zone reset recovery:** decide whether the app may offer “Restore this device's cached notes to iCloud” after a user-deleted/reset zone, versus starting empty and retaining only a local export.
9. **Legacy rollback retention:** choose the minimum time/release window before deleting the read-only legacy Mac store. Recommendation: at least one subsequent stable release and 90 days, with explicit support sign-off.
10. **Search:** confirm deferral from MVP. It is technically straightforward locally but not required for the core proposition.

## Assumptions and unverified items

- No released historical store files were present in the repository, so backward compatibility across all public versions could not be verified.
- The default SwiftData store's exact shipping URL/name and behavior under a module/type move were not tested; the architecture avoids relying on an in-place move.
- Developer Portal, App Store Connect, CloudKit Console, container-name availability, production schema, provisioning profiles, and team roles were not accessible from the repository.
- Current customer OS/device distribution, pricing/universal-purchase intent, and desired iPad availability were not available.
- `CKSyncEngine` and SwiftData behavior must be proven with the shipping SDK and physical devices. Documentation establishes intended behavior, not correctness of Tildone's future integration.
