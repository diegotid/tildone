#!/usr/bin/env python3
"""Audit and package the approved iPhone App Store media and native sources."""
import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import zipfile
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

repo = Path(__file__).resolve().parents[1]
capture = repo / "Marketing/Preview/Output/iOS/captures"
media = repo / "Marketing/Preview/Output/iOS-App-Store"
parser = argparse.ArgumentParser()
parser.add_argument("--destination", type=Path, default=Path("/tmp/Tildone-iPhone-App-Store-1.0"))
parser.add_argument("--no-archive", action="store_true")
parser.add_argument("--mac-baseline", type=Path, required=True,
                    help="Mac media hashes recorded before this iteration, e.g. run-marketing-ios-suite.py output")
args = parser.parse_args()
baseline = json.loads(args.mac_baseline.read_text())
assert isinstance(baseline, dict)
for name, expected in baseline.items():
    relative = Path(name)
    assert not relative.is_absolute() and ".." not in relative.parts
    mac_file = repo / "Marketing/Preview/Output/macOS-App-Store" / relative
    assert hashlib.sha256(mac_file.read_bytes()).hexdigest() == expected, name
destination = args.destination.resolve()
destination.mkdir(parents=True, exist_ok=True)
locales = ["en-US", "es-ES", "fr-FR", "zh-Hans"]
assets = [f"screenshot-{n}" for n in range(1, 7)] + ["preview-1", "preview-2"]
manifest = []
worker_results = {}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def contact(inputs, output, width, height):
    args = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-filter_complex_threads", "2"]
    for image in inputs:
        args += ["-i", str(image)]
    filters = [f"[{i}:v]scale={width}:{height}[v{i}]" for i in range(6)]
    layout = f"0_0|{width}_0|{width*2}_0|0_{height}|{width}_{height}|{width*2}_{height}"
    filters += ["".join(f"[v{i}]" for i in range(6)) + f"xstack=inputs=6:layout={layout}[out]"]
    args += ["-filter_complex", ";".join(filters), "-map", "[out]", "-frames:v", "1", str(output)]
    subprocess.run(args, check=True)

review = destination / "Review"
review.mkdir(exist_ok=True)
for locale in locales:
    for asset in assets:
        directory = capture / asset / locale
        result = json.loads((directory / "export-result.json").read_text())
        source = Path(result["file"])
        assert result["asset"] == asset and result["locale"] == locale and result["verified"] and not result.get("draft", False), result
        revision = Path(result.get("revisionDirectory", directory))
        assert digest(source) == result["sha256"], source
        native_proof = json.loads(Path(result["nativeProof"]).read_text())
        assert native_proof["mockDataOnly"] and not native_proof["cloudKitStarted"] and native_proof["nativeUI"], native_proof
        assert native_proof["locale"] == locale, native_proof
        assert native_proof["proContent"] == (asset in ["screenshot-5", "screenshot-6", "preview-2"]), native_proof
        entry = {"asset": asset, "locale": locale, "sha256": digest(source),
                 "tier": "optional-one-time-Pro" if native_proof["proContent"] else "free"}
        if asset.startswith("screenshot-"):
            assert struct.unpack(">IIBB", source.read_bytes()[16:26]) == (1320, 2868, 8, 2), source
            if asset == "screenshot-1":
                assert native_proof["taskCount"] == 4 and native_proof["allTasksVisible"], native_proof
            if asset == "screenshot-3":
                assert [n["color"] for n in native_proof["notes"]] == ["green", "blue", "yellow", "green", "green"], native_proof
                deck_path = Path(result["nativeDeckProof"])
                deck = json.loads(deck_path.read_text())
                assert deck["layout"] == "deck" and deck["notes"] == native_proof["notes"]
                assert deck["nativeUI"] and deck["mockDataOnly"] and not deck["cloudKitStarted"]
                deck_target = destination / "Sources" / locale / "screenshot-3-deck.png"
                deck_target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(deck_path.parent / "phone-checklist.png", deck_target)
                shutil.copy2(deck_path, deck_target.with_suffix(".json"))
                entry["nativeDeckSource"] = str(deck_target.relative_to(destination))
                entry["nativeDeckSourceSHA256"] = digest(deck_target)
            target = destination / locale / "Screenshots" / source.name
            entry.update(width=1320, height=2868, opaque=True, bitDepth=8, colorSpace="sRGB")
            native_file = Path(result["nativeProof"]).parent / "phone-checklist.png"
        else:
            probe = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(source)]))
            video = next(s for s in probe["streams"] if s["codec_type"] == "video")
            audio = next(s for s in probe["streams"] if s["codec_type"] == "audio")
            assert (video["width"], video["height"], video["codec_name"], video["pix_fmt"], video["r_frame_rate"], int(video["nb_frames"])) == (886,1920,"h264","yuv420p","30/1",900), video
            assert audio["codec_name"] == "aac" and audio["channels"] == 2 and audio["sample_rate"] == "48000", audio
            assert abs(float(probe["format"]["duration"]) - 30) < 0.05, probe
            assert all(video[key] == "bt709" for key in ["color_primaries", "color_transfer", "color_space"]), video
            target = destination / locale / "Previews" / source.name
            entry.update(width=886, height=1920, durationSeconds=30, fps=30, codec="H.264 High", audio="silent stereo AAC")
            native_file = Path(result["nativeProof"]).parent / "phone-native.mp4"
            poster = media / f"Tildone-iOS-{asset}-poster-{locale}.png"
            poster_target = destination / locale / "Posters" / poster.name
            poster_target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(poster, poster_target)
            contact([revision / f"review-{s:02}.png" for s in [2,7,12,17,22,28]],
                    review / f"Tildone-iOS-{asset}-{locale}.png", 220, 477)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        entry["file"] = str(target.relative_to(destination))
        native_target = destination / "Sources" / locale / (asset + native_file.suffix)
        native_target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(native_file, native_target)
        shutil.copy2(Path(result["nativeProof"]), native_target.with_suffix(".json"))
        entry["nativeSource"] = str(native_target.relative_to(destination))
        entry["nativeSourceSHA256"] = digest(native_file)
        manifest.append(entry)
        worker_results[asset + "/" + locale] = result
    contact([destination / locale / "Screenshots" / f"Tildone-iOS-screenshot-{n:02}-{locale}.png" for n in range(1,7)],
            review / f"Tildone-iOS-screenshots-{locale}.png", 330, 717)

