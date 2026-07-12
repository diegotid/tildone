# Architecture Decision Record (ADR): Repository Structure

- **Status:** Proposed
- **Date:** 2026-07-12
- **Decision owners:** Tildone product and engineering owner
- **Related document:** [Tildone for iPhone: Product and Technical Architecture](ios-companion-product-and-architecture.md)
- **Scope:** Repository, Xcode project, target, package, and platform-source boundaries for adding the iPhone app

## Context

Tildone is an existing shipping macOS application. The repository must evolve to add an iPhone app without treating the Mac implementation as disposable or turning the existing target into a conditional cross-platform target.

The repository was inspected before this decision was written. Its current structure is:

- One Xcode project: `Tildone.xcodeproj`.
- One shared scheme: `Tildone`.
- Three native targets, all for macOS:
  - `Tildone`
  - `TildoneTests`
  - `TildoneUITests`
- The app target uses macOS 14.0, Swift 5 language mode, automatic signing, team `F6HFAVTS49`, bundle ID `studio.cuatro.tildone`, and generated Info.plist settings.
- Source files use classic `PBXGroup` project groups and explicit file/build-phase entries. The project does not use file-system-synchronized root groups.
- There is no top-level `.xcworkspace`, Swift package manifest, package reference, shared framework, third-party dependency, iOS target, or CI workflow.
- `Tildone.xcodeproj/project.xcworkspace` exists because Xcode projects have an internal workspace. It is not a separate repository-level workspace or a reason to introduce one.
- The existing `Tildone/` source directory is the Mac application. Its entry point, views, services, settings, resources, entitlements, previews, and tests already belong to the shipping target.
- Much of the Mac UI and application lifecycle imports or relies on AppKit. The existing SwiftData `Todo` and `TodoList` types also belong to the released Mac persistent-store model.
- The working tree currently contains unrelated staged icon/project changes. Repository restructuring must preserve them and avoid rewriting the project file wholesale.

The new iPhone application needs native iOS UI, its own lifecycle, assets, entitlements, tests, and signing configuration. In the longer term, both apps need shared domain, persistence, and synchronization code. Existing Mac data must remain migratable.

## Decision

Keep one Xcode project, add separate iOS application and test targets to it, and add one repository-local Swift package named `TildoneCore` for cross-platform non-UI code. Do not create a top-level Xcode workspace at this stage.

Keep the existing Mac target and `Tildone/` directory names unchanged. Put all new iOS application code in a new `TildoneiOS/` directory and target. Platform-specific UI remains in its owning app target; it is not placed in the shared package.

The intended top-level structure is:

```text
tildone/
├── README.md
├── LICENSE
├── Tildone.xcodeproj/              Existing project; remains the entry point
├── Tildone/                        Existing macOS app; do not rename in this work
├── TildoneTests/                   Existing macOS unit tests
├── TildoneUITests/                 Existing macOS UI tests
├── TildoneiOS/                     New iOS app source and resources
├── TildoneiOSTests/                New iOS unit/integration tests
├── TildoneiOSUITests/              New iOS UI tests
├── Packages/
│   └── TildoneCore/                New local Swift package
│       ├── Package.swift
│       ├── Sources/
│       │   ├── TildoneDomain/
│       │   ├── TildonePersistence/
│       │   └── TildoneSync/
│       └── Tests/
│           ├── TildoneDomainTests/
│           ├── TildonePersistenceTests/
│           └── TildoneSyncTests/
└── docs/
```

The structure is an intended end state, not permission for the next task to create every empty directory or implement persistence and sync prematurely.

## Xcode project decision

### Retain `Tildone.xcodeproj`

`Tildone.xcodeproj` remains the single developer entry point and contains both application targets and their platform test targets.

This is the smallest evolution of the current repository. It keeps these concerns together:

