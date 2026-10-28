# macOS App Store preview

## Mac-only wallpaper refresh — 28 October 2026

The owner approved an original smoky slate, teal, lavender and peach mesh
wallpaper, `Inputs/Tildone-Mesh-20261028.png`, to replace Golden Gate in the
Mac's six screenshots and two previews across all four locales. Its provenance
and hash are in `Inputs/manifest.json` under `activeMacWallpaper`. The historical
external Golden Gate record is retained. The private resource remains named
`GoldenGate.png` for compatibility; its content is the selected input bitmap.
The owner excluded iPhone artwork from this Mac refresh. The original iPhone
media and prerequisites remain unchanged.

Use the existing unsigned private Mac builder with `--wallpaper` pointing to
the new input. Then `Scripts/refresh-marketing-mac-wallpaper.py --phase prepare`
stages independent story/locale app copies under a new ignored `--output`
iteration, with `--app-template` pointing to that built app and `--wallpaper`
to the original mesh bitmap. Its `capture`, `export` and `audit` phases resume
from that plan. Only `capture` needs an idle GUI desktop; `export` and `audit`
run in the background. The continuous batch counts down before its first scene,
captures genuine native note UI, and retains screenshot 6's required visible
rectangle capture. Announce the foreground interval before starting and tell
the owner when native capture finishes or stops.

`record-marketing-preview.py --destination` keeps new screenshots out of the
standing delivery folder until visual review. Existing behavior is unchanged
when the option is absent. Its opt-in `--retained-phone-inputs` accepts only a
manifest pinning the original verified phone proof and image/video files for
the exact story and locale. This reuses the approved native continuity footage
without claiming a fresh simulator capture or changing the older capture
helper fingerprint. The batch copies those inputs into its own iteration,
verifies native/mock-data/cloud-off flags and the existing composition checks,
and rejects any file-hash mismatch before a GUI launch. Without that explicit
manifest, the original app/helper cache check and recapture behavior remain.

Use a separate ignored output iteration and pin existing exports with baseline
manifests before starting. New Mac exports are staged under `ready-for-review/`;
capture completion is not visual approval or an App Store upload. Inspect all 24 screenshots, the native
privacy menu and transparency examples, and the eight complete video timelines
before refreshing the final delivery folder. Preserve replaced files and
record their new hashes. No customer app, live store, CloudKit, StoreKit,
distribution signing, App Store upload or submission is involved.

## Screenshot 1: one thing at a time

Build with `--story screenshot-1 --output Marketing/Preview/Output/screenshots/01/en-US`
and `--derived-data /tmp/TildoneScreenshot1DerivedData`. Its independent build and
launcher retain screenshot 3 and both approved previews.
Headline: “One thing at a time.” Subtitle: “A clearer desktop. Your other lists
still close.” A prominent yellow “Finish the proposal” checklist sits toward the
center-right: “Check the final figures” is complete; “Add the summary” and “Send
to Maya” remain pending. Blue Home and pink Weekend notes are minimized using
their actual native minimize controls and positioned along the bottom-left edge.
Both show their real titles/progress with the supported 1.5× compact-note setting.
Revision 2 fits the expanded note's width to the native title/task font metrics
plus the usual padding and checkbox space. Its height and position are retained.
The expanded note uses the supported 24-point task text preference. All three
notes contain ordinary flat checklists. No Pro content, mock background app or
Pro label is featured. All six new strings have en/es/fr/zh-Hans entries.
The native capture emits an opaque 2880 × 1800 PNG and verifies three windows,
one expanded note, two compact notes, and one completed task in the main list.
Produce the English image for review before creating another asset.

The approved revision 2 app can be copied to independent
`Output/screenshots/01/{es-ES,fr-FR,zh-Hans}/` directories with each copy's
`MarketingLocale` and output path set accordingly. The native width fitting
measures the localized title and tasks at the same text sizes. Capture the
three copies with `Scripts/record-marketing-localizations.py --story screenshot-1
--apps ...` from the GUI session and wait for `ALL SCREENSHOTS FINISHED`.
The batch copies verified PNGs to `Output/macOS-App-Store/` and records
`screenshot-1-localizations-result.json`. Screenshot 3 uses a separate batch.

