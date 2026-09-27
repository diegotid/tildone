# Tildone Pro purchase setup and acceptance

## Repository audit (2026-09-25)

- The released Mac App Store identity recorded in this repository is `studio.cuatro.tildone`, team `F6HFAVTS49`, version 1.6.0 (24); the [public listing](https://apps.apple.com/es/app/tildone-tareas-adhesivas/id6473126292?mt=12) has Apple ID `6473126292`, is Mac-only, and showed a free download on 2026-09-25. This audit does not verify the private App Store Connect record.
- The iOS target used `studio.cuatro.tildone.ios` before this change. Its Debug and Release application bundle IDs now match Mac: `studio.cuatro.tildone`. Both targets use automatic signing on the same team. The test targets retain their distinct test bundle IDs.
- Both app entitlements still name `iCloud.studio.cuatro.tildone`, the private CloudKit container, and **Development** environment. Both Release transports remain disabled under the current policy. No Production CloudKit schema, transport, records, or capability was changed here.
- The product ID in code and the local StoreKit configuration is exactly **`studio.cuatro.tildone.pro`**. It is one non-consumable product in one app record, not a pair of platform products. The local fixture price is only for testing; the paywall uses StoreKit's current localized `displayPrice`.
- An iOS installation under the old `.ios` bundle ID has a different app container. Installing the matching-ID app cannot read its local-only notes or preferences automatically. Do not uninstall the old development app until those notes have been exported or an explicit migration path has been verified. Development CloudKit notes may reappear on the matching account after sync, but this must be checked on a copy of data; CloudKit content never grants Pro. The Mac app's existing bundle ID and local stores are unchanged. No local note schema migration is introduced.

## Owner actions before distribution

1. In App Store Connect, inspect the existing **Tildone** app record and confirm its Mac bundle ID is `studio.cuatro.tildone`. Add an **iOS platform version to this same app record** with the same bundle ID. Do not create a separate iOS app record.
2. In Certificates, Identifiers & Profiles, confirm that team `F6HFAVTS49` can sign the iOS target for `studio.cuatro.tildone`, with the required iCloud container and In-App Purchase capability. Regenerate provisioning profiles if automatic signing cannot resolve them. Keep CloudKit in Development for this stage; Production work needs separate authorization.
3. Create one **non-consumable** In-App Purchase on that app record with product ID `studio.cuatro.tildone.pro`. Configure price, availability, and localized App Store descriptions. Complete any required agreements, banking, tax, and review information. The exact product ID must match the code; if App Store Connect already has a different ID, change code and local fixture together before a build is distributed.
4. Decide how to migrate or safely retire any test iOS installations under `studio.cuatro.tildone.ios`, especially local-only workspaces. A same-ID iOS release must not be presented as an in-place update to that different app.
5. Before eventual release, review the existing Mac app's price/business model and App Store listing against free note editing plus paid Pro. No archive, upload, TestFlight, or App Review submission is performed by this change.

Apple's [Add platforms guidance](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms) describes the shared app record and bundle ID; it notes that universal purchase becomes available after at least two platform versions are approved. Apple's [In-App Purchase guidance](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases) says to create one product under the app for availability across its platform versions.

## Local StoreKit and cross-platform acceptance

The two Debug launch schemes select `TildonePro.storekit`. Use Xcode's StoreKit transaction manager to clear local transactions between scenarios. These local tests exercise the UI and state machine; the cross-device checks need signed sandbox builds with the real App Store Connect product.

1. Launch each app with no transaction. Confirm ordinary note editing and iCloud sync work. Try every Pro entry: Mac note-kind menu and Return shortcut, Mac and iOS formatting menus, font selector, Mac Tab hierarchy and iOS indent/swipe actions, Mac Focus & Privacy menu, dim scroll for one/all notes, gather scroll, and the dim/gather shortcut controls in Mac Settings. Each entry should present Tildone Pro before changing data; the current localized StoreKit price must appear.
2. Purchase on Mac. Verify a successful verified transaction unlocks all Mac features. Relaunch and verify access persists. Sign in to the same sandbox Apple Account on iPhone, open or restore the iOS app, and verify the same product unlocks its Pro features without another product purchase. Repeat with purchase on iPhone and restore on Mac.
3. Cancel the purchase sheet: no entitlement or content change. Simulate Ask to Buy/pending: show pending status, keep gates closed, then approve and verify the transaction update unlocks Pro. Make the product unavailable or product loading fail: show the retry state and keep Restore Purchases accessible.
4. Use **Restore Purchases** from the Mac app menu and the iPhone About screen. Verify restoration with and without a purchase and after a relaunch. Simulate a refund/revocation and verify current entitlements remove access to new Pro actions.
5. Before and after loss of entitlement, inspect existing single memos, rich text, fonts, subtasks, Mac Focus privacy overrides, dimmed notes, and gathered notes. Content remains intact and editable as ordinary text. Existing Mac privacy behavior stays active; restoring opacity and note positions remains possible. Repeat offline and after re-enabling connectivity.
6. Check English, Spanish, French, and Simplified Chinese paywalls, status messages, menus, and accessibility labels on both platforms. Verify both unsigned Debug/Release builds and the release configuration script, then complete signed sandbox/device acceptance separately before any release decision.

## Feature paywall previews (2026-09-26)

Each feature entry point now shows a brief outcome description and a raster preview of that feature. The generic sparkles header has been removed. Explanations and mock note content are localized in English, Spanish, French, and Simplified Chinese in both platform catalogs.

Previews use ephemeral domain values only. Mac renders its actual `TaskRow` and memo text-field controls into an offscreen image, then SwiftUI composes blur, opacity, and gathering illustrations. iPhone renders its actual `NoteCard`, including rich text, task hierarchy, memo typography, and accurate mock completion counts. No preview accesses a repository, changes preferences, or reads/syncs user content. Images are generated locally as needed for the selected language and appearance; no external image service is involved. The paywall scrolls so longer explanations and larger iPhone text remain accessible.

Validation: unsigned Debug app builds passed on Mac and iOS Simulator. The Mac preview test rendered all six features in four languages and light/dark appearance (48 images); the iPhone 17 Pro simulator on iOS 26.4 rendered its three features across the same languages/appearances (24 images). Both rendering tests passed, including checks that translated mock content differs from English, images are nonempty, and feature previews are distinct. The localized Mac paywall layout capture test also passed. Existing unrelated compiler warnings remain; no new warning originates in the preview implementation. These are local UI checks, not signed Sandbox purchase evidence.

### Square preview revision (2026-09-26)

Feature headings are larger, explanations precede previews, and preview canvases are square. Mac previews reuse `SettingsPreviewBackground` and its `desktop` image, with 216×288 (3:4) note windows, three titlebar buttons, and actual rasterized note controls. Blur and Stay in Background now route to distinct feature paywalls. Resetting Focus defaults shows both examples. The blur example has a calm pointer/hover demonstration, an unblurred moon control, and real hover reveal; Reduce Motion stops automatic movement and disables the hover transition animation. The background example shows a mock foreground window and a moon control. Dimming and gathering retain their own illustrations. Memo fonts remain included under text styling.

The text-format examples now style only the localized words corresponding to “ideas,” “matters,” and “quiet.” iPhone keeps its native note-card presentation in the square canvas, with a 3:4 card and accurate task completion counts.

Both unsigned Debug app targets compiled during the selected test runs. Five Mac tests passed (seven distinct previews × four languages × two appearances; blur/reveal and Reduce Motion pixel checks; localized paywall layout; single-word ranges; feature gating). Two iPhone tests passed on the iPhone 17 Pro simulator with iOS 26.4 (three native previews × four languages × two appearances and single-word ranges). The Mac image checks use a constant native raster and compare visible pixels with a small dithering tolerance rather than requiring identical PNG compression/metadata. All newly added text is translated in both catalogs. Signing, StoreKit product identity, persistence, and CloudKit settings were unchanged by this revision.


### Compact paywall and Settings preview reuse (2026-09-27)

Removed the redundant in-content “Tildone Pro” heading. Purchase/retry and Restore Purchases now fill the same 360-point content width as the square preview, with 24-point outer padding. The Mac window measures its content height rather than always reserving 740 points; long/combined explanations remain scrollable with a 720-point height cap.

Mac note window controls are now 12 points at the normal preview note scale. Formatting highlights one word in pink, contrasting with the yellow note. Blur places its white moon in the wallpaper’s upper-right corner. Stay in Background shows a smaller note behind a larger foreground window. The memo uses a realistic electrician reminder translated into all four languages; native TextKit layout selects a font size that accommodates fallback Chinese glyphs as well as Latin text. Subtasks retain their existing content.

Dimming and gathering now use the actual `DimmingPreview` and `GatherPreview` from Settings, including their existing animation timing, direction chevrons and Dock illustration. Optional canvas sizing and window controls adapt those views to the square paywall; their default Settings layout remains unchanged. Deterministic test captures use an offscreen AppKit hosting surface for these views, since SwiftUI ImageRenderer cannot render their native material/checkbox components.

Validation: both unsigned Debug application targets built. Four Mac Pro tests passed (56 localized/light-dark feature renders, hover/reveal and Reduce Motion, compact localized paywall layout, and single-word formatting); the memo fitting correction was rerendered across all languages. Two iPhone tests passed on iPhone 17 Pro / iOS 26.4 (24 renders and single-word formatting). Existing dimming cycle and directional chevron tests also passed. An additional existing `testBottomRightGatherPreviewMovesScrollChevronsToTheLeftEdge` failed: its top-right assertion expects a 4-point inset, but unchanged `previewCenterX = 228` and indicator width 24 give zero in the 240-point canvas. Those constants and that test were not modified by this request. `git diff --check` passed. No signing, purchase identity, persistence, or CloudKit configuration was changed.


### Settings-aware preview follow-up (2026-09-27)

The background example’s foreground window moves upward by 24 points, leaving 28 points below its frame. The purchase button places its localized action at the leading edge and StoreKit’s localized price at the trailing edge on one row.

Mac gathering and dimming previews now observe the same AppStorage keys as Settings for the default note color, background opacity, and gathering corner. Gathering additionally follows the selected corner margin and Dock-space reservation. The dimming sample aligns to the selected corner, with its scroll indicator on the opposite side. Gathering’s mock Dock uses an edge-aligned position in the square paywall; existing Settings preview Dock placement remains unchanged.

Validation: both unsigned Debug app targets built. The Mac localized preview and compact paywall tests passed. A focused settings rendering test passed with isolated UserDefaults for pink/top-right and blue/bottom-left cases, producing four images without changing the owner’s preferences. Visual checks confirmed the foreground-window spacing and Dock edge placement. No new user-visible strings were introduced; existing localized labels and StoreKit price formatting are retained. `git diff --check` passed.


### Pro feature discovery navigation (2026-09-27)

The paywall now uses a NavigationStack whose root is the full seven-feature index. A feature-triggered presentation starts with that feature already pushed. Every feature page offers “Discover all Pro features,” which clears the path and returns to the index. The Mac adds an explicit toolbar back button; iPhone uses the native navigation back button. Selecting an index row opens its description and preview. The index identifies Mac-only features; iPhone describes those features without presenting an inaccurate iPhone card as their preview. Purchase, localized price, and Restore Purchases remain available on both index and detail pages.

Gathering’s moving sample notes no longer show titlebar buttons. Stay in Background now uses the same white moon in the wallpaper’s upper-right corner as Blur Content. The new index, discovery action, and Mac-only labels are translated in English, Spanish, French, and Simplified Chinese in both catalogs.

Both unsigned Debug app targets built, and Mac/iPhone preview checks passed, including four localized Mac paywall layouts. The iPhone 17 Pro / iOS 26.4 UI test passed for triggering the Single memos paywall, returning to the index through the discovery action, selecting Text styling, and returning through native Back. The test uses an isolated in-memory workspace and the current keyboard-based title entry flow.

The Mac UI navigation test also passed: index → Single memos → discovery action → index → Text styling → toolbar Back → index. The unsigned UI runner initially could not launch, and ordinary ad-hoc signing was rejected because of the app’s Development cloud entitlements. The successful isolated run used `/tmp/TildoneProNavigationUI` with command-line-only overrides `CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES CODE_SIGN_ENTITLEMENTS='' ENABLE_APP_SANDBOX=NO`. This is a temporary UI-test artifact with an in-memory workspace and cloud transport disabled by the test launch; it does not verify developer signing, sandbox capabilities, CloudKit, or cross-platform purchases. Source project signing/entitlements, Release transport, and Production resources were unchanged. `git diff --check` passed.


### Title restoration and compact feature index (2026-09-27)

Removed the navigation stack chrome and back controls. The Mac scene retains its original “Tildone Pro” window title. Feature selection is now local paywall state: entry points still start at the triggering feature, index rows select a feature, and “Discover all Pro features” returns to the index.

Index rows use separate short captions translated in English, Spanish, French, and Simplified Chinese, with tighter row spacing/padding. Mac captions occupy one line; iPhone captions may wrap for larger accessibility text. Full descriptions remain on feature pages. At the normal Mac window size, all seven rows and the purchase/retry and restore controls fit without scrolling; scrolling remains available when content needs more room.

Validation: both Debug targets built. Localized Mac index/detail layout checks passed in all four languages with the index’s content height below its 720-point cap. The Mac UI test confirmed the original window title, both purchase controls inside the visible window frame, no toolbar back button, and discovery navigation. The iPhone UI test confirmed trigger-first presentation, discovery navigation, and no navigation-bar back button. Mac UI validation used the same isolated ad-hoc test artifact/command-line entitlement overrides described above; source signing and CloudKit configuration were unchanged.

The first Mac test builds encountered four stale project references to missing `TildonePro 2.storekit`. Only those duplicate-file references were removed; `TildonePro.storekit` and its test resource membership remain intact. No purchase configuration content was replaced. `git diff --check` passed.


### Fixed Mac paywall size without scrolling (2026-09-27)

The Mac Pro window now uses a fixed 408×620-point content size for both the feature index and every feature detail. The Mac paywall contains no ScrollView. Feature preview canvases are 360×200 points; note windows scale proportionally to keep their 3:4 shape. Wallpaper, moon controls, hover motion, foreground windows, Settings-based dimming, and gathering adapt to the shorter canvas. Combined Focus & Privacy presents its two labelled examples side by side to fit the same window.

Index rows use 8-point padding, and a 42-point status area is reserved beneath the actions so purchase/restore messages do not change layout or push controls out of view. Mac status messages occupy at most three lines, with their full text available in the hover help and accessibility text. iPhone retains its native scrolling layout for smaller screens and larger accessibility text.

Validation: all nine Mac pages (index, seven catalog features, and combined Focus & Privacy) passed natural content-height checks in all four languages at the fixed 620-point height, including the reserved status area. Existing preview renders also passed. The Mac UI test visited all seven catalog features, confirming constant window size, zero scroll views, and visible discovery, purchase/retry, and restore actions. Both Debug app targets compiled. Mac UI tests used the previously documented isolated ad-hoc build with command-line-only entitlement overrides. Source signing, purchases, persistence, and CloudKit settings were unchanged. `git diff --check` passed.

### Content-fitted index and expanding previews (2026-09-27)

Supersedes the fixed 620-point window and reserved status space above. The Mac paywall measures the index's actual content height and applies that same height to all feature pages. The index has 24-point padding on every edge, including beneath Restore Purchases (or an active status message). Status messages occupy space only when present. The measurement copy is hidden, noninteractive, and excluded from accessibility.

Feature previews fill the remaining space between their descriptions and the discovery/purchase controls. Preview scenes adapt to the available height; note proportions remain 3:4, including in the narrower combined Focus & Privacy columns. Mac pages contain no ScrollView.

Validation: all nine Mac pages passed equal-height/content-fit checks in English, Spanish, French, and Simplified Chinese. The Mac UI test visited all seven catalog features and confirmed constant window size, zero scroll views, visible controls, and 24-point bottom padding matching the horizontal padding. Mac tests and the iOS Simulator build passed. UI tests used the previously documented isolated ad-hoc test build; source signing, purchases, persistence, and CloudKit configuration were unchanged. Offscreen layout captures were visually inspected for the expanded preview and bottom spacing; native button rendering in those captures remains an AppKit snapshot limitation. No new UI text was introduced.

### Native editor state-update warning fix (2026-09-27)

Title and task representables now schedule pending AppKit focus requests after the current SwiftUI update. Previously `updateNSView` called `makeFirstResponder` synchronously, allowing editor callbacks to mutate note state (including `isTopicHidden`) during rendering. Deferred requests recheck the current pending flag, preserving cancellation when focus moves elsewhere.

Validation: the Mac Debug target compiled and three focused tests passed: deferred focus/cancellation, title keyboard navigation to tasks or the capture field (empty/nonempty titles, with/without tasks, Return/Down/Tab), and title Return followed by checklist paste. Tests use in-memory repositories. No persistence, entitlement, CloudKit, or UI copy changes were made.

### Settings-aware preview text color (2026-09-27)

Mac note previews now call the same `NoteContentForeground` calculation as actual notes, using the current appearance and background opacity. Titles, memo text/cursors, task text/cursors/placeholders, and task-row light/dark styling share that result. Removed the forced light appearance from the preview note and its native raster. Explicit sample text colors/highlights are retained. Cached native previews refresh for appearance and background-opacity changes; deterministic capture helpers accept the same appearance/settings inputs. Dimming already uses the Settings note's shared foreground calculation, and gathering has no text content. iPhone continues using its native NoteCard styling.

Validation: three Mac tests passed, covering native text pixels in both appearances at three opacity settings, all seven feature renders in four languages and both appearances, and Settings-aware dim/gather scenes. Both Debug app targets compiled. No new UI copy, persistence, signing, purchase configuration, or CloudKit changes.

### Restored opacity-aware note contrast (2026-09-27)

Identified the regression in commit `6e9af8397635bc4f59570423ba017a151b275d90` (“Fix Dark Mode task text color,” 2026-09-15): `NoteContentForeground.usesLightText` had changed from `colorScheme == .dark && backgroundOpacity < 0.5` to `colorScheme == .dark`, ignoring note opacity. Restored the previous opacity threshold. Pastel notes at 50% or greater background opacity use dark text in both appearances; more transparent notes use light text in Dark Mode. Actual notes, Settings examples, and Pro previews share this calculation. Explicit rich-text colors are preserved.

Validation: the Mac Debug app compiled and four focused tests passed: opacity-threshold/light-appearance/dimming cases; native preview text pixels at three opacity settings in both appearances; localized feature renders; and an actual green Note hosted with an isolated in-memory repository in Dark Mode. The actual-note test checks both title and task field colors at opacity 0.7, 1.0, and 0.2. No new UI strings, stored-content changes, signing, or CloudKit changes.

### General settings Pro discovery section (2026-09-27)

Added a Tildone Pro section beneath the existing General content and a divider. It shows the universal-purchase caption (or unlocked status for owners) and a prominent “Discover all Pro features” button. The button clears the triggering-feature selection and opens the existing Pro window at its index. All displayed strings reuse English, Spanish, French, and Simplified Chinese catalog entries. General's pane height is 288 points to fit the added section.

### Separate Settings purchase and discovery actions (2026-09-27)

General's Pro section now has separate full-width purchase and discovery buttons. Extracted `ProPurchaseButton` from the feature paywall so Settings and paywalls share the same action, localized StoreKit price, leading action/trailing price layout, disabled state while purchasing, and product-loading retry behavior. The purchase button directly calls `ProEntitlement.purchase()`; it does not open the index. The secondary discovery button opens the index. Owners see unlocked status instead of a purchase button. Purchase/pending/failure messages are visible in Settings. General's height is now 384 points to accommodate the actions. All copy reuses the existing four-language translations.

Validation: Mac UI test confirms two distinct visible controls and that discovery opens the full index. Mac Debug compiled during the UI test; iOS Simulator Debug build passed after the shared-button extraction. No live purchase was made by this validation. Source signing, StoreKit configuration, data, and CloudKit settings were unchanged.

### Unlocked Settings confirmation banner (2026-09-27)

When the shared entitlement reports Pro unlocked, General replaces its purchase/discovery section with a full-width rounded banner reading “Tildone Pro is unlocked.” The banner uses a subdued green tint (14% opacity), a subtle green border, and standard primary text for appearance/accessibility contrast. It occupies the same section below the divider. The General pane uses 288 points for owners and retains 384 points for the paywall. The message reuses its English source and Spanish, French, and Simplified Chinese translations. The observed entitlement updates the banner automatically after purchase/restore or revocation.

Validation: Mac Debug app compiled and the Settings sizing test passed with the hosted-test unlocked entitlement. `git diff --check` passed. No purchase, stored content, signing, or CloudKit configuration changes.
