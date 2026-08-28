# AGENTS.md

## Scope of this guide

This file guides AI-assisted work on the Tildone macOS app, iPhone companion, shared local store, and Development-only CloudKit transport. It reflects the post-Stage-12C architecture while retaining released macOS 1.6.0 (build 24) compatibility. Keep statements labelled **Unresolved** or **Uncertain** as decisions, not requirements.

Before changing code, inspect the working tree. This repository may contain in-progress Xcode or asset changes; preserve unrelated work. When asked to commit, commit all uncommitted changes separately, with one well-named commit per feature or user request.

Every chat/task that adds or changes user-visible text must complete its localization before handoff: update `Tildone/Localizable.xcstrings` with the English source and translated Spanish, French, and Simplified Chinese entries. Do this even when Xcode has automatically extracted the English key, and include tooltips, accessibility labels, menus, alerts, placeholders, and other UI copy.

## Shared persistence invariants

- Never enable automatic SwiftData CloudKit mirroring for the shared store; every `ModelConfiguration` must explicitly use `cloudKitDatabase: .none`.
- Never open the released Mac legacy store through the shared `TildonePersistence` schema or migrate it in place.
- Never mutate, delete, rename, relocate, compact, or replace the released Mac legacy store during migration.
- A migrated shared store is not activation-eligible until it has been closed, reopened independently, and fully verified against the same source fingerprint.
- Automated tests and developer tools must use explicit fixture/source paths and must never default to a live legacy store.
- Retain legacy identity mappings, source fingerprint evidence, and the legacy source through the approved rollback/cloud-seeding safety window.
- Views use domain snapshots and repository operations, never shared stored-model objects or `ModelContext`.
- Every shared content mutation must atomically save transport-neutral outbound-work evidence in the same local transaction.
- The Mac process chooses its store once in `MacSharedStoreBootstrapper`: an existing destination must be activated, and a legacy source must first complete Stage 6 verification before activation. Do not reintroduce mixed legacy/shared windows.
- XCTest-hosted Mac app launches must use the in-memory shared repository; test setup must not inspect, open, or migrate a live legacy store.
- Shared user content sync uses `CKSyncEngine`, the private database of `iCloud.studio.cuatro.tildone`, and the `TildoneUserData` custom zone. Do not add public-database content or speculative record types.
- A durable outbox mutation is acknowledged only after CloudKit confirms that exact save; remote delivery must remain deterministic and idempotent through the domain merge layer.
- Never expose or reuse one confirmed iCloud account's cached workspace for another account. Confirmed sign-out, account switch, and custom-zone reset are safety boundaries that freeze the current sync session.
- Never auto-upload a local-only workspace or auto-reseed a deleted custom zone. Both operations require an explicit approved recovery/adoption policy.
- Keep titles and task text out of record names, logs, diagnostics, sync status, and notification payloads.
- Debug transport starts automatically outside tests. XCTest/UI-test launches are transport-off, and both macOS and iOS Release builds are explicitly transport-off until a later authorized stage. Workspace selection and local persistence must not be changed merely to pause transport.
- Active/paused transport intent is an installation-local preference keyed by the opaque account workspace UUID. Pausing retains that account repository, outbox, tombstones, and serialized engine state and performs no CloudKit send/fetch; resuming revalidates the account before reconstructing the coordinator and draining durable work.
- The Development contract is exactly `TDNote` V1/V2, `TDTask` V1/V2, and advisory `TDClient` V1 in the private custom zone. Reconcile field changes with `docs/development-cloudkit-contract-manifest.md` and its source generator/tests.
- V2-to-V3 note-color backfill authority is fixed: an existing explicit V2 color wins; otherwise the legacy Mac per-note/global color wins over platform-default backfill, and implicit V1 yellow is lowest. Preserve the reserved migration-stamp encoding and atomic outbox write.
- Production CloudKit inspection, schema deployment, entitlements, provisioning, records, zones, signing, archives, uploads, TestFlight, and App Store actions require separate explicit authorization. Development/local evidence never proves Production behavior.

## Product overview and principles

