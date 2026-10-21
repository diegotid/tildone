# macOS App Store preview

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