## Screenshot 2: pick up where you left off

Build the static iPhone fixture with `Scripts/build-marketing-phone.py --story
screenshot-2 --output Marketing/Preview/Output/screenshots/02/en-US`, then build
the Mac app with `--story screenshot-2`, that same output directory and
`--derived-data /tmp/TildoneScreenshot2DerivedData`. The GUI launcher first opens
the real iPhone NotesDeckView in a new, disposable simulator. Revision 3 selects
the shipping Deck overview layout before presentation and seeds four notes: two
yellow (Dinner plans, Shopping), two blue (Home, Weekend). Each color forms its
own native deck. Dinner plans and Home lead the decks; each deck's second card
remains partly overlapped, as in the shipping app. No card sizing or scrolling
behavior is changed for marketing.

Dinner plans has three tasks (Confirm the guests completed, Pick up fresh pasta,
Bring dessert); Shopping has Coffee beans and Fresh fruit; Home has Call the
electrician completed and Pick up the parcel; Weekend has Choose a walking route
and Check the train times. Capture-only geometry observers verify that both
front-card titles and their complete task previews fit the native scroll
viewport. The bottom of the second card may extend below the viewport; this is
recorded in the proof rather than concealed. The still has no keyboard and a
connected mock cloud indicator. Only the newly created simulator is shut down
and deleted. The Mac capture independently creates the same localized fixtures
and checks every note's title, color, task order and completion state against
the verified phone data. Both repositories are in-memory; no CloudKit transport
or customer store is used.

Headline: “Pick up where you left off.” Subtitle: “Your plans stay up to date,
wherever you are.” The approved thumbnail becomes a scattered native desktop:
Weekend upper left, Dinner plans in the center, Shopping lower left, and Home
below Dinner plans. Home is explicitly ordered above Dinner plans, overlapping
its lower margin by 20 canvas points. The group stays close to the bottom-left
corner. Native content remains at 1.1×; widths fit localized text, capped at 390
points. Wider translations move Dinner plans and Home right only enough to
keep Weekend clear. AppKit minimum-size rounding retains the overlap and a
24-point minimum bottom margin for Home.

“Same iCloud account” and the cloud symbol now occupy a centered pill below the
subtitle, matching screenshot 3's 19-point semibold text, capsule padding and
14% white fill. The iPhone's top stays at canvas y=232, with left edge x=900.
The fixture measures the real bottom UISearchTextField/UISearchBar in window
coordinates and records a crop line two native points above it. The entire
phone screen and bezel are uniformly enlarged until that line meets the canvas
bottom. Composition revision 4 adds a further 12 source-screen points of
clearance because UIKit field/bar bounds exclude the translucent outer capsule
and shadow. The existing native phone stills are reused, and both deck title/task
rectangles are independently checked against the adjusted crop. The lower phone extends off-canvas: the search box and bottom bezel
are not visible, while both decks' full titles/task previews must remain above
the crop. The app UI and its scroll position are unchanged.

Build each target once, then stage private app copies for en-US, es-ES, fr-FR,
and zh-Hans with locale-specific MarketingLocale, output and phone paths. Use
`record-marketing-localizations.py --story screenshot-2 --apps ...` to capture
all four: it prepares every isolated phone first (other apps remain usable),
then captures the four Mac canvases after the first 10-second warning. Leave
the screen idle until ALL SCREENSHOTS FINISHED. All compiled fixture and header
translations are verified before handoff; capture checks note/color/task state,
window ordering/overlap, and the search crop in addition to opaque 2880 × 1800 PNG
format. Outputs go to each locale folder and Output/macOS-App-Store. No background
app, Pro content, customer stores or CloudKit transport are involved.

