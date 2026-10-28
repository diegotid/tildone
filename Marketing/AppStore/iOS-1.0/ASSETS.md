# iPhone App Store visual assets

Lineup approved on 25 October 2026. Work on one asset at a time: thumbnail
approval precedes its full-resolution implementation and localization. Preserve
the existing Mac assets, stories, outputs and metadata.

The user's subsequent overnight instruction authorizes completing both previews
and all six screenshots in all four languages without further individual
thumbnail approvals, using the approved six-color composition. This supersedes
the approval checkpoints above for this production run.

## Approved lineup

| Asset | English headline | Content |
| --- | --- | --- |
| Preview 1 | From thought to done. | Fullscreen capture/completion and list, grid, deck; early free Mac–iPhone iCloud sync callout. |
| Preview 2 | Make the big thing feel smaller. | Fullscreen subtasks, memo and text styling; optional one-time Pro disclosure. |
| Screenshot 1 | Get it off your mind. | Ordinary checklist and completion state. |
| Screenshot 2 | On iPhone. On Mac. In sync. | Matching native notes; free iCloud sync; same Apple Account required. |
| Screenshot 3 | See your plans your way. | Native grid and everyday plans. |
| Screenshot 4 | Find your next thing. | Native search in list view. |
| Screenshot 5 | Small steps. Real progress. | Subtasks with progress; optional one-time Pro. |
| Screenshot 6 | Give a thought its own space. | Memo and text styling; one Pro purchase for Mac and iPhone, no subscription. |

## Visual direction

Screenshot reference: the inner ChatGPT App Store artwork supplied by the user,
not its surrounding iPhone Mirroring window or App Store chrome. Short centered
headlines, generous spacing, light backgrounds with soft gradients from the
shipping six-color note palette, and a large translucent white phone bezel.
The user approved the first composition and requested all six colors in each
background, replacing the initial one-accent-per-screenshot direction. Use
yellow, green, blue, orange, pink and purple in soft blended areas around the
phone, with a light headline area.
Hide hardware notch/Dynamic Island. Preserve the actual app UI and its geometry.
Previews show fullscreen native UI, with no marketing device frame.

Capture only real SwiftUI components with synthetic data and disabled live
transport. Lists, layouts, colors, search and iCloud sync are free; subtasks,
memos and text styling are optional Pro. Localize each approved full asset,
including mock contents and purchase disclosures, into en-US, es-ES, fr-FR and
zh-Hans. Warn before any capture requires the screen to remain idle.

## Completed production set — 25 October 2026

All 32 main assets are complete: 24 screenshots and eight 30-second previews.
Each of en-US, es-ES, fr-FR and zh-Hans has six screenshots and both previews.
The first screenshot contains four ordinary tasks as requested. Screenshot 3
shows four complete native note cards without clipped bottom rows.

`Marketing/Preview/Output/iOS-App-Store/` contains the finished media and
`final-validation.json`. The review package adds per-language folders, preview
posters, contact sheets, native source captures and their verification records.
`Scripts/package-marketing-ios-assets.py` audits and packages these files.

Screenshots are 1320 × 2868, opaque 8-bit sRGB PNGs. Previews are fullscreen
886 × 1920, exactly 30 seconds at 30 fps, H.264 High with silent stereo AAC.
The free preview shows list, grid and deck, task entry and completion, with a
free Mac iCloud sync footer throughout. The Pro preview shows subtasks,
collapsing and a styled single memo, with an optional one-time purchase footer
throughout. Screenshots 5 and 6 also disclose optional Pro.

## Native capture and isolation

The private simulator-only capture target uses the real `NotesListView`,
`ChecklistView`, `TaskRow`, grid/deck and `SingleMemoTextView` components with
an in-memory repository. Capture hooks are gated by `MARKETING_CAPTURE`.
Live CloudKit and StoreKit are disabled; Pro examples are seeded mock content.
No physical iPhone or user data was used. Sync is illustrated using matching
native content and an existing native Mac capture, rather than measured by a
live network transaction.

The original overnight worker used prepared private builds and a shared,
task-owned simulator. The current `Scripts/run-marketing-ios-suite.py` builds
its own app, runs all eight stories in four locales, and uses a fresh disposable
simulator per capture. It provides a read-only plan/input check, requires a new
iteration folder, preserves prior finals, and captures both screenshot-3 layouts.
See `Marketing/README.md` for clean-checkout prerequisites and commands.
No screen-idle session or foreground simulator window is needed for iPhone capture.
The original overnight run stopped when disk space ran out; all missing assets
were subsequently captured, repaired and verified after space was available.