for name, expected in baseline.items():
    assert digest(repo / "Marketing/Preview/Output/macOS-App-Store" / name) == expected, name
assert len(manifest) == 32
audit = {"generatedAt": datetime.now(ZoneInfo("Europe/Madrid")).isoformat(), "mainAssetCount": 32,
         "screenshots": 24, "previews": 8, "locales": locales,
         "nativeSwiftUI": True, "mockDataOnly": True, "physicalIPhoneUsed": False,
         "liveCloudKitUsed": False, "macMediaUnchanged": len(baseline), "assets": manifest}
(destination / "manifest.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n")
(media / "final-validation.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n")
(capture / "suite-result.json").write_text(json.dumps({"assets": assets, "locales": locales, "results": worker_results,
    "expectedCount": 32, "complete": True, "physicalIPhoneUsed": False, "liveICloudUsed": False}, ensure_ascii=False, indent=2) + "\n")
readme = """# Tildone — iPhone App Store assets 1.0

32 main assets: six screenshots and two previews in en-US, es-ES, fr-FR and Simplified Chinese (zh-Hans).

Each language folder contains:

- **Screenshots:** upload the six numbered PNGs in order. 1320 × 2868, opaque 8-bit sRGB.
- **Previews:** free experience first, optional Pro second. Each is exactly 30 seconds, portrait 886 × 1920, 30 fps, H.264 High with silent stereo AAC.
- **Posters:** reference images from 00:02 of each finished preview. Select that time as the poster frame in App Store Connect.

The free preview shows list, grid and deck layouts, captures a task and marks progress. Free Mac–iPhone iCloud sync is identified throughout. Preview 2 opens with matching iPhone/Mac notes and free sync, then shows subtasks, collapsing, selective word styling and a Permanent Marker memo. Its optional one-time purchase subtitle accompanies paid-feature scenes; it is absent during the opening and the later free-sync claim. The MacBook and white opening captions zoom and move down together, revealing the following caption while the native lists crossfade. Screenshots 5 and 6 also identify optional Pro; one purchase covers iPhone and Mac, with no subscription.

**Review** contains contact sheets for all languages. These are review aids, not upload screenshots.

**Sources** preserves the final native iPhone captures and their mock-data verification. The app UI uses the running production SwiftUI components in an isolated simulator. The background, captions and translucent bezel are marketing composition; hardware islands are hidden. No physical iPhone, customer notes, live CloudKit transport or purchase flow was used. The Mac inset reuses an existing native Mac capture with matching content. Synchronization is illustrated, not timed or network-qualified by these captures.

The existing Mac media files listed in the supplied baseline were checked unchanged. No App Store submission was made.

**manifest.json** records dimensions, duration and source/output hashes.

Apple specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/ and https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications/
"""
(destination / "README.md").write_text(readme)
if not args.no_archive:
    archive = Path("/tmp/Tildone-iPhone-App-Store-Assets.zip")
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
        for file in sorted(destination.rglob("*")):
            if file.is_file():
                bundle.write(file, destination.name + "/" + str(file.relative_to(destination)))
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None
    print(archive)
subprocess.run([sys.executable, str(repo / "Scripts/publish-marketing-ios-finals.py")], check=True)
print(f"Verified: 24 screenshots, 8 previews, four languages, {len(baseline)} unchanged Mac media files.")