## Screenshot 3: small steps and a thought to keep

Recommended display position: third screenshot, fifth asset after the two
previews and two screenshots establishing the free experience. Production order
is independent of display order.

Build with `--story screenshot-3 --output Marketing/Preview/Output/screenshots/03/en-US`
and a separate `--derived-data /tmp/TildoneScreenshotDerivedData` to retain the
approved preview app. Run the resulting private app with the GUI-session
`Scripts/record-marketing-preview.py --app /path/to/TildonePreviewStudio.app`.
This mode captures one opaque sRGB PNG at 2880 × 1800, rather than a video.
It uses a 1440 × 900 point canvas, the real expanded SwiftUI note components
at their native content scale in two floating windows: a simple checklist with
one level of subtasks and a separate single memo. Revision 6 tightens the yellow
checklist to 340 × 405 points on the left and reduces the memo to 255 × 270 points
near the bottom center. The real memo component uses a capture-only typography
override: 95% of its calculated fitted font size, up from the normal 60% (about
58% larger). The override is compiled only with `MARKETING_CAPTURE` and applied
only to screenshot 3. Normal app builds and the previews retain their sizing.
The yellow note is “Seaside getaway”: under “Plan the journey,” the completed
“Receive train tickets” subtask corresponds to Mail's “Your tickets are ready”
message. Station directions, packing and a coastal walk remain pending.
A subdued native mock Mail window (490 × 355 points) sits to the right and above
the memo, which overlaps it. Mail is active at capture time; the notes keep their
floating presentation above it. Mail is attached before the notes and becomes
key without being brought to the front. The capture checks actual AppKit window
order before writing the image and fails if either note is behind Mail.
The approved previews retain their layout.
The headline is “Make the big thing feel smaller.” and the subtitle is
“Small steps for your plans. A place for your thoughts.” Revision 7 replaces the
feature label with “Tildone Pro · One-time purchase” in the existing pill,
retaining its position, typography and padding. Spanish: “Tildone Pro · Pago
único”; French: “Tildone Pro · Achat unique”; Simplified Chinese: “Tildone Pro ·
一次性购买”. The scene, note contents, memo font fitting and Mail stacking are
unchanged from revision 6. Existing Pro content is
seeded in the explicitly in-memory repository; no StoreKit purchase is mocked
or started. All copy has English, Spanish, French and Simplified Chinese
entries. Produce the English composition for review before proceeding to
another screenshot.
Only the private process and its child windows are captured. The runner checks
the PNG's actual RGB color type and dimensions, two notes, a single memo and a
maximum subtask depth of one, the active mock Mail window, and the floating memo
overlap, then copies it to the App Store output folder.
No keyboard/cursor, completion animation or minimized note is
part of this composition.

Stage independent copies of the same built app under
`Output/screenshots/03/{en-US,es-ES,fr-FR,zh-Hans}/`, retaining all bundled
localizations and setting each copy's `MarketingLocale` and output directory.
Run `Scripts/record-marketing-localizations.py --story screenshot-3 --apps ...`
from the GUI session. The all-language batch captures four native PNGs in
sequence, checks revision 7, the localized purchase disclosure and the existing
typography/stacking evidence, and copies all four to `Output/macOS-App-Store/`.
The previous three-language launcher still works for localized-only runs.
Keep the screen idle after the first countdown until `ALL SCREENSHOTS FINISHED`.
No iPhone preparation is needed for screenshot 3.

Mac screenshot specifications:
https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications

## Screenshot 4: personal reminders stay discreet

Headline: “Keep your plans to yourself.” Subtitle: “Personal reminders, discreet
until you need them.” The shared pill reads “Tildone Pro · One-time purchase”.
All header, note, mock-document and existing menu labels are available in
English, Spanish, French and Simplified Chinese.

