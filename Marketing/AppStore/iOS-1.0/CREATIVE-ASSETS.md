# Header and Search Results

Lineup approved on 26 October 2026. Work on one asset at a time: English
thumbnail approval precedes the full asset. Keep English only until the final
composition is approved, then localize into es-ES, fr-FR and zh-Hans.

| Asset | Copy and visual | Full upload dimensions |
| --- | --- | --- |
| Header | “Your Mac notes. With you.” and “Free iCloud sync”. Matching real Weekend checklist on iPhone and MacBook, six-color palette and translucent bezels. | 3840 × 1646 opaque PNG |
| Search Results | “Your to-dos. On iPhone and Mac.” Prominent native checklist and supporting Mac note; free iCloud sync. | 3840 × 2560 opaque PNG |

Use saved captures from the private native SwiftUI fixtures. Revisions 1–3
reused the unchanged Mac screenshot-2 crop; the approved revision 4 captures
matching five-task notes on both platforms. No live iCloud transaction, physical iPhone,
customer data or foreground screen capture is needed. Free features only.
Keep mock task content consistent between devices. Keep essential copy and
note content central and inspect Apple placement previews before publication.
The Header's revision 4 thumbnail was approved on 26 October 2026. Its full
3840 × 1646 export preserves the approved English composition exactly.
The Search Results revision 1 thumbnail was also approved on 26 October 2026.
Both approved compositions can now be fully exported and localized.

Apple's dedicated Header PSD marks the central art-safe rectangle at
`[1097, 493, 2743, 1154]` on its 3840 × 1646 canvas. Keep the headline, free-sync
line and native note content within that rectangle; decorative device edges
can extend outside it. The current English review thumbnail is under
`Marketing/Preview/Output/iOS/creative/header/r4/en-US/` and is not an upload
asset. The full Header PNG uses the same native inputs and renderer at 3×.

Header revision 2 follows the owner's feedback on revision 1: fill the canvas,
enlarge the MacBook display until its bottom extends beyond the lower edge,
keep the entire Mac note visible, and enlarge the foreground iPhone with a
physical titanium frame and side buttons. The iPhone island remains hidden.
The former central-only composition is superseded for this thumbnail. Retain
revision 1 and render the revision 2 review under `creative/header/r2/en-US/`.

Header revision 3 reduces the Mac note to 60% of revision 2's width and height,
preserving its center. The entire foreground iPhone casts a broad soft shadow
and a tighter contact shadow onto the MacBook screen. Retain revision 2 and
render this English review under `creative/header/r3/en-US/`.

The approved full Header set is complete in en-US, es-ES, fr-FR and zh-Hans.
All four 3840 × 1646 PNGs passed format, source-hash and matching-native-content
checks, and their localized text was visually reviewed. They are delivered in
the standing final folder's per-language `Creative` folders. The English
composition was compared pixel-for-pixel with the approved r4 thumbnail before
its full-resolution export. No App Store upload or submission was made.

Header revision 4 adds three tasks to both native notes and completes “Check
the train times”. The five ordinary tasks are defined once in
`Marketing/Preview/Inputs/header-note.json`; both private fixture builders copy
that input into their app resources. Existing screenshot/preview fixtures are
unchanged. Build the phone with `--story ios-screenshot-header`, then capture
with `capture-marketing-phone.py --fresh-device`. Build the Mac with
`--story header`, then execute only that private app's `Contents/MacOS/Tildone`.
Its accessory app orders its own small wallpaper stage behind other windows,
never activates or makes a key window, and captures only its own stage/child
note through `SCShareableContent.currentProcess`. No idle screen is required.
The regular Mac screenshot/recording paths keep their existing screen-idle
requirements.

Keep the results as `phone-native/` and `mac-native/` within the new revision
directory, then pass that directory to
`render-marketing-ios-header-thumbnail.swift output.png --native-root <directory>`.
The compositor verifies matching native task text and completion state before
rendering. The Mac note retains the 60% scale and the iPhone foreground shadow.

Use `--full --locale <locale>` for an approved Header upload export.
`Scripts/localize-marketing-ios-header.py` stages private locale app copies,
captures the background Mac note and owned simulator, checks matching native
content, and renders the localized full exports. It requires an approved full
English Header record and never launches a normal customer app. Review each
localized output before publishing the delivery folder.