The marketing renderer adds captions, the six-color background and translucent
bezel around uniformly scaled native pixels. It hides the hardware island with
an empty native status-strip backdrop. The Mac inset is cropped from an existing
native Mac export. Product controls, titles and tasks are not redrawn.

## Validation

All locales were reviewed through screenshot contact sheets and sampled preview
frames. Packaging checks dimensions, screenshot depth/opacity, video duration,
frame count, codecs, source/output hashes, mock-data proofs and free/Pro tiers.
The private capture app and ordinary non-marketing iOS app both build.
All 32 existing Mac media hashes match the pre-work baseline. Existing Mac
assets and App Store metadata were preserved. No submission was made.

The approved 440 × 956 first thumbnail remains under
`Marketing/Preview/Output/iOS/screenshots/01/en-US/`; finished upload files are
in `iOS-App-Store`, separate from this design proof.

## Requested revision — 25 October 2026

Process in order: preview 1, preview 2, screenshot 2, screenshot 3, screenshot 6.
Preview 1 leads with the Mac companion benefit and uses two native color groups:
personal plans in green, work/reference notes in blue. Retain the free sync footer.
Preview 2 will separate black Permanent Marker memos from a task list with
selective multicolor words, bold and italic, and explicitly mention free Mac sync.
Screenshot 2 will replace the floating inset with a dark translucent MacBook Pro
top-screen crop in the lower two fifths, visible notch and a note right of center.
Screenshot 3 will group personal and work notes by color. Screenshot 6 will use
black Permanent Marker memo text. Keep all six background colors. Produce native
review thumbnails before replacing approved full exports and localizing revisions.

Preview 1 storyboard approved with one adjustment: Dinner plans is the sole
yellow note (meal planning); Weekend, Home and Travel remain green, Work and
Research remain blue. Export this approved revision in all four languages.

The approved preview 1 palette is three green personal notes, two blue work/
reference notes and one yellow Dinner plans note. Preview 2's draft now uses
a dedicated styled-checklist scene with partial-word blue/bold, green/italic
and purple/bold-italic spans. Its separate memo is plain black text with the
Permanent Marker font. Free Mac iCloud sync has its own caption while the
optional one-time Pro footer stays visible. The remaining screenshot changes
are queued for their own thumbnail reviews.

Capture recovery: after Simulator's background service stopped responding,
only the task's stalled device was removed. `--fresh-device` now supports an
independent disposable simulator per capture. Private iOS fixtures suppress
the software keyboard themselves and no longer need simulator-wide keyboard
tutorial preference writes. Native verification records the owned simulator
UUID for targeted cleanup.

Preview 1's approved yellow-note revision is now exported and verified in all
four locales. The French reference-note title is “Références” so it fits the
shipping card. Current full media lives in `iOS-App-Store`; the dedicated
`Tildone-iOS-preview-1-approved.zip` includes all four previews, posters and
native sources. Preview 2 remains a draft pending its thumbnail approval.
Screenshots 2, 3 and 6 remain queued for individual thumbnail review.

Preview 2's English native storyboard is ready for approval. It samples the
settled memo scene at 00:28, after the native navigation transition finishes.
Its task-list words use blue/bold, green/italic and purple/bold-italic; the
Permanent Marker memo has default black text and no colored spans. The revised
full preview 2 exports have not replaced the previously approved media.

## Final delivery folder — current standing instruction

Keep `/tmp/Tildone-iPhone-App-Store-Finals` as the single delivery destination.
The user explicitly chose to leave it there instead of moving it to Desktop.
After every finalized iteration, copy the latest upload media to that same
folder under the same filenames. Keep all previous per-iteration assets in
their existing source/revision folders. Do not put drafts, thumbnails, posters,
source captures, ZIPs, guides or manifests in the delivery folder.

The destination contains 24 final screenshots and eight final previews,
organized by en-US, es-ES, fr-FR and zh-Hans, with Screenshots and Previews
subfolders. Link new delivered assets directly to these local filesystem paths
and label final exports and review drafts clearly; do not substitute Library
links for the user's local file links.