Build with `--story screenshot-4 --output Marketing/Preview/Output/screenshots/04/en-US`
and `--derived-data /tmp/TildoneScreenshot4DerivedData`. Stage locale-specific
copies of this private app under `Output/screenshots/04/{en-US,es-ES,fr-FR,zh-Hans}`.
Use `record-marketing-localizations.py --story screenshot-4 --apps ...` for all
four captures. After the first 10-second countdown, leave the screen idle until
ALL SCREENSHOTS FINISHED. No phone preparation is required.

The 1440 × 900 canvas uses the same Golden Gate wallpaper, caption typography,
pill styling and native note components as the preceding assets. The blue
“Personal” checklist sits left at (150, 180), 380 × 400 points. It contains three
synthetic tasks (Review the budget, Book the check-up, Renew the passport). The
yellow “Workshop” note at (1020, 310), at least 320 × 280 points, contains Check
the agenda (completed), Add the examples and Send the handout. Native content is
uniformly presented at 1.1×. A quiet mock TextEdit window at (765, 165), 530 × 305,
shows a fictional workshop outline behind the floating yellow note.

The private fixture seeds the blue note's existing per-note blur preference.
Both the actual Note and the actual titlebar SwiftUI privacy Menu read that
state. It does not mock a StoreKit purchase or alter customer preferences.
The real Note applies its normal 3-point blur to the entire checklist body,
including its title. Titlebar controls stay sharp. The real pointer moves out
of the note body during capture so the native hover rule does not reveal text.
A capture-only state observer verifies that the blue Note is blurred and the
yellow Note is clear. The private preference is removed on process termination.

A common-mode run-loop timer presses the existing privacy Menu's native button
(or its accessibility press action). Its actual NSMenu must report Blur Content
checked and Stay in Background unchecked. Menu labels and controls are not
recreated for the artwork. The stage capture's includeChildWindows option already
includes the related native menu. Revision 1 incorrectly overlaid a second
window capture which resolved to the owning canvas, stamping a miniature scene
over the menu. Revision 2 removed that compositing step, but its new Vision OCR
check failed inside Apple's compute engine (`e5rtError`, code 13). Revision 3
removes OCR from capture altogether. It enumerates only this process's own
popup bounds, retains the original stage pixels, and flags the exported image
for visual menu review. No additional window image is drawn. This remains a
current-process capture: no other application, display, customer store or
CloudKit transport is captured or opened.

Revision 3 proof checks both native blur states, the localized menu's checkmarks,
at least one native popup and menu state, and explicitly records that the menu
pixels still need visual review; it does not claim automated text verification.
It also checks two notes, three tasks each, one completed Workshop task, floating ordering above
TextEdit, yellow-note overlap with the document, and the localized Pro purchase
disclosure. The exported PNG is opaque
sRGB at 2880 × 1800 and is copied to `Output/macOS-App-Store/`.

## Preview 2: continuity

Build the separate sync story with `--story sync --output Marketing/Preview/Output/sync/revision-7/en-US`.
The default `--story desktop` retains preview one's composition and timeline.
Both stories support the same four capture locales.

The sync story uses two explicitly in-memory repositories, with the real domain
remote-merge operations and Mac presentation refresh. Revision 7 includes a native
iPhone video of the real `NotesListView` and `ChecklistView`, in a separate private
simulator app. It starts with one existing Home note, creates a new note through
the real navigation action, and fills its title and first task character by
character through the real SwiftUI text-field bindings. Every character is
checked in the focused native text field before the next one is entered.
Capture-only notifications invoke the existing view actions and are compiled out
of ordinary builds. In the private phone capture app, editing fields use an empty
input view to keep the software keyboard hidden while native text entry remains
active. Title submission explicitly calls the existing title-save action before
releasing focus, and the fixture waits for the model to confirm the localized title. This
retains the native title row as the field's Return action does. It does not tap the
toolbar Done action that removes that row and switches to a navigation title.
Revision 5's unsuccessful scroll/nav-bar override has been removed. The fixture
checks the title field's font, visible frame and full text width after title
submission, while typing the first task, after task submission and after the
remote update. Both title visibility and recorded keyboard-frame evidence are
required before composing the clip. The shipping app's navigation is unchanged.
The fixture injects an available/idle sync presentation so the native overview
button shows its normal unslashed cloud. Each recorded phase verifies this state
and the production symbol mapping. Only presentation is mocked; the fixture's
live CloudKit transport remains disabled.
The private phone view disables text correction for the supplied translated
mock strings, and the simulator launches the app with its language arguments
already set before UIKit starts.
No live CloudKit transport is started. The Mac checkbox and
editor use the production components. The bezel, arrows and device pills are
marketing overlays; the header/subtitles describe outcomes, with no offline scene.