The first Search Results thumbnail is under
`creative/search-results/r1/en-US/`. It uses the same five-task native content,
foreground iPhone hardware/shadow and cropped MacBook display. Its headline
is “Your to-dos. On iPhone and Mac.” with “Free iCloud sync”. The taller 3:2
composition puts the headline above the devices and enlarges the checklist.
Render with `--asset search-results --full --locale <locale>` for its approved
3840 × 2560 upload export. Reuse the Header's four localized native captures;
no new capture or idle-screen session is needed. The export helper is
`Scripts/export-marketing-ios-search-results.py`, with `--native-root`,
`--output` and `--approved-thumbnail` arguments. It verifies the English
composition against the approved thumbnail, renders all four languages,
preserves iteration outputs, and publishes only when rerun with `--publish`
after localized visual review.

Search Results is complete in en-US, es-ES, fr-FR and zh-Hans. Each full export
is an opaque 8-bit sRGB PNG at 3840 × 2560. The English composition matches
the approved thumbnail exactly; all four localized images were visually
reviewed. They reuse the approved localized Header native captures, with the
same five tasks and one completed item, and required no new capture.

The standing final folder contains 40 upload files: 24 medium-display
screenshots, eight previews, four Headers and four Search Results images.
Each locale's `Creative` folder contains its Header and Search Results PNGs.
Earlier iterations and review material remain outside the upload folder.

These optional creative assets are separate from screenshots and previews.
Only approved full assets belong in the standing upload folder. Drafts,
thumbnails, proofs and source recordings remain under Preview/Output.

## Header crop correction — approved 27 October 2026

App Store Connect's placement preview revealed clipping in the delivered r4
Header. Its canvas-filling layout puts essential copy and the Mac note outside
the template's central safe area. The r4 technical audit checked the PNG and
native sources but did not qualify placement cropping; it must not be treated
as evidence that essential content survives every placement.

The English r5 review uses `--crop-safe-review` to place the existing headline,
free-sync line and native checklist content within the central rectangle.
The six-color background still fills the canvas, and the Mac display extends
below the image. The existing five-task native captures are reused. No new
capture or idle-screen session is needed. Keep r4 and its delivered files until
the revised English thumbnail is approved. The renderer refuses full exports
or localization in this review mode. Review both the whole canvas and a
safe-area detail; the detail is a conservative template check, not a claim to
replicate App Store Connect's exact device crop. Final placement qualification
requires App Store Connect's own preview.

The owner rejected r5's tall Mac screen as resembling a portrait iPad. English
r6 restores the original landscape display proportions and adds a visible
metal keyboard deck and trackpad beneath it, with the lower edge continuing
past the canvas. This hardware-only change keeps the safe-area copy, native
notes, foreground iPhone and shadows in their r5 positions. Both r5 and r4 are
preserved. English thumbnail approval is still pending; full export and
localization remain disabled for the revised review composition.

English r7 projects the whole keyboard plane, including each key, the keyboard
well and the trackpad, through a single perspective transform matching the
metal base's trapezoid. The rear edge is narrower than the front edge and all
deck features share its vanishing point. The display, native note, phone and
copy retain r6 geometry. Preserve r6 and review r7 before full export.

The owner approved r7 on 27 October 2026. All four localized full Headers are
now exported at 3840 × 1646, visually reviewed both in full and within the
template safe area, and delivered. The compositor permits full r7 exports and
localization with `--crop-safe-review`; the flag selects this approved layout.
`Scripts/export-marketing-ios-header.py` verifies the approved English
thumbnail, reuses r4's four native capture sets, and retains each full output
and review image under `creative/header/r7/<locale>/`. Run it with
`--native-root`, `--output` and `--approved-thumbnail`, then `--publish` after
localized review. No new capture is required. It preserves the old canonical
records and delivery history; the standing folder contains the four new
Headers and the unchanged 36 other assets. App Store Connect's own device
preview remains the final check of its placement-specific crop.

## Larger Header review — r8, pending approval

The owner requested an intermediate size between the cropped r4 layout and
the compact r7 layout. English r8 increases the devices and free-sync line to
65% of the original scale, versus r7's 45% (44% larger). The headline grows
from 23.4 to 31.2 logical points. Reposition the Mac display, note and iPhone
to keep essential content central, retaining the landscape hardware and the
projected keyboard/trackpad. Render with `--mid-scale-review` using r4's native
inputs. This new layout is limited to an English thumbnail until approved;
r7 remains the delivered final. Preserve both iterations and review the full
canvas and template safe-area detail before exporting or localizing.