`Scripts/publish-marketing-ios-finals.py` defaults to this destination. It reads
canonical verified export records, checks source hashes, skips unchanged files
and updates changed files atomically. Before replacing a delivery copy, it also
preserves that exact prior copy under `iOS/revisions/delivery-history/` without
deleting existing iteration folders. `Scripts/package-marketing-ios-assets.py`
refreshes the delivery folder automatically after successful final packaging.
The source of truth remains the per-asset final export records, never a draft
review directory.

Current revision state: Preview 1's yellow-note revision is finalized in all
four languages. Preview 2's revised English storyboard awaits approval; its
new full exports and screenshot 2, 3 and 6 revisions are not finalized yet.
The delivery folder retains their latest earlier final exports until replaced.

## Current requested iteration (r4)

Finalize both previews and screenshots 2, 3 and 6 in all four languages.
Previews use 64px main captions and 40px disclosures over a bottom white wash:
transparent at two thirds of screen height and opaque over the search bar.
The green deck pans through all three real native cards. Single memos use
Permanent Marker with default black text and only the word “space” in blue.
The concise localized memo “Make space.” fits above the caption wash.
The purple checklist styles only the selected ideas/what matters/quiet words
in blue-bold, green-italic and purple-bold-italic. Screenshot 3 has two green
personal notes and two blue work/reference notes. Screenshot 2 uses the top
center crop of a dark translucent MacBook Pro bezel, with a visible notch and
the native Mac note offset right, across the lower two fifths of the artwork.
Retain each previous final in its iteration folder, then refresh the fixed
final delivery folder after each completed four-language asset. Preserve Mac
assets. No live iCloud, physical iPhone or host desktop capture is involved.

## Current language gate — 26 October 2026

The user now explicitly requires en-US only until the final English versions
are agreed. This supersedes the r4 four-language render plan above. Stop any
remaining localization jobs. Continue English revisions and reviews for both
previews and screenshots 2, 3 and 6. Do not generate or replace additional
Spanish, French or Chinese iterations until the user approves the English
final versions. Preserve completed iteration files and earlier language files.
The fixed final-delivery folder remains upload-media only; label review drafts
separately and link directly to local filesystem paths.

English r4 review is complete: the two previews and screenshots 2, 3 and 6
are rendered, visually checked and copied to the fixed en-US delivery folders.
Both previews pass 30-second/900-frame verification; screenshots pass the
1320 × 2868 opaque 8-bit checks. Native proofs verify all three green carousel
front cards, the memo's single blue word with Permanent Marker, and the grid's
two green/two blue notes. All 32 Mac media hashes remain unchanged. Further
localization is explicitly on hold until the user agrees on the English finals.

## English review iteration r5 — 26 October 2026

Screenshot 2's new thumbnail uses the supplied abstract Golden Gate wallpaper
from the unchanged Mac marketing build, a tighter mask around the native Mac
note's rounded corners, and a broader shadow cast upward from the MacBook
screen onto the iPhone. Review: `/tmp/Tildone-iOS-r5-review/screenshot-02-en-US-thumbnail.png`.
This is a design proof awaiting approval; no final upload media has been replaced.

Next, preview 2 should use this same MacBook screen in its opening four seconds,
without the optional Pro subtitle. Introduce the Mac companion relationship and
free iCloud sync, then zoom the MacBook in while moving it down beyond the bottom
edge before “Make the big thing feel smaller.” begins. Remove the Pro purchase
subtitle during the later free iCloud sync claim as well. Paid feature scenes
retain the optional one-time Pro disclosure. Continue en-US only until approval.

The user approved screenshot 2's Golden Gate treatment. Its 1320 × 2868
English final is now verified and delivered to the fixed final folder; the
previous final remains under r5's `previous-final` and delivery history.
All 32 Mac media hashes are unchanged.

Preview 2's English review is ready at
`/tmp/Tildone-iOS-r5-review/preview-02-full-review.mp4`, with a short motion proof
at `/tmp/Tildone-iOS-r5-review/preview-02-opening.mp4`. It opens with the actual
matching Weekend checklist on iPhone and Mac, using the native screenshot 2
capture and the same approved SwiftUI MacBook artwork. The opening white wash
keeps both the headline and free-sync subtitle readable. From 3.0 to 3.9 seconds
the MacBook zooms in and moves down out of frame, before the Pro feature title
at 4 seconds. The optional purchase subtitle appears only during paid-feature
scenes (4–18 and 22–30 seconds), and is absent from the free-sync claim at
18–22 seconds. The review passes 30-second/900-frame and Rec.709 checks.
It awaits preview approval and has not replaced the final preview. Other
languages remain on hold. Open review files directly on the Mac because the
app's sandbox links have repeatedly failed for the user; include plain paths.