Build the phone app with `python3 Scripts/build-marketing-phone.py --output
Marketing/Preview/Output/sync/revision-7/en-US` and the same `--locale` as Mac.
Run `Scripts/record-marketing-preview.command` from a GUI Finder/Terminal session.
The launcher creates its own disposable simulator, captures only that mock app,
then shuts down and deletes that simulator. It never reuses existing devices.
Before launching the fixture it marks the simulator's one-time keyboard tutorials
as already seen, so the slide-to-type introduction cannot cover the captured UI.
Once the phone video is ready, a ten-second warning precedes the Mac capture.
The iPhone video plays in an `AVPlayerLayer` without playback controls, aligned
with the Mac story. Source fingerprints include the private phone app's resources
and debug dylib, plus the capture script, to invalidate stale phone footage.
The central connector starts empty, changes to a left arrow when the new note
arrives, then to a right arrow for the Mac edit, which remains through the end.
The cloud sits below the phone in place of its old text label. The pink window
bottom is aligned to that cloud frame, at canvas y=74; no Mac label is shown.

Timeline: 0–12 seconds Mac has one note while iPhone starts at its note list,
creates a new note and enters title/first task; at 12 seconds the new note arrives
on Mac. At 14–20 seconds Mac adds the next task and completes the first. At about
23 seconds iPhone receives both changes. The final scene holds matching content.
This is a scripted demonstration, not a measurement of real network latency.
Export checks the one-note opening, native creation flow, and matching final
task text and completion on both replicas and in the recorded iPhone screen.

The exporter checks both replicas and names this video's output
`Tildone-macOS-preview-2-sync-<locale>.mp4`, preserving preview one's filenames.

The capture build runs the real `Note`, `MacNoteWindow`, checkbox, editor,
title-bar controls, compact presentation and completion lifecycle with three
synthetic checklists in an explicitly in-memory `TildoneRepository`.

The `MARKETING_CAPTURE` compilation condition selects a separate entry point.
The build script requires a private bundle identifier; the customer's app
bootstrap, delegate, CloudKit and StoreKit are never started. Ordinary Debug
and Release builds compile out the capture code and retain their original entry.

## Build and record

```sh
python3 Scripts/build-marketing-preview.py --wallpaper /absolute/path/GoldenGate.png
```

For localized exports, add `--locale es-ES`, `--locale fr-FR`, or
`--locale zh-Hans`, and use a separate `--output` directory for each language.
The private app selects its own language before AppKit launches and explicitly
supplies the locale to SwiftUI; system and customer app language settings stay
unchanged. The exporter validates the resolved language and names the video
using its capture locale.

To record several prepared sync-preview languages in one GUI session, run
`python3 Scripts/record-marketing-localizations.py --apps /path/to/es.app
/path/to/fr.app /path/to/zh.app`. Each private Mac app must point to its own
matching-locale private iPhone app and output directory. The batch records both
native apps, exports and verifies each 30-second MP4, and copies the finished
videos to `Marketing/Preview/Output/macOS-App-Store`. Wait for
`ALL RECORDINGS FINISHED` before reporting completion. Each Mac capture has its
own ten-second warning. The approved binaries can be copied with only their
capture Info.plist locale and output paths changed; their existing localized
resources supply native captions, controls and fixture text.