- Schemes and build configurations.
- Signing teams and App IDs.
- CloudKit and push-notification capabilities.
- App icons and platform resources.
- Unit and UI test hosts.
- Marketing/build versions.

The project already supports independent targets. A second project would create project-to-project dependency and scheme-management overhead without isolating a separately delivered subsystem.

### Do not add a top-level workspace now

A top-level `Tildone.xcworkspace` is rejected for the initial iOS work. Xcode can attach a local Swift package directly to an `.xcodeproj`; no manually maintained workspace is required.

Reconsider a workspace only if the repository later contains multiple independently built Xcode projects, such as an app project plus separately delivered extensions or developer tools that cannot be managed cleanly in the existing project. Target count alone is not sufficient reason.

### Preserve the existing Mac target identity

Do not rename the current `Tildone` target, product, scheme, directories, bundle ID, or test targets merely to make names symmetrical with iOS. Such a rename would churn `project.pbxproj`, schemes, test hosts, signing, paths, and release automation while providing no user value.

Use these new target and scheme names:

| Purpose | Target | Shared scheme | Source directory |
| --- | --- | --- | --- |
| Existing macOS app | `Tildone` | `Tildone` | `Tildone/` |
| Existing Mac unit tests | `TildoneTests` | Included in `Tildone` | `TildoneTests/` |
| Existing Mac UI tests | `TildoneUITests` | Included in `Tildone` | `TildoneUITests/` |
| New iOS app | `TildoneiOS` | `Tildone iOS` | `TildoneiOS/` |
| New iOS tests | `TildoneiOSTests` | Included in `Tildone iOS` | `TildoneiOSTests/` |
| New iOS UI tests | `TildoneiOSUITests` | Included in `Tildone iOS` | `TildoneiOSUITests/` |

The iOS product's display name remains **Tildone** even though its internal target name is `TildoneiOS`.

## Local Swift package decision

Create one local package at `Packages/TildoneCore`. It is one package for repository ownership and versioning, with multiple internal targets to enforce dependency boundaries.

Do not create separate repositories or separately versioned packages for domain, persistence, and sync. These components evolve together with the two Tildone applications and are not public SDKs.

### `TildoneDomain`

Responsibilities:

- Stable note and task identifiers.
- Version stamps and deterministic conflict rules.
- Task order-token generation and comparison.
- Pure note/task lifecycle and completion policies.
- Text normalization rules that are genuinely shared.
- Repository/service protocols and domain errors.

Allowed dependencies:

- Foundation.

Forbidden dependencies:

- SwiftUI, SwiftData, CloudKit, AppKit, UIKit, ServiceManagement, and application targets.

This target must remain usable in fast, deterministic unit tests without an Apple account, database, simulator, or UI runtime.

### `TildonePersistence`

Responsibilities:

- The new sync-ready SwiftData `StoredNote` and `StoredTask` models.
- `VersionedSchema` and `SchemaMigrationPlan` for the new shared store.
- Repository implementations and atomic local mutation capture.
- Tombstones, pending mutations, account-workspace metadata, and quarantine storage.
- Store construction for persistent, in-memory, preview, and test configurations.

Dependencies:

- `TildoneDomain`.
- Foundation and SwiftData.

`TildonePersistence` is a target inside `TildoneCore`, not a second package named `TildonePersistence`. Splitting it at the target boundary gives compile-time separation without unnecessary package-management overhead.

### `TildoneSync`

Responsibilities:

- `CKSyncEngine` lifecycle and delegate handling.
- Private CloudKit zone and record mapping.
- Applying fetched records through the shared merge rules.
- Account-change handling, pending-change scheduling, partial-failure recovery, and sync status.

Dependencies:

- `TildoneDomain`.
- Narrow persistence protocols or `TildonePersistence` where required.
- Foundation and CloudKit.

It must not import SwiftUI, AppKit, or UIKit. Neither app view layer calls CloudKit directly.

### Package products

Expose focused library products rather than one umbrella module that makes every consumer import SwiftData and CloudKit:

- `TildoneDomain`
- `TildonePersistence`
- `TildoneSync`

Both app targets may eventually link all three. Pure domain tests and tools can link only `TildoneDomain`. An umbrella `TildoneCore` product is unnecessary unless a concrete composition use case emerges.

## Platform application boundaries

### Existing macOS target

Keep these in `Tildone`:

- `TildoneApp` and `AppDelegate`.
- `Desktop` and the Mac `Note` view.
- Manual `NSWindow`/`NSHostingView` coordination.
- `Styler`, `WindowAccessor`, and AppKit checkbox/window behavior.
- Mac menus, shortcuts, focus traversal, and notifications.
- Clipboard integration using `NSPasteboard`.
- Launch at login using `SMAppService`.
- Focus Filter window behavior.
- Mac settings and window/appearance preferences.
- StoreKit update notes and installation-specific system content.
- The legacy `Todo` and `TodoList` SwiftData types until migration support can be retired.
- A future Mac-only legacy-store importer.

Do not add `#if os(iOS)` branches to these files to make them compile for iOS. Do not add them to the iOS target's Compile Sources phase.

### New iOS target

Keep these in `TildoneiOS`:

- Its own `@main` SwiftUI application entry point.
- Notes-list navigation and empty state.
- Native checklist editor and task-row presentation.
- iOS Settings and synchronization-status views.
- Touch, swipe, context-menu, drag-reorder, Dynamic Type, VoiceOver, and keyboard behavior.
- iOS lifecycle adapters and links to system settings.
- iOS-specific entitlements, Info.plist values, asset catalog, app icon, previews, and localized presentation strings.

The iOS target must not depend on the Mac application target and must not compile files from `Tildone/` merely because an individual file currently appears portable.

### Shared UI

Do not create a shared UI target for the first release. The platform information architectures are intentionally different, and current Mac components contain AppKit assumptions.

Small UI-independent value types or formatting rules belong in `TildoneDomain`. A genuinely identical reusable SwiftUI component may be extracted later only after both platform implementations demonstrate the same semantics and accessibility behavior. Avoid speculative sharing.

## Persistence model transition

Do not move the released `Todo` and `TodoList` model classes directly from `Tildone/Models` into `TildoneCore`. Their type/module identity and schema are associated with the released Mac SwiftData store.

Use this transition:

1. Leave `Todo` and `TodoList` in the Mac target as legacy persisted types.
2. Define the final cross-platform `StoredNote` and `StoredTask` types in `TildonePersistence` before either app stores production data with them.
3. Add a Mac-only importer that opens the legacy store and writes the new shared store side by side.
4. Verify counts, relationships, text, completion, and visible order before cutover.
5. Retain the legacy store read-only for the approved rollback period.
6. Point both app targets at the new store and repository operations.

This avoids an in-place module/type move and keeps legacy compatibility code out of the iOS application.

## Dependency direction

Dependencies flow inward toward pure domain rules:

```text
                    ┌──────────────────┐
                    │  TildoneDomain   │
                    └────────▲─────────┘
                             │
                  ┌──────────┴──────────┐
                  │                     │
       ┌──────────┴──────────┐  ┌───────┴────────┐
       │ TildonePersistence  │  │  TildoneSync  │
       └──────────▲──────────┘  └───────▲────────┘
                  │                     │
             ┌────┴─────────────────────┴────┐
             │ Application composition roots │
             └──────────▲───────────▲────────┘
                        │           │
                 ┌──────┴───┐ ┌─────┴──────┐
                 │ Tildone  │ │ TildoneiOS │
                 │  macOS   │ │    iOS     │
                 └──────────┘ └────────────┘
```

Rules:

- Package targets never depend on either application target.
- Platform views request typed repository/domain operations; they do not own save, sync, tombstone, or conflict policy.
- `TildoneDomain` remains unaware of persistence and transport.
- `TildonePersistence` remains unaware of UI.
- `TildoneSync` remains unaware of UI and platform presentation.
- The Mac and iOS targets may provide platform adapters conforming to shared protocols.

## Resources and localization

Resources have explicit ownership:

- Keep the existing Mac app icon, assets, preview assets, Info.plist, and entitlements in `Tildone/` and the Mac target only.
- Give `TildoneiOS` its own asset catalog, iOS app icon, preview assets, entitlements, and generated Info.plist settings.
- Do not add the Mac `TildoneIcon.icon` resource to the iOS target.
- Keep platform presentation strings in each application target.
- Move only genuinely shared domain/error strings into package resources if they need localization. Do not relocate the existing string catalog as part of merely scaffolding the iOS target.
- Preserve the project's known regions: English/Base, Spanish, French, and Simplified Chinese.

## Target configuration for the next iOS task

When the owner authorizes implementation of the iOS target, use these defaults unless a later decision overrides them:

- Target name: `TildoneiOS`.
- Product display name: `Tildone`.
- Shared scheme: `Tildone iOS`.
- Platform: iOS, iPhone device family for the first release.
- Deployment target: iOS 17.0.
- Interface: SwiftUI.
- Lifecycle: SwiftUI App.
- Swift language mode: match the existing project initially; language-mode upgrades are separate work.
- Build configurations: existing Debug and Release; do not introduce environment-specific configurations merely for the new target.
- Signing style: automatic with team `F6HFAVTS49`, subject to account access.
- Info.plist: generated, with iOS-specific values in target build settings unless an explicit plist becomes necessary.
- Entitlements: separate `TildoneiOS/TildoneiOS.entitlements`; never reuse the Mac entitlements file by path.
- Unit-test target: `TildoneiOSTests`, hosted by `TildoneiOS` where appropriate.
- UI-test target: `TildoneiOSUITests`, targeting `TildoneiOS`.

The final iOS bundle ID is intentionally not decided here. The choice depends on whether the iPhone app is added to the existing App Store product/universal-purchase arrangement or uses a separate listing. Do not create App IDs, CloudKit containers, or production entitlements using a guessed bundle ID.

## Scope of the next implementation task

An implementation task whose objective is specifically “add the iOS target” should be a scaffold, not the full architecture migration.

It should:

1. Add `TildoneiOS`, `TildoneiOSTests`, and `TildoneiOSUITests` to the existing project.
2. Add and share the `Tildone iOS` scheme.
3. Create a minimal iOS `@main` app and placeholder root view that compile independently of the Mac target.
4. Add iOS-owned assets, previews, generated Info.plist settings, and a separate entitlements file with no speculative CloudKit container.
5. Set iOS 17.0 and the approved signing/bundle settings.
6. Verify the existing Mac scheme still builds and the new iOS scheme builds/tests in an available simulator or generic destination.
7. Keep the placeholder free of copied Mac models and UI.

It should not:

- Rename or relocate `Tildone`, `TildoneTests`, or `TildoneUITests`.
- Create a top-level workspace or second Xcode project.
- Add existing Mac source files to the iOS target.
- Move `Todo` or `TodoList` into a package.
- Implement migration, CloudKit, sync, or production persistence.
- Add guessed iCloud containers, App IDs, or production capabilities.
- Begin a broad Mac MVVM/refactor effort.
- Rewrite `project.pbxproj` in a way that discards the staged icon changes.

Creating `TildoneCore` may be a separate task before or after the iOS scaffold. If combined with target scaffolding, it should initially contain only the package manifest, target boundaries, and independently tested pure domain primitives that the task explicitly requires. Do not create empty architectural layers solely to match the tree above.

## Sequencing after target scaffolding

Recommended sequence:

1. Scaffold the iOS app and test targets without sharing legacy source.
2. Add `Packages/TildoneCore` and implement/test `TildoneDomain` primitives.
3. Add the new versioned models and repositories in `TildonePersistence`.
4. Implement and validate the Mac side-by-side legacy migration.
5. Route Mac mutations through the shared repository while preserving AppKit behavior.
6. Implement `TildoneSync` behind a development feature flag.
7. Build the complete iPhone notes list and checklist editor on the shared repository.
8. Configure and promote production CloudKit only after multi-device testing.

The scaffold can precede the package because it establishes independent platform ownership. It must not ship as a functional companion until the shared persistence and synchronization stages are complete.

## Alternatives considered

### Convert the existing Mac target into a multiplatform target

Rejected. Current source contains substantial AppKit-specific application, window, keyboard, pasteboard, Focus Filter, settings, and lifecycle code. Conditional compilation would spread platform checks through working Mac code and make target membership ambiguous.

### Add iOS source files directly to the existing target

Rejected. App products have different SDKs, lifecycles, signing, entitlements, resources, test hosts, and information architecture. They need distinct application targets.

### Create a second Xcode project and top-level workspace

Rejected for now. It adds scheme and project-dependency overhead without an independently owned build product that needs project-level isolation. A local package already provides the important source dependency boundaries.

### Put all shared code in one `TildoneCore` target

Rejected. A monolithic target would cause pure domain consumers to import/link persistence and CloudKit concerns, weaken compile-time boundaries, and slow tests. One package with several targets provides a better balance.

### Create separate `TildoneDomain`, `TildonePersistence`, and `TildoneSync` packages

Rejected. These are internal components with one release cadence. Separate manifests and dependency resolution add maintenance without independent versioning value.

### Create an Xcode framework target instead of a local package

Rejected. A local package provides clearer dependency declarations, package-level tests, and less project-file target/build-setting maintenance. There is no requirement to distribute a binary framework.

### Share complete SwiftUI views between platforms

Rejected for the initial release. The product deliberately uses sticky desktop windows on Mac and list/detail navigation on iPhone. Premature shared views would encode the wrong abstraction.

## Consequences

### Positive

- The shipping Mac target remains recognizable and minimizes release-risk churn.
- iOS receives native lifecycle, resources, tests, and interaction design.
- Shared behavior has enforceable dependency boundaries and fast unit-test surfaces.
- Persistence and CloudKit remain replaceable/testable behind domain operations.
- Legacy Mac migration is isolated from the clean iOS implementation.
- The project remains easy to open: one `.xcodeproj`, two application schemes.

### Negative

- The repository temporarily contains legacy Mac models alongside new shared stored models during migration.
- Some concepts may be represented twice in platform UI code by design.
- The existing project uses explicit classic groups, so target/file additions require careful `project.pbxproj` changes.
- One project file becomes a shared point of change for both platforms; small, reviewable edits and preservation of unrelated changes are essential.
- Multiple package targets introduce dependency design work earlier than a monolithic shared folder would.

### Risks

- Moving legacy model types prematurely could make the released SwiftData store unreadable.
- Copying apparently portable Mac files into iOS target membership could pull in hidden AppKit assumptions.
- Guessing the iOS bundle ID or CloudKit container could create difficult-to-reverse Developer Portal state.
- A broad project-file regeneration could erase the current staged app-icon migration.

The scope rules and sequencing above are the mitigations.

## Acceptance criteria for this ADR

This decision is ready to guide implementation when the owner confirms:

1. One Xcode project and no new top-level workspace.
2. Separate `TildoneiOS` application/test targets and platform-owned UI.
3. One local `TildoneCore` package with domain, persistence, and sync targets.
4. Existing Mac target/directory names remain unchanged.
5. iOS 17.0 as the initial deployment target.
6. The App Store packaging/bundle-ID decision will be supplied before signing or capability configuration requires it.

Until those points are accepted, this ADR is a recommendation and the next task should not make irreversible signing, App ID, or CloudKit-container choices.
