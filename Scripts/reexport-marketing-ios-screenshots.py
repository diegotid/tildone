#!/usr/bin/env python3
"""Re-render approved screenshot compositions from saved native captures."""
import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--display-size", choices=["medium", "large"], default="medium")
parser.add_argument("--publish", action="store_true", help="After visual review, replace canonical screenshots and refresh delivery")
args = parser.parse_args()
root = args.output.resolve()
revisions = repo / "Marketing/Preview/Output/iOS/revisions"
assert root.is_relative_to(revisions) and root != revisions
root.mkdir(parents=True, exist_ok=True)
captures = repo / "Marketing/Preview/Output/iOS/captures"
media = repo / "Marketing/Preview/Output/iOS-App-Store"
dimensions = (1206, 2622) if args.display_size == "medium" else (1320, 2868)
locales = ["en-US", "es-ES", "fr-FR", "zh-Hans"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


snapshot = root / "previous-records.json"
if not snapshot.exists():
    previous = {}
    for locale in locales:
        for number in range(1, 7):
            key = f"screenshot-{number}/{locale}"
            record = json.loads((captures / key / "export-result.json").read_text())
            assert record["verified"] and not record.get("draft", False)
            source = Path(record["file"])
            assert digest(source) == record["sha256"]
            backup = root / "previous-final" / locale / source.name
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, backup)
            previous[key] = record
    save(snapshot, previous)
previous = json.loads(snapshot.read_text())
mac_directory = repo / "Marketing/Preview/Output/macOS-App-Store"
baseline_path = root / "mac-media-baseline.json"
if not baseline_path.exists():
    save(baseline_path, {p.name: digest(p) for p in sorted(mac_directory.iterdir())
                         if p.suffix in {".png", ".mp4"}})
baseline = json.loads(baseline_path.read_text())
preview_hashes = {p.name: digest(p) for p in media.glob("*.mp4")}
assert len(preview_hashes) == 8
tools = Path("/tmp/TildoneIOSRenderTools")
tools.mkdir(exist_ok=True)
renderer = tools / "render-screenshot"
source = repo / "Scripts/render-marketing-ios-thumbnail.swift"
if not renderer.exists() or renderer.stat().st_mtime < source.stat().st_mtime:
    subprocess.run(["swiftc", "-disable-sandbox", "-module-cache-path", "/tmp/tildone-marketing-module-cache",
                    "-O", str(source), "-o", str(tools / "render-screenshot.new")], check=True, timeout=180)
    (tools / "render-screenshot.new").replace(renderer)
results = {}
for locale in locales:
    for number in range(1, 7):
        asset = f"screenshot-{number}"
        key = asset + "/" + locale
        original = previous[key]
        directory = root / key
        directory.mkdir(parents=True, exist_ok=True)
        result_path = directory / "export-result.json"
        existing = json.loads(result_path.read_text()) if result_path.exists() else None
        if not (existing and existing.get("displaySize") == args.display_size
                and digest(Path(existing["file"])) == existing["sha256"]):
            native = Path(original["nativeProof"]).parent
            command = [sys.executable, str(repo / "Scripts/export-marketing-ios-asset.py"),
                       "--asset", asset, "--locale", locale, "--native", str(native),
                       "--output", str(directory), "--display-size", args.display_size, "--draft", "--repair"]
            if number == 3:
                command += ["--deck-native", str(Path(original["nativeDeckProof"]).parent)]
            with (directory / "export.log").open("w") as log:
                subprocess.run(command, cwd=repo, check=True, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        result = json.loads(result_path.read_text())
        assert struct.unpack(">IIBB", Path(result["file"]).read_bytes()[16:26]) == (*dimensions, 8, 2)
        assert result["nativeProof"] == original["nativeProof"]
        result.update(approvedCompositionPreserved=True, formatAdaptationOnly=True,
                      previousSHA256=original["sha256"], nativeRecaptured=False)
        save(result_path, result)
        results[key] = result
        save(root / "status.json", {"stage": "rendering", "completed": len(results), "total": 24})
for name, expected in baseline.items():
    assert digest(mac_directory / name) == expected
assert preview_hashes == {p.name: digest(p) for p in media.glob("*.mp4")}
if args.publish:
    # All 24 files have passed format verification before any canonical replacement.
    for key, result in results.items():
        source = Path(result["file"])
        target = media / source.name
        current = json.loads((captures / key / "export-result.json").read_text())
        assert current["sha256"] in {previous[key]["sha256"], result["sha256"]}
        assert digest(target) == current["sha256"]
        temporary = target.with_suffix(".copying")
        shutil.copy2(source, temporary)
        assert digest(temporary) == result["sha256"]
        temporary.replace(target)
        canonical = dict(result, file=str(target), draft=False, requiresVisualReview=False)
        save(captures / key / "export-result.json", canonical)
    subprocess.run([sys.executable, str(repo / "Scripts/publish-marketing-ios-finals.py")], check=True)
save(root / "status.json", {"stage": "published" if args.publish else "ready for visual review",
                           "screenshots": 24, "width": dimensions[0], "height": dimensions[1],
                           "nativeRecaptured": False, "previewsUnchanged": 8, "macMediaUnchanged": len(baseline)})
print(root)