Launch the printed `TildonePreviewStudio.app` through Finder. It stages the
wallpaper in its own window without changing the system wallpaper. It records
only its own window and child notes with ScreenCaptureKit's permission-free
current-process API, with audio and system cursor capture disabled.

The capture starts after setup, runs for approximately 30 seconds and exits.
`capture-status.txt` reports progress/errors; `capture-result.json` verifies
that completion removed the mock note and the typed task was committed.
The supplied cursor is a presentation overlay using the native arrow asset.
Its movement does not move the user's pointer. Recorded actions invoke the
actual checkbox and minimize button, and type through the real field editor.

The mock notes use the real per-note color picker. Text size is set to 20 pt
and background opacity to 72%, both supported customer settings. Caption and
fixture text has English, Spanish, French and Simplified Chinese localizations.
The completion scene caption is “Done. Off your mind.”, connecting the visible
fade to the opening promise of less mental load.

The current composition uses 82.5 pt headlines and 33.75 pt subtitles (50%
larger than the second composition). Expanded note content is reduced by 25% with
a live SwiftUI transform (effective task text size 15 pt), with their
origins moved 25% toward the canvas's bottom-left corner. Native title-bar
controls retain their normal size. The compact note keeps its normal dimensions
and sits 47.5 pt from the left and bottom edges, half the original bottom margin.
The completed note's window is 15% larger and Home's window is 15% smaller than
the second composition, without changing their content scale. Capture-only
minimum sizes account for the content transform. A subdued native window with a
fictional email inbox and selected travel email sits behind the notes. Its outer
size is approximately 488 × 385 pt, 25% larger in each dimension than the fourth
composition's 390 × 308 pt inbox. Its title is “Mail” and its left edge is 195 pt
farther right, half the fourth composition's width. Home and expanded Weekend
each sit 25% of their own heights farther down; compact Weekend retains its
47.5 pt edge margin. Early activation and a small vertical movement demonstrate
the real floating window level. It is hosted by the private capture app,
without opening Mail or accessing any customer account or files.

Conform and verify the recording with:

```sh
python3 Scripts/export-marketing-preview.py
```

The private build omits Icon Studio's app-icon compilation, which needs a GUI
service unavailable in the build runner; customer build settings are unchanged.
Build caches are explicitly scoped to `/tmp`. Compiler and package-manifest
child sandboxes are disabled only in this build command because the outer build
runner is already sandboxed. No system security settings are changed.

## Deliverable

Use `Tildone-macOS-preview-raw.mp4` as the source. Conform to exactly 30 seconds,
1920 × 1080, constant 30 fps, H.264 High at approximately 10–12 Mbps, yuv420p,
Rec.709 tagging and fast start. Inspect a contact sheet and the full sequence.
Select the poster frame at two seconds. Final exports are kept out of git.

The background used for the first render is Apple's light abstract macOS 27
Golden Gate wallpaper, obtained from Basic Apple Guy's official-wallpaper
extraction page: https://basicappleguy.com/haberdashery/macosgoldengate
The wallpaper is a supplied build input and is not added to customer resources.

## Screenshot 5: reclaim the workspace

Build the private `screenshot-5` story with `Scripts/build-marketing-preview.py`.
`MarketingGatherCaptureDirector` has a separate capture entry point, an explicit
in-memory repository and six real `MacNoteWindow`/`Note` instances: three matching
plans in each scene, each with two pending tasks. No customer app bootstrap,
CloudKit or purchase flow is started. Screenshot 1–4 and both video stories keep
their existing directors.

The English headline is “Keep the reminder. Reclaim the space.” and the subtitle
is “Your plans stay close. Your workspace opens up.” All artwork copy and fixture
text is translated into Spanish, French and Simplified Chinese. The common
“Tildone Pro · One-time purchase” disclosure is retained.