Tildone is a lightweight sticky task-list app. On macOS, each `TodoList` is a separate desktop note window. Pending work stays visible; completing every task starts a calm 20-second fade, after which the note and its tasks are deleted. The product reference is [Tildone — Sticky To-Dos on the App Store](https://apps.apple.com/es/app/tildone-sticky-to-dos/id6473126292).

Protect these principles in both apps:

- Simplicity: fast capture, few concepts, and no project-management complexity by default.
- Low distraction: quiet visuals, limited chrome, and no unnecessary alerts, badges, onboarding, or engagement mechanisms.
- Visibility of pending work: incomplete tasks should be easy to rediscover without users maintaining a separate organizational system.
- Completion should reduce clutter: completed notes leave the active workspace, with a short opportunity to cancel accidental completion.
- Native platform behavior: retain the unusual desktop-sticky behavior on macOS, but use iPhone navigation, controls, touch targets, lifecycle, and accessibility conventions on iOS.
- Privacy: the App Store listing says “Data Not Collected.” Any sync, analytics, crash reporting, account, or network feature must be evaluated against that promise before shipping.

Do not turn the iPhone app into a direct copy of floating macOS windows. Preserve notes, ordered tasks, completion, fast capture, and calmness; redesign window position, minimization, foreground level, desktop arrangement, hover, and keyboard-only interactions for iPhone.

## Repository map

- `Tildone.xcodeproj/`: Xcode project and tracked shared `Tildone` and `Tildone iOS` schemes.
- `Tildone.xcodeproj/project.pbxproj`: macOS and iOS app, unit-test, and UI-test targets; deployment and signing settings live here.
- `Tildone/App/`: lifecycle, scene, and non-view presentation state grouped into `Lifecycle/`, `Scenes/`, and `Presentation/`.
- `Tildone/Store/`: process-wide shared store plus bootstrap, location, resolution, and sync collaborators grouped by subject.
- `Tildone/Views/App/`: app-level SwiftUI/AppKit views grouped into coordinator, Focus help, note resolution, and sync status.
- `Tildone/Views/Note/`: note UI and supporting behavior grouped into core, completion, tasks, title-bar, and window concerns.
- `Tildone/Models/`:
  - `Todo.swift`: SwiftData task model and ordering/backward-compatibility helpers.
  - `TodoList.swift`: SwiftData note model, relationships, computed lifecycle state, and task/list mutation methods.
  - `FocusFilter.swift`: macOS Focus Filter `AppIntent`.
  - `Constants.swift`: window IDs, AppKit key codes, layout-related constants, and the fade duration.
- `Tildone/Views/`:
  - `Desktop.swift`: root coordinator for shared snapshots, manually created note windows, focus, cleanup, positioning, and arrangement.
  - `Note/`: note/task editing UI plus focused files for actions, content, focus-safe AppKit text editing, completion/fade, minimization, title-bar controls, task reordering, and SwiftUI-to-window bridging.
  - `Settings.swift`: settings UI, preference enums/keys, previews, and legacy preference conversion support.
  - `About.swift`: fixed-size About scene.
- `Tildone/Views/Common/`:
  - `Styler.swift`: note geometry, colors, custom AppKit window styling/blur, window buttons, and text-field behavior.
  - `Checkbox.swift`: custom circular checkbox.
  - `Launcher+Toggle.swift`: settings control for launch at login.
  - `View+Util.swift`: conditional SwiftUI modifier helper.
- `Tildone/Services/`:
  - `Copier.swift`: AppKit pasteboard copy/paste behavior for tasks and lists.
  - `Launcher.swift`: `SMAppService.mainApp` registration.
  - `UpdateChecker.swift`: StoreKit app-version check and locally generated “what’s new” system note.
- `Tildone/Localizable.xcstrings`: English source strings and Spanish, French, and Simplified Chinese localizations.
- `Tildone/Assets.xcassets`, `Tildone/TildoneIcon.icon`: runtime artwork and icon sources.
- `Tildone/Preview Content/`: preview assets and in-memory model mocks. `Mocks.swift` is currently included in the app target, not a separate preview-only module.
- `Tildone/Tildone.entitlements`, `Tildone/Info.plist`: sandbox/capability and icon metadata.
- `TildoneTests/`, `TildoneUITests/`, `TildoneiOSTests/`, `TildoneiOSUITests/`: hosted/unit and isolated UI coverage for the two platform adapters.
- `README.md`: brief product and installation description.
- `LICENSE`: GNU General Public License version 3; consider its distribution obligations when adding or extracting shared components.

`Packages/TildoneCore` provides the implemented `TildoneDomain`, `TildonePersistence`, and `TildoneSync` products plus the source-derived Development contract generator. `TildoneiOS` is a separate native companion target and must not receive Mac source files.

## Architecture and file organization

- Preserve the existing directory hierarchy and architectural boundaries.
- Keep one top-level named type per Swift file. Use `Type+Concern.swift` for focused extensions.
- Place SwiftUI `View`, `NSViewRepresentable`, `ViewModifier`, `ButtonStyle`, and AppKit view subclasses under `Tildone/Views/`.
- Group view files by feature and subject. Do not place dozens of files directly in a first-level folder.
- Keep application lifecycle, presentation state, and scenes under the corresponding `Tildone/App/` subfolders.
- Keep shared-store code grouped under `Tildone/Store/Bootstrap`, `Location`, `Resolution`, and `Sync`.
- Before introducing a new folder or moving code across architectural boundaries, inspect the existing structure and follow the closest established pattern.
- Keep filesystem folders and Xcode project groups synchronized.
- Update tests and documentation containing source-file paths after moving files.
- Do not consolidate unrelated types into large files for convenience.

## Project and platform facts

- Implementation language: Swift 5 language mode.
- UI: SwiftUI with substantial AppKit interop.
- Persistence: SwiftData.
- Other Apple frameworks: AppIntents, StoreKit, ServiceManagement, Foundation, and AppKit.
- macOS deployment target: macOS 14.0 in project and target configurations, matching the App Store listing.
- Targets: `Tildone`, `TildoneTests`, and `TildoneUITests` for macOS; separate `TildoneiOS`, `TildoneiOSTests`, and `TildoneiOSUITests` targets for iOS.
- Bundle ID: `studio.cuatro.tildone`.
- Version in the project: marketing version 1.6.0, build 24.
- Signing: automatic signing with team `F6HFAVTS49`; hardened runtime enabled.
- External dependencies: none. Do not add one when an Apple framework or small local implementation suffices; any dependency is a deliberate product/maintenance decision.
- Future iOS minimum version: **Unresolved.** Do not infer it from the macOS 14 minimum.

## Current architecture

The Mac app remains a view-driven SwiftUI/AppKit utility, but shared content is now behind the domain and repository boundary.

- `TildoneApp` waits for `MacSharedStoreBootstrapper`, which either opens an activated shared store or runs Stage 6 migration and atomically activates the independently verified destination before `Desktop` exists.
- `MacSharedStore` is the only Mac presentation adapter for `TildoneRepository`. It publishes immutable `MacNoteSnapshot` values and translates UI CRUD requests into domain/repository operations.
- `Desktop` reconciles snapshot IDs with manual `NSWindow` instances. `Note` receives a note ID plus the adapter, never a legacy/shared SwiftData model or `ModelContext`.
- For each note, `Desktop.openWindow(for:)` creates an `NSWindow`, hosts `Note` in `NSHostingView`, configures window style/level, and retains the released creation-date autosave key for migrated notes.
- View-local state (`@State`, `@FocusState`), preferences (`@AppStorage`), an app-level `Binding<NoteID?>`, AppKit notifications, and `NotificationCenter` remain the macOS presentation state system.
- Menu commands in `TildoneApp` publish global notifications such as `.new`, `.close`, `.copy`, `.arrange`, `.minimizeAll`, and `.bringAllUp`. `Desktop` and each `Note` subscribe and filter where needed.
- `foregroundList` and `foregroundWindow` decide which note menu commands address. Window titles are used as list identity; a leading `_` encodes minimized state.

This architecture is effective for a small AppKit-backed desktop utility but is not a cross-platform architecture. Do not add iOS conditionals throughout `Desktop`, `Note`, or `Styler`; first separate portable data/operations from platform coordinators and views.

## Domain model and persistence

### `TodoList`

`TodoList` is the persisted note/list entity:

- `created: Date`: required creation timestamp; currently also used as practical identity through `hash` (`created.ISO8601Format()`).
- `topic: String?`: optional note title.
- `systemURL: URL?` and `systemContent: String?`: optional release-note payload. A non-nil `systemContent` makes `isSystemList` true.
- `items: [Todo]`: inverse relationship to `Todo.list`.
- `isEmpty`: no tasks and a nil topic. An empty string is normalized to nil by the view.
- `isComplete`: at least one task and no incomplete tasks.
- `isDeletable`: complete or empty.

`TodoList.createNewTask`, `delete`, and `clean` reach through SwiftData’s injected `modelContext` and save immediately. `remove` updates the relationship array and reindexes remaining tasks.

### `Todo`

`Todo` is a persisted task:

- `what: String`: task text.
- `created: Date`: creation timestamp and current SwiftUI/focus identity.
- `index: Int?`: display order; optional for compatibility with data written by early versions.
- `done: Date?`: completion timestamp; nil means pending.
- `list: TodoList?`: owning list relationship.

`Todo.setDone` writes/removes the completion timestamp. `Array<Todo>.sorted()` first stabilizes by creation date, then orders by `index`, and assigns indexes to legacy unindexed tasks as a side effect.

### Storage and deletion behavior

- `ModelConfiguration(schema:isStoredInMemoryOnly: false)` uses SwiftData’s default local store. No explicit store URL, App Group, or CloudKit database is configured.
- Empty task rows are cleaned when a note loses focus and at app termination.
- A completed list starts fading after one second, fades for `Timeout.noteFadeOutSeconds` (20 seconds), then `TodoList.delete()` permanently deletes the list and children.
- Completing a note can be canceled during the fade. A note already complete when opened does not restart the fade, but complete/empty notes are deleted when the app terminates.
- There is no archive, trash, undo manager, tombstone, or deletion history.
- Errors during many normal saves call `fatalError`; update-note creation and preview saves only log errors.

### Existing migration strategy

There is no `VersionedSchema`, `SchemaMigrationPlan`, or explicit persistent-store migration. Current compatibility is ad hoc:

- `Todo.index` remains optional, and `indexIfUnindexed()` fills missing values for stores created by early versions.
- `Note.convertLegacyFontSizeSettingIfNeeded()` converts the old enum-like `fontSize` `UserDefaults` value to a point size.
- `NoteColor.current()` converts the retired translucent color raw value (`6`) into yellow plus zero background opacity.

Treat model changes as migration-sensitive. Before shipping a changed model, test opening a store produced by released version 1.6.0 and decide whether SwiftData lightweight migration is sufficient. Never make an optional persisted property required, change enum raw-value meaning, or change relationship/delete semantics without a migration plan and fixtures.

## Important user workflows

### Launch and restore

1. The main scene bootstraps the shared local-only repository and displays `Desktop` only after it is active; a legacy source is copied/verified by Stage 6 before cutover.
2. `Desktop` opens one manual note window for every persisted list; if the store is empty, it creates one empty note.
3. AppKit frame autosaving restores each non-new note’s size and position using its creation timestamp.
4. `UpdateChecker` may create a green system note after an App Store update, based on `AppTransaction.shared` and `knownAppVersion` in `UserDefaults`.

### Capture and editing

- A new empty note focuses its topic. Existing titled notes focus the new-task field.
- Return or Tab commits new task text. Arrow keys navigate topic, pending tasks, and the new-task field.
- Return within an existing task may insert before/after it or move focus, depending on cursor position.
- Delete/backspace removes an empty pending row. Editing and task creation capitalize the first character.
- Copy can target the focused task or produce an HTML list; multiline paste fills the current task and inserts following lines as new tasks.

### Completion and cleanup

- Checking the final pending task shows the Done overlay, demotes the window from floating, and starts the delayed fade.
- Cancel resets fade progress and keeps the completed tasks available for unchecking.
- Closing via the close button or Command-W is allowed only for empty or complete notes. Pending notes are deliberately persistent.

### Minimize and arrange

- The standard minimize button is intercepted. It shrinks the same window to a 96×66 progress gauge rather than using macOS Dock minimization.
- Clicking a gauge restores its previous in-memory frame. “Minimize All” and “Bring All Up” publish global notifications.
- “Arrange Notes” groups windows by screen and lays them out horizontally or vertically from the selected corner with configured margins and spacing.
- Minimized state and the pre-minimize frame are not persisted across launch.

### Focus Filter

`FocusFilter` exposes “Task text blurred” and “Note may stay in the background.” Applying it sends `.visibility`: notes blur/disable content and/or move from `.floating` to `.normal`. Preserve privacy and reduced-distraction semantics when changing this path.

## macOS-specific implementation details

These are intentional macOS behaviors or AppKit implementation mechanisms, not portable product domain:

- Manual `NSWindow` creation, `NSHostingView`, window levels, shadows, opacity, titlebar transparency, traffic-light restyling, frame autosave, multiple screens, and visible-frame clamping (`Desktop`, `Styler`).
- One window per list and the invisible root coordinator window.
- Foreground-note tracking through `NSWindow.didBecomeKeyNotification`.
- Window title strings as runtime identity and `_` as minimized-state encoding.
- `NSEvent` local key monitor and numeric AppKit key codes in `Keyboard`.
- `NSTextField`/`NSTextView` traversal to place the insertion point, plus the global `NSTextField.focusRingType` override.
- `NSPasteboard` clipboard integration.
- `SMAppService.mainApp` launch-at-login behavior.
- `NSVisualEffectView` note blur/tint and `NSColor` palette.
- Disabling automatic window tabbing and the fullscreen menu item.
- Menu command layout and macOS shortcuts.
- Focus Filter window-level behavior. The conceptual privacy setting may be portable, but this AppKit response is not.

Changes in these areas require real macOS testing with multiple notes, multiple displays if relevant, light/dark appearance, app relaunch, and keyboard-only operation.

## Shared-code opportunities for macOS and iOS

Aim for a small shared domain/persistence layer, not shared screens by default.

Good candidates after refactoring:

- `Todo` and `TodoList` persisted fields and relationships, subject to the identity/sync redesign below.
- Pure computed rules for empty, complete, pending count, progress, deletability, and task ordering.
- Task text normalization, insertion, removal, and index normalization, once they no longer save through an implicitly injected `modelContext`.
- Completion transition policy: when a list becomes complete, the cancellation/grace period, and what “removed from active view” means. The timer animation itself remains platform UI.
- Shared SwiftData schema/migration definitions if SwiftData is selected for both apps.
- Localized domain strings and supported locale catalog, with platform-specific strings separated as needed.
- Preview/test fixtures currently in `Preview Content/Mocks.swift` and `SampleNoteData`, after moving them out of production UI files.
- Color tokens and preference value types where the semantics match; platform color conversion (`NSColor` vs `UIColor`/`Color`) stays in platform code.
- Sync metadata, conflict-resolution rules, and a persistence/sync service protocol once those are designed.

Do not mark existing files as members of an iOS target just because they import SwiftUI. `TodoList.swift` currently contains model-context persistence, `Todo.swift` has a mutating sort helper, and most other source files import or rely on macOS-only APIs.

## Platform-boundary rules

- Shared code must import only frameworks available to both chosen deployment targets. Keep AppKit, ServiceManagement, macOS window APIs, and macOS key codes out of it.
- Put `Desktop`, macOS `Note`, window styling/accessors, macOS commands, Focus Filter window handling, launch-at-login, and pasteboard adapters in the macOS target.
- Give iOS its own app entry point, scene/navigation structure, note/list views, clipboard adapter, settings surface, and lifecycle handling.
- Keep persistence operations behind explicit domain/store APIs before adding sync. Views should request operations; they should not each decide save/delete/conflict behavior.
- Do not use notification names as the shared action architecture. Typed operations/state are safer across scenes and devices.
- Do not share window geometry or minimized state to iPhone. If these remain persisted, classify them as Mac-local presentation metadata.
- Do not sync `systemContent` update notes unless there is an explicit product reason. They are installation/version UI, not user data.
- Preferences need an explicit classification: device-local (Mac arrangement, launch at login, window opacity), platform-local, or user-synced (possibly note color/text size). Do not automatically sync the entire `UserDefaults` set.
- Use conditional compilation only at narrow adapters. If a shared type accumulates many `#if os(macOS)` branches, split it.

## Intended direction for the iPhone companion app

The repository does not yet specify the iPhone feature set. The safe initial direction is a companion focused on the same user data and fast task interaction, with an iPhone-native presentation.

Preserve:

- Notes as lightweight titled task lists.
- Pending tasks as the primary information.
- Very fast note/task capture and completion.
- Stable task ordering and a visible, reversible completion transition.
- A calm, uncluttered visual language and optional note color identity.
- Privacy and offline usefulness.

Redesign for iPhone:

- Present notes in a native collection/list or similarly touch-friendly overview; there is no desktop or floating-window analogue.
- Open a note in a native detail/editing flow rather than embedding a scaled macOS sticky window.
- Replace hover, traffic lights, window dragging/resizing, foreground level, and desktop arrangement with touch/navigation conventions.
- Replace the tiny 14-point custom checkbox geometry with accessible touch targets while retaining visual lightness.
- Use Dynamic Type, safe areas, software-keyboard behavior, VoiceOver, swipe/context actions only where discoverable, and standard navigation restoration.
- Decide whether a widget, quick action, App Intent, or notification is the iPhone equivalent of persistent visibility; none is currently required by the repository.
- Decide how completed notes leave the iPhone active view. A 20-second window-opacity fade cannot be transferred literally when a detail screen is backgrounded or dismissed.

The iPhone companion now supports full note/task CRUD, reordering, completion, offline edits, and account-scoped synchronization. Widgets, shortcuts/App Intents, archive/history, and native iPad/visionOS scope remain unresolved; do not implement them by assumption.

## Data synchronization considerations

Synchronization is implemented as a local-first SwiftData replica plus a durable transport-neutral outbox and `CKSyncEngine`; automatic SwiftData CloudKit mirroring remains forbidden. Stable UUIDs, field-level Lamport versions, fractional order tokens, lifecycle tombstones, account-keyed workspaces, custom-zone reset latching, and remote Mac/iPhone presentation refresh are existing contracts.

Current Development-only constraints:

1. Debug transport is automatic outside test processes. Release transport is off on both platforms; enabling shipping transport is not authorized by source entitlement presence.
2. Mac local-only adoption and note-location changes are explicit and confirmation-gated. An empty account can receive a retained-source copy. When both locations contain notes, the user may combine them through the established stable-ID field merge, show iCloud notes, or keep showing Mac notes; all three retain both repositories. The account is revalidated before any account operation, and no choice may auto-delete, reset, or overwrite either repository.
3. Transport pause retains the selected account workspace. The compact Mac status surface exposes active, paused, and attention states without user content. Note-location review and confirmation replace the status window's content in place rather than opening a second window. When the user explicitly chooses Mac notes, each note shows a neutral slashed-cloud button beside the color picker; it states that the note is only on this Mac and opens the existing note-location choices. This indicator is not used for transport pause. The menu-bar item retains the Tildone icon and overlays an attention badge when needed. Zone-reset and incompatible-data states provide preservation guidance only; no automatic or owner-approved destructive recovery action is defined.
4. Release/update system notes, window geometry, minimized state, opacity, arrangement, launch-at-login, and Mac Focus behavior remain installation-local.
5. Titles/tasks are private user content. They may enter the approved private CloudKit fields only, never record names, diagnostics, status, notifications, device-registration records, or logs.
6. The exact Development schema is generated in `docs/development-cloudkit-contract-manifest.md`. Any encoder/decoder field change must update the manifest generator and exact-key regression test together.

## Settings and preferences

Current `UserDefaults`/`@AppStorage` keys are compatibility contracts:

- `fontSize`: continuous point size; legacy small raw values are converted on note appearance.
- `taskLineTruncation`: `TaskLineTruncation` raw value (`single = 1`, `multiple = 2`).
- `selectedArrangementCorner`: `ArrangementCorner` raw value.
- `selectedArrangementAlignment`: `ArrangementAlignment` raw value.
- `selectedArrangementCornerMargin`: `ArrangementSpacing` raw value.
- `selectedArrangementSpacing`: `ArrangementSpacing` raw value.
- `noteColor`: legacy/global fallback used to seed shared per-note color; legacy value `6` has migration meaning. Per-note keys remain migration evidence.
- `noteBackgroundOpacity`: global background opacity, default 0.6.
- `noteWindowOpacity.<note-id>`: installation-local whole-window opacity set with Command–wheel; default 1.0.
- `noteUserDraggedPosition.<note-id>`: installation-local last manually dragged Mac window origin; wheel convergence and arrangement never overwrite it.
- `noteCornerWheelPosition.<note-id>`: installation-local marker that lets Command–Control–wheel restore a wheel-moved note to its last manual origin after relaunch.
- `knownAppVersion`: last App Store version for which the local update note was generated.
- `NSFullScreenMenuItemEverywhere`: set false during desktop setup.
- `syncTransportState.<account-workspace-uuid>`: `active` or `paused`; missing state preserves the Debug default and malformed state fails safe to paused.
- `localWorkspaceAdoptionFingerprint.<account-workspace-uuid>`: SHA-256 of the last explicitly copied local workspace snapshot; this is adoption evidence, not content or sync-engine state.
- `noteLocationChoice.<account-workspace-uuid>`: `thisMac` or `iCloud`; the explicit presentation choice is isolated per account and a missing or malformed value leaves an unadopted local workspace selected for review.

Launch at login comes from `SMAppService` state, not `UserDefaults`. Preserve raw values and storage keys unless shipping a tested conversion. Note that Settings currently labels two sections “General”; treat whether that is intentional as uncertain.

## Coding conventions

Follow the codebase’s existing Swift style unless a scoped refactor establishes a new convention:

- Four-space indentation and opening braces on the declaration line.
- Organize larger files with `// MARK:` sections and `private extension` blocks.
- Use descriptive lowerCamelCase methods/properties and UpperCamelCase types.
- Keep storage keys and notification names centralized on their owning type.
- Use typed SwiftUI property wrappers (`@Query`, `@AppStorage`, `@FocusState`) deliberately; avoid adding duplicate sources of truth.
- Capitalization and ordering rules belong in domain operations, not duplicated in new views.
- Localize user-facing text. Use string-catalog-compatible APIs (`Text` literals, `String(localized:)`, `LocalizedStringResource`) and provide translator context for ambiguous strings.
- Do not add forced unwraps or new `fatalError` paths for recoverable persistence/sync failures. Existing ones are technical debt, not a preferred error-handling convention.
- Avoid using creation timestamps, display strings, or window titles as new entity identity.
- Keep new reusable logic pure and unit-testable. Inject storage/clock/sync dependencies where deterministic behavior matters.
- No SwiftLint or SwiftFormat configuration exists. Do not claim those tools are required, and do not reformat unrelated files.

## UI and UX conventions

- Pending notes stay visible and cannot be casually closed; this is central macOS product behavior.
- Retain immediate editing and keyboard efficiency on macOS. Verify topic/new-task initial focus, Return/Tab insertion, arrow navigation, delete/backspace, Command-W, copy/paste, and menu shortcuts after relevant changes.
- Keep animation calm and functional. Completion must retain a clear way to cancel before destructive removal.
- Note windows have minimal chrome, translucent colored material, fixed minimum size (180×240), default size (250×300), and a compact progress form (96×66).
- Normal note color and opacity are global settings; system release notes remain green.
- The note content forces a light SwiftUI color scheme in `ScrollFrame`, while foreground colors also inspect the environment color scheme/opacity. Appearance changes need visual testing because this interaction is non-obvious.
- Do not transfer exact pixel sizes or macOS control density to iPhone. Use Apple-platform standard touch targets and Dynamic Type.
- Avoid adding hierarchy, metadata, or settings that compete with task text without a clear product need.

## Localization and accessibility requirements

### Localization

- Source language is English. Maintain English, Spanish (`es`), French (`fr`), and Simplified Chinese (`zh-Hans`) in `Localizable.xcstrings`.
- Most English source values are implicit while the three translations are explicit; do not mistake the missing `en` localization object for an untranslated key.
- Preserve interpolation placeholders such as `Updated to v%@` and numeric placeholders.
- Focus Filter parameter titles/descriptions/display representations, menus, Settings, overlays, gauges, system notes, links, and iOS-only strings all require localization.
- `NoteColor.label` returns English strings used by Settings help and currently has no catalog entries for the color names. Treat this as an existing localization gap.
- `UpdateChecker` hard-codes release contents for version 1.6.0. Future release notes need a deliberate update/versioning process.

### Accessibility

The sync status surfaces and some controls have explicit accessibility modifiers, but coverage remains incomplete. Do not interpret native SwiftUI usage as proof of complete accessibility.

- Give the custom `Checkbox` an accessible label/value/trait and a sufficiently large interactive region; disabled placeholder checkboxes should not create confusing VoiceOver stops.
- Ensure minimized progress communicates note topic, pending count, and restoration action without relying on the gauge or color alone.
- Preserve full keyboard access and visible, native focus behavior on macOS. The global removal of `NSTextField` focus rings is a special-risk area.
- Completion, blur, disabled editing, opacity, strikethrough, and colors must not be the only way state is communicated.
- On iPhone, support Dynamic Type, VoiceOver, Switch Control, Reduce Motion, sufficient contrast across every color/opacity, and comfortable touch targets from the first implementation.
- Test localized text expansion and larger accessibility sizes; do not lock the iPhone UI to macOS note dimensions.

## Entitlements, sandbox, signing, and privacy

`Tildone/Tildone.entitlements` currently declares:

- App Sandbox enabled.
- User-selected files read-only.
- Outbound network client access.
- Development push notifications (`com.apple.developer.aps-environment = development`).
- CloudKit service and `iCloud.studio.cuatro.tildone` container identifiers.
- The Development CloudKit container environment.

`TildoneiOS/TildoneiOS.entitlements` declares the same Development CloudKit container and Development APNs environment. The iPhone plist declares `remote-notification`. These are Development source capabilities, not evidence of effective Production signing or runtime success.

Do not remove or expand entitlements casually: compare Debug/Release signing, App Store provisioning, Focus Filters, launch at login, StoreKit receipts, and the intended sync design. A future iOS app needs its own bundle ID and target entitlements. If sharing a CloudKit container, explicitly configure both targets and production schema/deployment.

No privacy manifest is present, and no third-party SDK is linked. User task text should remain out of diagnostics and network payloads except the explicitly chosen private sync system. Several product/README links use plain HTTP; review transport/security before relying on them for new functionality.

## Testing strategy

Current automated coverage includes the complete `TildoneCore` domain/persistence/sync suite, real released/V1/V2 store fixtures, Mac and iPhone hosted/unit tests, and isolated Mac/iPhone UI smoke tests. Preserve exact fixture hashes and distinguish local/simulator evidence from signed Development and physical-device evidence.

Continue prioritizing:

- Model completeness/emptiness/deletability and pending progress.
- Stable ordering, insertion at boundaries, reindexing, and legacy nil-index conversion.
- Completion/uncompletion and deletion grace policy with an injected clock.
- Preference migrations for legacy font size and translucent color.
- Store migration from released schemas and stable-ID backfill.
- Sync conflicts, offline changes, deletion/tombstones, duplicate prevention, and deterministic ordering.
- Mac UI smoke tests for window restoration, new note focus, close restrictions, minimize/restore, fade cancellation, Focus Filter, and multi-display arrangement.
- iPhone UI tests for creation/editing/completion, offline launch, navigation restoration, Dynamic Type, and accessibility.

Use in-memory `ModelConfiguration` for isolated model tests. For migration tests, retain versioned on-disk fixtures rather than creating both old and new stores with the current model.

## Build and test commands

Run commands from the repository root (the directory containing `Tildone.xcodeproj`). The verified local toolchain during this analysis was Xcode 26.4.1; the project was originally created with Xcode 15-era settings, so do not silently raise deployment or project format versions.

Inspect targets and schemes:

```sh
xcodebuild -project Tildone.xcodeproj -list
```

Build the macOS app without requiring signing, keeping Derived Data outside the repository:

```sh
xcodebuild -project Tildone.xcodeproj -scheme Tildone -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/TildoneDerivedData CODE_SIGNING_ALLOWED=NO build
```

Run the shared scheme’s unit and UI tests on the current Mac:

```sh
xcodebuild -project Tildone.xcodeproj -scheme Tildone -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/TildoneDerivedData CODE_SIGNING_ALLOWED=NO test
```

Assert that both tracked app schemes use Debug launch/Release archive configuration and that the Release bundle IDs, entitlements, deployment targets, and compilation conditions remain deterministic:

```sh
./Scripts/verify-release-configuration.sh
```

Run the build command on the current tree before claiming application compilation. Stage 12C's shared Debug/Release package suites, four fresh generic Debug/Release platform builds, and Mac/iPhone hosted tests passed on 2026-08-09. These local results are not signed physical-device or live CloudKit evidence. Existing compiler warnings include explicit specialization of `getNestedSubviews()` in `Note.swift` and two never-mutated variables in `Desktop.clampedOrigin`; do not hide new warnings among them.

There is no repository-defined lint or formatting command. The repository has deterministic Release configuration assertions but no authorized archive/upload command. The shared schemes support Archive in Release configuration, and the project uses automatic signing, but App Store archive/upload steps and release-note/version policy are **Unresolved**; do not invent or automate them without owner confirmation.

The iOS scheme is `Tildone iOS`. Use an available simulator destination for hosted/unit/UI tests and `generic/platform=iOS` for unsigned Debug/Release compilation. Record the exact resolved simulator/device and command in the stage evidence.

## Validation checklist for changes

Apply the subset relevant to the change; sync/persistence/window changes require the broader checks.

- Inspect `git diff` and preserve unrelated work, especially `.pbxproj` and icon changes.
- Build the affected target(s) with no new compiler warnings.
- Run meaningful unit tests; do not count placeholder tests as coverage.
- Launch with an empty store and with realistic existing data.
- For schema/preference changes, verify migration from released data and document rollback/data-loss risks.
- Create multiple notes; edit topics/tasks; insert and delete empty tasks; copy/paste multiple lines; complete, cancel fade, uncheck, and relaunch.
- Verify a pending note cannot be discarded while empty/complete notes can be closed.
- Verify minimize/restore, Minimize All/Bring All Up, arrangement preferences, relaunch geometry, and screen-configuration changes.
- Check Focus Filter combinations: blur only, background only, both, and neither.
- Check light/dark appearance, all note colors, opacity extremes, font-size extremes, and single/multiline task wrapping.
- Check English, Spanish, French, and Simplified Chinese, including truncation/expansion.
- Check keyboard-only operation and VoiceOver; for iOS also check Dynamic Type, Reduce Motion, and touch targets.
- Confirm no task/topic text is logged, collected, or sent beyond the approved sync boundary.
- Recheck entitlements, privacy disclosures, and signing when adding capabilities or network behavior.
- For sync, test two devices, offline edits, simultaneous edits, deletion conflicts, iCloud unavailable/sign-out, interrupted migration, and remote insertion/deletion while the Mac app is open.
- Update this guide when targets, supported OS versions, build commands, migrations, capabilities, or architectural boundaries change.

## Files and areas requiring special care

- `Tildone.xcodeproj/project.pbxproj`: merge-prone and currently may carry user icon/project changes. Make minimal target-membership/build-setting edits and inspect the diff.
- `Tildone/Models/Todo.swift` and `TodoList.swift`: released store schema, ordering, relationship, and destructive deletion semantics.
- `Tildone/Store/`: activation safety, test-process isolation, snapshot refresh, insertion ordering, workspace policy, and every Mac repository operation.
- `Tildone/App/`: lifecycle, scene coordination, sync presentation state, and global menu/notification contract.
- `Tildone/Views/App/`: shared-store bootstrap presentation, recovery choices, and sync-status UI.
- `Tildone/Views/Desktop.swift`: manual window lifecycle, snapshot reconciliation, foreground selection, multi-display coordinates, and deletion on termination.
- `Tildone/Views/Note/`: repository requests plus keyboard monitoring, AppKit responder manipulation, completion timer, fade deletion, focus, and minimization. Small changes can affect several workflows.
- `Tildone/Views/Common/Styler.swift`: reaches into AppKit’s theme-frame subviews, retries background application asynchronously, globally overrides `NSTextField.focusRingType`, and restyles standard window buttons.
- `Tildone/Views/Note/Window/WindowAccessor.swift` and its AppKit attachment/action collaborators: bridge a SwiftUI note to its owning `NSWindow`; preserve deterministic reattachment and strong ownership of the standard-button action target across view/store refreshes.
- `Tildone/Views/Settings.swift`: owns preference raw values/migrations and contains app-like preview persistence code.
- `Tildone/Localizable.xcstrings`: generated/extracted state and manually maintained translations can be changed by Xcode; inspect diffs carefully.
- `Tildone/Tildone.entitlements`: contains apparently unused or incomplete capabilities; coordinate changes with provisioning and App Store configuration.
- `Tildone/Services/UpdateChecker.swift`: StoreKit verification, persistent version flag, version-specific localized content, and an HTTP release URL.

## Known technical debt and risks

- The released legacy models still use dates/indexes internally, but shared notes/tasks have stable UUIDs, versioned schemas, fractional order, tombstones, and frozen released/V1/V2 fixtures.
- Any action that recreates or reseeds a reset Production zone remains an unresolved policy decision. Stage 12C intentionally supplies preservation guidance, not that action.
- Production schema/signing/provisioning/privacy/distribution behavior is unverified and unauthorized.
- The legacy Mac view/model implementation still contains direct persistence and `fatalError` paths outside the shared repository boundary.
- `Note.swift` and `Desktop.swift` mix presentation, domain operations, persistence, timers, event routing, and AppKit lifecycle.
- Global stringly typed `NotificationCenter` events and window-title identity are fragile.
- Each `Note` installs a local key monitor without retaining/removing its monitor token, which may accumulate as windows are created.
- Foreground-list matching in `Desktop.handleFocus` compares against `lists.first` before other handling; this path deserves tests and review.
- The manual window array may diverge from model/query state, especially once remote changes exist.
- Window positioning mixes screen frame and visible frame logic; `randomPositionOnScreen()` can form invalid ranges on unusually small screens.
- Minimized state is encoded in a title prefix and its restoration frame exists only in view state.
- Accessibility is largely unimplemented for custom controls and visuals; focus rings are globally suppressed.
- Localization gaps include color help labels; the catalog and release-note content require manual care.
- App entitlements intentionally remain Development-only; effective Production capabilities have not been inspected or configured.
- Plain HTTP links remain in About, update notes, previews, and README.
- The app target includes preview mocks; there is no dedicated shared/test support module.
- There is no CI, linting, formatting, or authorized App Store release pipeline.
- Existing compiler warnings should be resolved rather than accepted as a growing baseline.

## Unresolved architectural and product questions

Do not answer these implicitly in implementation work:

- Is native iPad support intended beyond iPhone compatibility behavior?
- What final privacy disclosures/policy language are required for private CloudKit while retaining the account-free product model and current App Store claims?
- Should existing local Mac data automatically upload, and what recovery/rollback experience is required?
- What shipping UX authorizes local-only Mac adoption, and what operator/user flow handles a Production zone reset without automatic reseed?
- What explicit build/release control enables transport after Stage 12C while preserving the account workspace during containment?
- What is the iPhone mechanism for pending-task visibility: app overview, widget, Live Activity, notifications, App Intents, or a deliberately smaller first release?
- Should system release notes be stored in the same user-data model at all?
- Should shared code be a local Swift package/framework or shared target membership? Decide after the domain/store boundary and deployment targets are known.
- Which currently declared entitlements are genuinely required, and what is the intended signed release/archive process?

When a decision is made, capture it here and in tests before relying on it across both platforms.
