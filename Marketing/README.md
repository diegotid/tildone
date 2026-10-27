# Marketing source and generated files

Keep source code, localized string catalogs, canonical App Store copy,
editorial review documents, capture instructions and external-input manifests
in Git. App icon/runtime artwork remains tracked as application source.

Generated media, simulator app bundles, native recordings, screenshots,
thumbnails, contact sheets, logs and runtime verification files live under
`Preview/Output/`, which is ignored. Export snapshots and ZIPs under
`AppStore/Exports/` are also ignored. These rules do not delete any local file.
Do not add blanket `*.png`, `*.mp4` or `*.zip` exclusions across the repository:
original inputs and source artwork may use those formats.

## App Store copy

`AppStore/macOS-2.0/metadata.json` is the canonical Mac field content.
Its `README.md` and `REVIEW.md` retain editorial decisions and human review.
The iPhone's canonical copy is `AppStore/iOS-1.0/REVIEW.md`; its visual brief and
approved history are in `ASSETS.md`.

The Mac's per-locale TXT fields and count report are derived:

```sh
python3 Scripts/export-app-store-copy.py \
  --source Marketing/AppStore/macOS-2.0/metadata.json \
  --output Marketing/AppStore/macOS-2.0 \
  --date 2026-10-25
```

The generator verifies every field limit, including UTF-8 keyword bytes.
The existing 24 TXT fields and validation report were reproduced exactly.

## Capture dependencies and release evidence

The original Golden Gate wallpaper is an external input, not a generated
image. `Preview/Inputs/manifest.json` pins its source page, size and SHA-256.
Keep that original available outside Git and pass it to the private Mac
capture builder with `--wallpaper`. The iPhone's MacBook artwork also consumes
the generated native Mac screenshot 2 and its window-frame metadata; rebuild
that prerequisite using `Preview/README.md` before a clean iPhone export.

Native capture results depend on the Apple SDK, installed simulator runtime,
fonts, animation timing and original wallpaper. A fresh capture can recreate
the approved composition but need not produce byte-identical PNG/MP4 files.
Keep the exact approved release media and detailed audit outside Git.
`AppStore/iOS-1.0/release-manifest.json` is the small, portable record of the
approved filenames, hashes, formats and toolchain; it contains no local paths.
The current screenshot delivery uses 1206 × 2622 for the required iPhone
Dynamic Island medium-display slot. `release-manifest-large.json` preserves
the previously approved 1320 × 2868 set. The native captures and compositions
are shared; `render-marketing-ios-thumbnail.swift --medium` renders directly
at the new output scale. Previews remain 886 × 1920 and work in both slots.

To re-export saved screenshot sources without recapture, use
`Scripts/reexport-marketing-ios-screenshots.py --output <new-iteration>`, review
the 24 images, then rerun with `--publish`. Native capture is not needed.
`export-marketing-ios-asset.py` and `package-marketing-ios-assets.py` now default
to medium screenshots; use `--display-size large` to recreate/audit a large set.

## Rebuild the iPhone set

Use macOS with Xcode, an installed iOS Simulator runtime and `ffmpeg`/`ffprobe`
on `PATH`. The private app uses production SwiftUI components and disposable
in-memory mocks. The simulator captures do not need an idle desktop or a
physical iPhone. The current native capture framing expects a 1206 × 2622
simulator image; the format checks reject a different device/runtime size.

First restore the original wallpaper and the four localized native Mac
screenshot-2 prerequisites described in `Preview/README.md`. For each locale,
the iPhone compositor reads these paths beneath
`Preview/Output/screenshots/02/<locale>/`:

- `Tildone-macOS-screenshot-02-<locale>.png`
- `screenshot-result.json` with the native note-window rectangles
- `phone-frames/phone-capture-verification.json` with matching note/task content
- `TildonePreviewStudio.app/Contents/Resources/GoldenGate.png`

To regenerate that prerequisite, build the phone with `--story screenshot-2`
and then the Mac with `--story screenshot-2`, `--locale`, `--wallpaper`, and
the same locale output directory. Use the Mac builder's printed private app
path with `record-marketing-localizations.py --story screenshot-2 --apps ...`.
The Mac builder places its app in DerivedData: also copy that private app into
the locale output directory as `TildonePreviewStudio.app`, retaining the
wallpaper resource at the path above. **The Mac GUI capture requires an idle
screen; tell the user and schedule it before running.** The iPhone runner
checks these prerequisites and never starts a Mac capture automatically.
Recreating prerequisites on a fresh checkout produces new captures, not the
exact historical approved bytes. Preserve any existing approved Mac outputs
before explicitly recapturing them.

Inspect the complete plan and check inputs without starting a capture:

```sh
python3 Scripts/run-marketing-ios-suite.py \
  --output Marketing/Preview/Output/iOS/revisions/new-iteration --plan
python3 Scripts/run-marketing-ios-suite.py \
  --output Marketing/Preview/Output/iOS/revisions/new-iteration --check-inputs
```

Run the same command without either flag to build once and capture all eight
assets in all four locales. `--assets` and `--locales` can select a smaller
iteration. Screenshot 2 precedes preview 2; screenshot 3 captures grid and deck
from the same mock session. Every capture creates and removes its own isolated
simulator. A new iteration directory is required, prior final media is copied
into that iteration's `previous-final` folders, and Mac media is hash-checked
against a baseline recorded before the run. No `ready.json`, prepared app,
session repair manifest or temporary worker script is needed.

Review the native frames, thumbnails and video motion before publishing.
After all 32 canonical exports are present, audit/package and refresh the
standing final delivery folder:

```sh
python3 Scripts/package-marketing-ios-assets.py \
  --destination Marketing/Preview/Output/iOS/revisions/new-iteration/package \
  --mac-baseline Marketing/Preview/Output/iOS/revisions/new-iteration/mac-media-baseline.json \
  --no-archive
```

The package includes review/source evidence outside the upload folder.
`publish-marketing-ios-finals.py` can refresh the upload folder independently;
it copies the 32 final screenshot/preview PNG/MP4 files plus any approved full
Header/Search Results PNGs into locale `Creative` folders, and archives replaced versions in
`Preview/Output/iOS/revisions/delivery-history/`. Its default destination is
`/tmp/Tildone-iPhone-App-Store-Finals`, as requested by the owner. This location
is temporary: preserve the approved release externally if the temporary
directory is cleared. Neither command uploads to App Store Connect.

The approved r11 Header is rendered with
`render-marketing-ios-header-thumbnail.swift --full --large-text-review --native-root <captures>`.
Use `export-marketing-ios-header.py` with the approved English thumbnail to
export all four locales from existing native captures. Review the full image
and template-safe-area detail before publishing. Earlier r4 Headers remain
preserved alongside r7 and r9; only the r11 files belong in the current upload folder.
The owner approved the larger caption outside the conservative template safe
area; the audit records that exception rather than claiming text-safe-area
compliance. Its full English composition matches the approved r11 thumbnail. The localized
Header workflow and Search Results approval state are documented in
`AppStore/iOS-1.0/CREATIVE-ASSETS.md`.

`update-marketing-ios-localizations.py` is the incremental localization helper
for the five compositions changed in the approved iteration. It requires an
existing complete English/localized set. The older screenshot-1 batch helper
also expects prepared apps; use the suite runner above for a fresh checkout.