The smaller, unframed before scene floats directly on the main wallpaper. Its
quiet native mock TextEdit window is 310 × 220 points at (95, 250); Home is at
(65, 165), Shopping at (335, 320), and Weekend at (315, 115). Their dimensions
are respectively 230 × 180, 240 × 180 and 235 × 180 points. Both scenes use the
same production note content at 0.75×, including native editors and titlebars.
The larger outcome inset is (665, 90), 730 × 490 points, with a 450 × 350 mock
document at (895, 180). Its matching notes gather to (685, 130), (735, 145), and
(710, 115), retaining their expanded dimensions and relative horizontal/vertical
order. The yellow right edge extends beyond pink. These approved presentation
targets use the production `NoteCornerConvergence` interpolation; no production
corner-target selection or user preference is changed. Outcome window alpha
is 0.9 through the supported native opacity calculation.

Ghost outlines are computed from the **measured** before document and note
frames, transformed into the measured outcome document's coordinate system.
Their sizes follow that same transform. Outline opacity is 0.065; fine motion
traces have opacity 0.025. A transparent, noninteractive own-process child window
places these effects above the documents and below the real notes, clipped to
the inset. Its white-on-charcoal “Gather with a scroll.” capsule sits inside the
inset's upper-left corner. It reuses `ScrollChevronIndicator` from Settings, with
six downward chevrons, animating during preparation and freezing at travel offset
17 for the still. Making that existing component module-visible is the only
ordinary-build change; its appearance and behavior are unchanged.

Revision 2 separates the before notes with at least 20 points between every
pair, retaining their dimensions and the gathered scene. Ghosts follow the new
measured positions automatically. Capture proof revision 2 checks the measured
separation, paired fixture content and dimensions, expanded state, relative note order, yellow-edge visibility, native window ordering,
outcome containment and reduced document coverage. It records the measured
source/target/ghost frames, and the Python exporter independently recomputes the
document-relative ghost transform. This is an own-process stage capture with
child windows, no second-window compositing or OCR. Output is opaque sRGB,
2880 × 1800. Native captures still need visual review after the GUI batch.

Run `Output/macOS-App-Store/Capture-screenshot-5-all-languages.command` in a GUI
Terminal session (also staged as `/tmp/Tildone-Screenshot-5-All-Languages.command`).
After the first ten-second countdown, leave the screen idle until
**ALL SCREENSHOTS FINISHED**. Final files are copied to
`Output/macOS-App-Store/Tildone-macOS-screenshot-05-<locale>.png`.

## Screenshot 6: a comfortable desktop

Build the isolated `screenshot-6` story. `MarketingAppearanceCaptureDirector`
uses the existing private capture bundle, in-memory repository and normal native
`MacNoteWindow`, `Note`, task editors and titlebar controls. There are no customer
stores, CloudKit, StoreKit actions or changes to shipping appearance behavior.
The new capture-only branch in `SettingsForm` mounts its existing color,
background-transparency, font-size and wrapping controls, instead of drawing
lookalike sliders. Existing full Settings presentation is retained.

The headline is “A desktop that feels like yours.” and the subtitle is
“Your colors. Your text size. Your level of quiet.” Green Weekend plans has
three tasks at the supported 20-point font setting, 0.65 background opacity and
full window alpha. Purple At home has two tasks at 15 points and **zero background
tint**, with full window alpha. Its real NSVisualEffectView material, chrome and
shadow are retained; no invisible-window simulation or hand-drawn glass is used.
Orange Later has two tasks at 15 points and whole-window alpha 0.45. The existing
opacity calculation and opacity-change notification update its native background
and text presentation. Only this example carries “Dim notes with a scroll.” and
the contextual “Tildone Pro · One-time purchase” pill. The other showcased
appearance settings are free. Header, fixtures and captions support en-US,
es-ES, fr-FR and zh-Hans, along with the existing localized Settings controls.
No external example labels or green presentation border are added.

Font size and background transparency are global preferences. Weekend and Later
are captured sequentially with fresh native Note views and their respective
settings, then retained as unmodified own-process stage-image crops. The green
note opens its existing six-color native NSPopover via its accessibility press
action. Its actual frame is observed only under MARKETING_CAPTURE. Source PNGs
are retained in `native-frames/`. There is no independent popover-image capture.