## English preview 2 review r6 — 26 October 2026

The opening headline and free-sync subtitle now use white text, with the same
64/40px fonts and 150px bottom padding as the next caption pair. They are
composited into the MacBook desktop before a single shared zoom-and-downward
transform. The MacBook sits slightly higher in this video crop so the native
note clears the bottom copy; the approved screenshot remains unchanged.
A restrained dark wash makes the white copy readable against Golden Gate.
The next black title and Pro subtitle are present behind the display from the
start and are revealed by its exit. The exit runs from 2.75–4 seconds, with
a stronger zoom from 1× to 1.9×. The actual native Weekend and Seaside task
captures crossfade over 3.05–3.6 seconds during this movement.

Review: `/tmp/Tildone-iOS-r6-review/preview-02-full-review.mp4`; short motion
proof: `/tmp/Tildone-iOS-r6-review/preview-02-opening.mp4`. Keep r5's review
in its existing revision folder. This en-US draft awaits approval; no final
preview or localized assets are replaced by this review render.

The user approved preview 2 r6 as final. Its verified English 30-second video
and poster now replace the canonical English export, and the final MP4 is
copied to the standing delivery folder. The previous final and each prior
review remain preserved. Other languages remain on hold.

## Screenshot 3 two-phone review r7 — 26 October 2026

Use the current real grid capture at the upper left, below the subtitle with
a margin, and a second real phone capture with the same four mock notes in
deck layout at the lower right, in front. Keep matching 24pt outside margins,
translucent phone bezels, hidden hardware islands and all six background
colors. The mock notes retain two colors: green personal notes and blue work
notes. Capture a private screenshot 3 deck variant via the isolated
`MarketingOverviewLayout` bundle flag; do not change shipping UI. First render
and directly open an English thumbnail for approval before final export.

The r7 English two-phone thumbnail is ready at
`/tmp/Tildone-iOS-r7-review/screenshot-03-en-US-thumbnail.png` and opened directly
in Preview. The private capture app builds successfully; its disposable
simulator was removed after capture. The native deck proof exactly matches
the grid's four note snapshots, including tasks, completion and colors.
The grid phone starts at (24, 208) and the foreground deck phone retains 24pt
right/bottom margins on the 440 × 956 proof canvas. Screenshot 2's unchanged
composition remains pixel-identical after extracting the shared phone artwork.
All 32 Mac media hashes remain unchanged. Await thumbnail approval before
replacing screenshot 3's final or localizing the new composition.

## English iteration r8 — 26 October 2026

Screenshot 3 now uses two 270pt-wide phones instead of 230pt on the 440pt
canvas, retaining 24pt outside margins. The front deck phone overlaps 148pt
of the grid phone instead of 68pt; the grid's left column and upper right
card remain visible. Thumbnail: `/tmp/Tildone-iOS-r8-review/screenshot-03-en-US-thumbnail.png`.
Keep r7's proof unchanged; await approval before updating the final screenshot.

Preview 1 now seeds the private fixture in this deterministic overview order:
Weekend, Work, Research, Dinner plans, Home, Travel. All fixture task edits
share a timestamp, so stable synthetic note IDs supply the shipping sort's
tie-break order. This places the sole yellow note fourth in both native list
and grid, while preserving the green carousel's Weekend/Home/Travel order.
Capture validation checks the yellow note at index 3 in both overview scenes,
the six-note palette, all three green fronts and the real task addition.
Only English is captured/rendered for review; no final media changes yet.

Both r8 reviews are ready. Screenshot 3's larger overlapping-phone thumbnail
was opened in Preview. Preview 1's complete English review was opened in
QuickTime at `/tmp/Tildone-iOS-r8-review/preview-01-full-review.mp4`.
Native capture verifies the exact six-note overview order in the list and grid,
and the rendered grid visibly shows yellow Dinner plans as the fourth card.
The actual green carousel still fronts Weekend, Home and Travel in that order.
The private capture build succeeds; video export passes 30-second/900-frame
checks. All 32 final-delivery assets and 32 Mac media hashes remain unchanged.
Await English review approval before replacing either final or localizing.