English r9 keeps r8's sizes and moves the iPhone 15 logical points right and
the MacBook hardware 30 points right, giving the headline more clearance.
The Mac note shifts four points right overall by moving slightly left within
the screen, so it remains inside the template safe area. Retain the projected
keyboard and trackpad. Render with `--spacing-review`; English thumbnail
approval is required before full export. R7 remains the delivered final.

The owner approved r9 on 27 October 2026. It supersedes r7 in the standing
delivery folder. All four localized 3840 × 1646 Headers have been exported
from the same native r4 inputs and reviewed both in full and within the
template safe area. The English composition matches the approved r9
thumbnail. Localized captions use a narrower column and a slightly smaller
headline font to preserve clearance from the iPhone; wording is unchanged.
Both native checklists remain fully readable inside the template safe area.
The projected keyboard, trackpad and device shadows are retained.

Use `--spacing-review --full` for the approved r9 compositor layout, or pass
the r9 approved thumbnail to `export-marketing-ios-header.py`; the helper
chooses the appropriate approved layout. R8 remains a historical draft.
R7 full exports and the previous delivery bytes are preserved outside the
upload folder. No new capture, idle-screen session, App Store upload or
submission was required. Verify the updated Header in App Store Connect's
own device preview before publishing there.

## Caption-only Header review — r10, pending approval

The owner requested larger display copy moved slightly left while keeping
the device visuals exactly as in r9. English r10 scales only the headline,
free-sync line and cloud symbol by 1.15, anchored at the caption's top-left,
then moves that block 18 logical points left. The devices, native content,
wallpaper, hardware geometry and shadows retain r9 positions and sizes.
Render with `--text-review` and r4's saved native inputs; no capture is needed.

The requested left shift extends beyond the template's conservative safe
area, and its detail crop visibly demonstrates the text clipping. Record
`captionInsideHeaderSafeArea: false` and do not claim this draft passes that
placement check. This mode permits only an English review thumbnail; full
export and localization remain blocked until the composition is agreed.
R9 stays in the standing final folder. Preserve r10's full-canvas review and
safe-area detail separately from upload files.

English r11 makes the difference more visible after the owner found r10 too
subtle. Scale the caption block to 1.5× r9 (headline 46.8 logical points,
free-sync text 20.475), move it 138 logical points left of r9, and raise it
27 points to balance the larger block. The longest headline line now ends
roughly 60 points before the iPhone, compared with roughly 20 in r10. Device
positions, sizes, native content and shadows remain unchanged from r9.
Render using `--large-text-review`; preserve r10. This remains an English
thumbnail awaiting approval, with template-safe-area text clipping explicitly
recorded. R9 is still the delivered final; no new capture is needed.

The owner approved r11 on 27 October 2026 after the caption's position outside
the conservative template safe area was disclosed. This explicit design
choice is retained for all four locales. It is not a passed text-safe-area
check: `captionInsideHeaderSafeArea` and
`essentialContentInsideHeaderSafeArea` remain false, while the export record
marks `captionOutsideTemplateSafeAreaApproved: true`. The device layouts and
their native content remain unchanged from r9. The package audit retains
the Mac-note bounds check and records the caption exception in its manifest.

All four full Headers have been visually reviewed and delivered at
3840 × 1646 as opaque 8-bit sRGB PNGs. English matches the approved thumbnail;
Spanish, French and Simplified Chinese retain the localized r9 column and
font fitting while applying the same 1.5× caption scale and offsets. The
standing final folder now contains r11 Headers and the unchanged 36 other
assets. R9 full exports, previous delivery bytes, and r10/r11 review material
remain preserved outside it. Use `--large-text-review --full`, or pass the r11
thumbnail to the Header exporter. App Store Connect upload and submission
have not been performed.

Sources checked 26 October 2026:
- https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications
- https://developer.apple.com/app-store/asset-best-practices/

## Medium screenshot export

The approved 1320 × 2868 large-display compositions are preserved. Re-export
the six screenshots in all four locales as 1206 × 2622 medium-display images
with `Scripts/reexport-marketing-ios-screenshots.py --output <new-iteration>`.
The source view is rendered directly at the new scale, without changing its
layout or recapturing native app views. Uniform scaling fills the new canvas;
the aspect-ratio difference trims less than 0.4 output pixels at each side.
Inspect all localized review images, then rerun with `--publish` to update the
standing final folder and preserve the replaced files in delivery history.