Revision 2 applies the approved overlapping layout. Settings moves to (85, 50),
410 × 310 points. Weekend is (570, 310), 405 × 310; Later is (1030, 195),
325 × 240, with its contextual caption centered at (1192.5, 147). The 55-point
horizontal gap keeps Weekend clear of Later, and the complete Later window is
in the lower half of the artwork. At home is (385, 220), 325 × 240, covering
Weekend's bottom-left corner and Settings' upper-right corner.

After capturing Weekend and Later, the director mounts the real Settings
excerpt with the transparent example's 15-point font and zero background tint.
It then mounts At home **as a live native window**, above Settings and the
previously captured Weekend example. At home remains live in the final stage
capture; its opaque screenshot crop is never painted behind itself. This is
necessary for correct native backdrop composition and avoids the Settings
window later covering a flattened At home image. Its actual behind-window
material, native shadow and controls are retained. The previous isolated source
looked flat gray; the overlapping live material still requires pixel inspection
after the GUI run. No hand-drawn blur, glass or invisible-window simulation is
introduced. All preferences remain in the capture process's volatile domain.

Revision 2/3 proof checks actual task-font attributes, title visibility, native
window alpha and zero tint. It records whether each example is live or captured,
retained material/shadows, actual measured note and Settings frames, overlapping
corners, native stacking order and Weekend/Later separation. The Python exporter
independently recomputes those overlaps and gap. It also checks source PNGs,
reused Settings controls, localized copy and the dimming-only purchase disclosure.
Final output is opaque sRGB, 2880 × 1800. Capture and material/visual review still
need the user's GUI session.

Revision 3 changes **only the final export method** to the screen-rectangle
method the user verified in macOS Screenshot. Behind-window material is correct
on screen but flattened by the stage/window snapshot API. After preparing the
same live overlapping scene, the app writes `screen-region-request.json`, waits
at `READY FOR SCREEN REGION`, and stays visible. The GUI launcher runs
`capture-marketing-screen-region.py`, which calls `/usr/sbin/screencapture -x -t
png -R<x,y,1440,900> <temporary.png>`; it never uses window-ID capture. Coordinates
are the actual integer stage frame converted from AppKit's primary-bottom-left
space to the desktop's primary-top-left screen space. The canvas must fit wholly
inside a screen's visible area; a fitting connected screen is selected before
presentation. This rectangle capture is explicitly authorized by the user and
can include any object visibly covering that canvas, so keep the screen idle.

The helper atomically saves the original display PNG to
`native-frames/screen-region-native.png` and acknowledges the matching scene token.
The app then converts those actual screen pixels to opaque sRGB at 2880 × 1800
with ImageIO/CoreGraphics, writes revision 3 proof, and closes. The raw source's
pixel dimensions, rectangle and capture method are retained. All earlier native
example captures, layout, text and mock-data isolation remain as documented.
This uses no synthesized glass, blur or replacement background. The exported
material must still be visually reviewed after the GUI run.

If region capture fails, the scene deliberately remains open. On a retry, the
new private app terminates only older instances of the same private capture
bundle, preventing stale floating notes from appearing in the rectangle. The
separate `/tmp/Tildone-Screenshot-6-Manual-English.command` uses the same native
Screenshot tool with `-i -s`: drag the complete canvas rectangle, without Space
(window mode). macOS may require Screen Recording access for the GUI Terminal
running the command. No additional permission is requested by the chat agent.

Run `Output/macOS-App-Store/Capture-screenshot-6-all-languages.command`, also
staged as `/tmp/Tildone-Screenshot-6-All-Languages.command`. Leave the screen idle
from the first ten-second countdown until **ALL SCREENSHOTS FINISHED**. Files
are copied to `Output/macOS-App-Store/Tildone-macOS-screenshot-06-<locale>.png`.