## Screenshot 3 preview-matched mock content r9 — 26 October 2026

The user now requests the same six-note mock set and native grid/deck layouts
seen around 00:09 of preview 1. This supersedes screenshot 3's earlier four-note,
two-color fixture. Retain the larger overlapping 270pt phone composition.
Use the current preview 1 r8 native recording before marketing overlays:
grid at 8.8 seconds, immediately before the layout switch; deck at 9.8 seconds,
settled after the switch and before its first pan. Both contain Weekend, Work,
Research, Dinner plans, Home and Travel in the overview, with three green notes,
two blue and one yellow. The green deck contains Weekend, Home and Travel.

The frames are actual production SwiftUI pixels extracted from the verified
native recording, without drawing cards or controls. Native frame proofs keep
the original event data, recording/event hashes, capture-proof paths and exact
sample times. Sample VFR recording frames using tpad/fps from the start before
output seeking, not input seeking. For eventual localization, use each approved
localized preview recording and equivalent stable layout frames.

English thumbnail: `/tmp/Tildone-iOS-r9-review/screenshot-03-en-US-thumbnail.png`.
Prior reviews remain in r7/r8. This thumbnail awaits approval; final upload
assets and localized files remain unchanged.

## Screenshot 3 three visible colors r10 — 26 October 2026

The user replaces Research with Dinner plans in the visible grid and makes
Work the only blue note. Screenshot 3 now has five notes in fixed order:
Weekend (green), Work (blue), Dinner plans (yellow), Home (green), Travel
(green). Dinner plans occupies the former Research slot in the grid's left
column. The three green notes form the first shipping carousel; the sole
blue Work and sole yellow Dinner plans share the native singleton-color
carousel in the second row. This fixture change is specific to screenshot 3;
preview 1's six-note content remains as reviewed in r8.

The private screenshot capture app supports `--both-layouts` for this story:
capture its actual grid, then switch the same model/session to deck and capture
it. The helper verifies equal snapshots, exactly three green/one blue/one
yellow notes and Dinner plans at index 2. Keep the 270pt overlapping phones,
24pt margins, native UI, hidden hardware islands and six-color background.
Prepare only the English thumbnail for approval; preserve prior reviews/finals.

The r10 English thumbnail is ready at
`/tmp/Tildone-iOS-r10-review/screenshot-03-en-US-thumbnail.png`. Both native
captures match exactly and show the requested palette/order. The actual green
carousel reports Weekend as its front card; Home and Travel are behind it.
The deck's second row visibly combines blue Work with yellow Dinner plans.
The grid's exposed left column shows green Weekend and yellow Dinner plans,
with blue Work visible in the upper right. The private build succeeds and its
isolated simulator is cleaned up. All 32 current upload files and 32 Mac media
hashes remain unchanged. Await thumbnail approval before final export.

## Consolidation and localization authorized — r11, 26 October 2026

The user approved the latest English changes and explicitly requested the
approved set consolidated into the standing target folder, then replicated in
Spanish, French and Simplified Chinese. This lifts the English-only gate above.
No further per-language approval is required for this production pass.

The English set now uses preview 1 r8 (Dinner plans fourth), preview 2 r6
(shared white-caption/MacBook zoom and native crossfade), screenshot 2 r5
(Golden Gate, masked native note corners, stronger shadow), screenshot 3 r10
(large overlapping phones, five notes, green carousel plus blue/yellow row),
and screenshot 6 r4 (Permanent Marker, only one word blue). Screenshots 1, 4
and 5 retain their latest approved compositions. Keep historical revisions and
update only final PNG/MP4 files in `/tmp/Tildone-iPhone-App-Store-Finals`.

### r11 complete

The approved English set is consolidated and all three localized sets are
complete. The standing final folder contains exactly 24 screenshots and eight
previews, eight upload files per language, with no drafts or review material.
Fifteen localized assets were updated; screenshots 1, 4 and 5 retain their
already matching approved localized versions. All prior revision media remains
preserved, including each overwritten delivery copy in delivery history.

