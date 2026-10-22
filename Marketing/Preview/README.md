# macOS App Store preview

## Preview 2: continuity

Build the separate sync story with `--story sync --output Marketing/Preview/Output/sync/revision-7/en-US`.
The default `--story desktop` retains preview one's composition and timeline.
Both stories support the same four capture locales.

The sync story uses two explicitly in-memory repositories, with the real domain
remote-merge operations and Mac presentation refresh. Revision 7 includes a native
iPhone video of the real `NotesListView` and `ChecklistView`, in a separate private
simulator app. It starts with one existing Home note, creates a new note through
the real navigation action, and types its title and first task into native fields.
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
The private phone fields disable text correction for the supplied translated
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
