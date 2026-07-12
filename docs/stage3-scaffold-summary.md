# Stage 3 Scaffold Summary

## Repository changes

- Retained `Tildone.xcodeproj` as the sole Xcode project and developer entry point.
- Added the iOS-owned `TildoneiOS/`, `TildoneiOSTests/`, and `TildoneiOSUITests/` directories.
- Added the repository-local package at `Packages/TildoneCore`.
- Left the existing macOS source, target names, source membership, persistence, and behavior unchanged.

## Created targets and scheme

- `TildoneiOS`: iPhone-only SwiftUI application target with a placeholder root view.
- `TildoneiOSTests`: iOS hosted unit-test target.
- `TildoneiOSUITests`: iOS UI-test target.
- `Tildone iOS`: shared scheme that builds, runs, and tests the iOS application.

## Package structure

`Packages/TildoneCore` exposes the three ADR-approved library products and target boundaries:

- `TildoneDomain` (Foundation-only boundary)
- `TildonePersistence` (depends on `TildoneDomain`)
- `TildoneSync` (depends on `TildoneDomain`)

Each target has only the source file Swift Package Manager requires to form a module. No domain types, repositories, SwiftData models, persistence, migration, CloudKit, or synchronization code has been added. The package is attached to `Tildone.xcodeproj`, but no application target links it yet.

## Project configuration

- iOS deployment target: 17.0.
- Device family: iPhone.
- Display name: Tildone.
- Swift language mode: 5.0, matching the existing project.
- Separate generated Info.plist settings, asset catalog, preview assets, and empty iOS entitlements are configured.
- Automatic signing retains team `F6HFAVTS49`.
- No CloudKit, iCloud container, push-notification, or other production capability is configured.

## Deferred owner decision

`studio.cuatro.tildone.ios.placeholder` is a local, explicitly temporary bundle identifier needed for Xcode to build the scaffold. It must be replaced after the owner decides whether iOS belongs to the existing App Store product/universal purchase or a separate listing. No Apple Developer Portal resource was created.

## Build verification

All requested build checks passed with code signing disabled solely for local validation:

- `xcodebuild -project Tildone.xcodeproj -scheme Tildone ... build`
- `xcodebuild -project Tildone.xcodeproj -scheme 'Tildone iOS' -destination 'generic/platform=iOS' ... build`
- Builds of `TildoneTests`, `TildoneUITests`, `TildoneiOSTests`, and `TildoneiOSUITests`.
- `swift test --package-path Packages/TildoneCore` (three passing module-boundary tests).

No macOS application source, target membership, persistence, or runtime behavior was changed. A simulator runtime was unavailable in the validation environment, so iOS UI tests were compiled but not executed against a simulator.

## Deviations from the ADR

None. The ADR permits the package scaffold to remain function-free, and the product tree is deliberately not treated as permission to implement persistence or synchronization.

## Assumptions

- The Stage 2 documents supplied for this task are the requested owner approval for the ADR's structural direction.
- The final iOS App Store packaging and bundle-ID choice remains deferred as stated in the ADR.

## Deferred implementation work

- Shared domain primitives, stored models, repositories, migrations, and legacy-store import.
- Any SwiftData store shared by platforms.
- CloudKit, `CKSyncEngine`, account handling, sync metadata, and conflict rules.
- Notes, tasks, navigation, settings, user-facing iOS features, and production assets.