Native proofs verify Dinner plans fourth in preview 1, all three green carousel
fronts, preview 2's shared MacBook/caption transform and native list crossfade,
selective styled words, the memo font selection and one blue word, and screenshot
3's matching five-note grid/deck captures with blue/yellow in the second row.
Preview 2's free-sync scenes have no optional purchase subtitle. All main files
pass dimensions/format/source-hash checks; previews pass 30 seconds, 900 frames,
stereo AAC and Rec.709 checks. All language screenshot contact sheets, localized
preview storyboards and key transition/free-sync/memo frames were reviewed.

Two localized fit refinements were applied before final delivery: Spanish
Research uses the concise mock title “Estudio”, avoiding a dangling letter;
the Chinese day-view and free-sync captions use shorter natural wording.
Earlier versions of those renders remain under r11 and its fit-repair history.
The approved English media hashes and all 32 existing Mac media hashes are
unchanged. No physical iPhone, live iCloud, purchase flow or screen-idle capture
was used. The isolated simulators were cleaned up. No submission was made.

Authoritative audit: `Marketing/Preview/Output/iOS/revisions/r11/final-validation.json`.
The review/source package is under r11/package, outside the upload folder.
`Scripts/update-marketing-ios-localizations.py` resumes verified current records,
including fit repairs, without replacing them with an earlier render.

## Medium display compatibility — r12, 26 October 2026

All 24 screenshots have been re-rendered at 1206 × 2622 for the required
iPhone with Dynamic Island medium-display slot. The user approved this format
adaptation. Saved native captures, mock content and the approved composition
were reused; no app capture or layout redesign was needed. The renderer uses
uniform scaling with less than 0.4 output pixels cropped from each side.

All four localized contact sheets were reviewed. All 24 PNGs passed 8-bit RGB,
opaque sRGB and exact-dimension checks, and the complete 32-asset package audit
passed. The eight previews and all 32 Mac media files retain their hashes.
The standing delivery folder now contains the medium screenshots. Original
large outputs remain in r11, r12-medium/previous-final and delivery history;
the portable original release hashes are in release-manifest-large.json.


## Original mesh wallpaper refresh — 28 October 2026

After reviewing a native side-by-side draft, the owner approved replacing Golden Gate in every affected iPhone asset. Screenshot 2, preview 2, Header and Search Results were refreshed in en-US, es-ES, fr-FR and zh-Hans: 16 replacements. The other 24 files in the current 40-file upload set remain byte-identical. The light outer iPhone background, native phone footage, captions, hardware/layout geometry, animation and Pro disclosure intervals are retained. Preview 2's four poster frames were updated too.

The existing native SwiftUI compositors render the approved mesh master using separately selected native Mac inputs. Four native five-task Mac Header notes were recaptured with the established background-only path; the retained phone captures are unchanged. Original Golden Gate input folders and the previous complete iPhone delivery are preserved. `activeIPhoneWallpaper` in `Marketing/Preview/Inputs/manifest.json` selects `Marketing/Preview/Output/iOS/active-mac-inputs/`. The historical `GoldenGate.png` resource name remains an alias for the selected bitmap.

All 16 replacements passed format/integrity checks and localized visual scene review; the four complete videos decoded without errors. Header retains the previously accepted r11 composition, including its explicitly owner-accepted caption extension outside the conservative template safe area. This refresh does not claim that exception is resolved or that App Store Connect placement cropping is newly qualified.

The updated 40-file current delivery and audit are under the ignored iPhone wallpaper refresh iteration. The portable release manifest records new hashes and the 24 unchanged files. The historical large-display manifest remains unchanged. No customer app, data store, CloudKit operation, signing change, App Store upload or submission is part of this media refresh.


## Large-display wallpaper correction — 28 October 2026

The wallpaper refresh also provides screenshot 2 at 1320 × 2868 for en-US, es-ES, fr-FR and zh-Hans. These four additional native-compositor renders retain the approved large layout and current mesh inputs. Format checks and localized visual review passed. The other twenty large screenshots keep their original approved hashes. Only screenshot 2 needs replacing in this size slot; previews are shared with the updated current delivery. The ignored wallpaper refresh iteration includes a separate four-file large-display folder and ZIP, complete reference set, new local manifest and the preserved historical manifest. The tracked release-manifest-large.json remains the original historical record. No new device capture or App Store action occurred.
