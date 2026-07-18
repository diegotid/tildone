# Stage 9: iPhone MVP

## Outcome

The iPhone scaffold is now a local-first SwiftUI companion for the shared Tildone workspace. It shows the current account's active notes, lets the user make and rename notes, and provides a native checklist editor for adding, editing, completing, deleting, and reordering tasks. The implementation uses the Stage 4–8 domain, repository, durable outbox, account-workspace, and `TildoneSync` boundaries directly; it introduces no iPhone-only data model or store.

SwiftData automatic CloudKit mirroring remains disabled: every shared `ModelConfiguration` continues to use `cloudKitDatabase: .none`. No production CloudKit schema was deployed.

## Navigation and interaction

- The root is a standard `NavigationStack` note list. It uses the repository's `visibleNotes()` order (last meaningful edit, descending), omits tombstones, has an explicit first-use empty state, and calls an untitled note **Untitled Note**.
- The toolbar creates a note and immediately navigates to its editor. Note rows use native swipe actions and a context menu for Rename and Delete; deleting a note has a confirmation dialog.
- A checklist has an inline title field, stable task rows, a persistent **New task** field, native edit-mode reordering, completion controls, and task deletion swipe actions. Return on the new-task field creates a nonempty task and leaves capture ready for the next one. Blank draft tasks are never written.
- Existing task text only commits when it is nonempty and changed. Focused task drafts are not replaced by incoming text; stable domain IDs keep unrelated remote changes from rebuilding another row's editor.
- Task completion controls have 44-point tap targets, useful VoiceOver labels/actions, and `Move Up`/`Move Down` accessibility actions. The UI uses semantic controls and multiline text fields so it participates in Dynamic Type rather than imposing a fixed layout.

## Composition and observation

`TildoneiOSApplicationModel` is the iPhone-only application/presentation boundary. It resolves the iCloud account, opens only the matching account-keyed `TildoneRepository`, publishes immutable `Note` snapshots, and calls repository operations for every mutation. Views do not access SwiftData models, `ModelContext`, `CKRecord`, or `CKSyncEngine`.

When the Debug sync flag is enabled, the model builds the existing `TildoneSyncCoordinator`, subscribes to its transport-neutral `SyncStatusModel`, and starts/resumes it on application activation. Local mutations reload from the repository immediately and then notify the coordinator; the durable outbox is already part of the repository transaction. A coordinator remote-change callback reloads snapshots, so fetched changes appear without duplicate rows. The status menu also provides **Sync Now** for an explicit immediate send/fetch checkpoint during development validation.

The iPhone target supplies `UIBackgroundModes` as a real plist array containing `remote-notification`. This is intentionally an explicit partial Info.plist rather than a scalar generated-plist build setting; the latter was omitted from the built product and caused CKSyncEngine to reject push-notification setup.

Confirmed sign-out and account changes stop the coordinator, discard the repository handle and all published note snapshots before showing the account-changed state. The subsequent launch resolves a new account workspace rather than reusing the prior cache.

## Account and sync states

The small toolbar status menu uses only `SyncStatus`. It presents plain language for disabled development sync, updating, local offline editing, transport attention (including malformed data, quota, permission, and service categories), no account, restrictions, temporary unavailability, adoption required, account changes, zone reset, incompatible data, and the pending local-change count where available. No CloudKit error code, record name, account identity, filesystem path, or user text is shown.

The iPhone does not open an account cache until a matching account identity is resolved. If the account is unavailable at launch it displays a safe status screen. Adoption remains an existing development-policy boundary: Stage 9 only explains that sync cannot continue; it does not invent or perform adoption.

## Tests

`TildoneiOSTests` adds deterministic in-memory coverage for:

- note ordering, untitled notes, create/rename/delete;
- task add/edit/complete/delete/reorder through repository commands;
- tombstone hiding and idempotent remote-style refreshes;
- local/offline mutations, account workspace invalidation, and status presentation.

The UI test launches an isolated in-memory workspace (`TILDONE_UI_TESTING=1`) and verifies the main empty state and create-note navigation without network or an Apple Account.

Validation performed through 2026-07-19:

- `swift test` in `Packages/TildoneCore`: 73 tests passed.
- Debug iPhone simulator `build-for-testing`, including the iPhone unit/UI test bundles: passed.
- The built product was inspected and contains `UIBackgroundModes = [remote-notification]`.
- `TildoneiOSTests` executed on an iPhone 17 Pro simulator: 6 tests passed.

## Manual Mac-to-iPhone validation

The following remains the development-container validation procedure:

1. Set `TILDONE_ENABLE_CLOUDKIT_SYNC=1` on both Debug schemes. Use the same development iCloud account on Mac and iPhone; use a physical iPhone for silent-push/background checks.
2. Create notes and tasks on Mac, then verify they appear in the iPhone list and editor.
3. Create/edit notes and tasks on iPhone, including completion, reordering, and deletion; verify the Mac converges.
4. Make offline edits on either device, terminate/relaunch, reconnect, and verify pending work converges without duplicates or deleted content returning.
5. Test sign-out/account switching, temporary service loss, zone-reset attention, and local-workspace adoption-required states. Confirm no previous-account data is shown.

No live development-container or physical-iPhone validation was performed in this environment.

### Development recovery

If a disposable **development** account workspace cannot open because its local sync envelope/outbox is invalid, the Mac Debug scheme supports one explicit recovery run. Set `TILDONE_RESET_DEVELOPMENT_ACCOUNT_WORKSPACE=CONFIRM_RESET`, launch Mac once, then remove that variable immediately. This removes only that resolved account's local replica/outbox directory; it never deletes the local-only Mac workspace, released legacy store, or any CloudKit zone/records. Add `TILDONE_ALLOW_LOCAL_WORKSPACE_ADOPTION=1` in that same one-time run only when reseeding from the local-only Mac workspace is intentionally approved.

Manual adoption testing exposed and fixed an outbox coalescing defect: when a rapid edit replaced an unsent successor of an older in-flight mutation, the older row could retain a dangling successor link. Both local and remote-normalization enqueue paths now retarget those ancestors to the replacement mutation. A deterministic adoption/in-flight/rapid-edit regression test covers the failure.

## Deferred polish

- There is no standalone Settings screen; immediate synchronization is available from the toolbar status menu.
- Draft task collision UX is intentionally conservative: focused local text is preserved rather than attempting an in-field conflict merge.
- iPad layout, search, widgets, sharing, richer task entry shortcuts, and a final user-facing local-workspace adoption/recovery policy remain out of scope.
