#!/usr/bin/env python3
"""Export approved Search Results artwork using existing localized native captures."""
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
parser.add_argument("--native-root", type=Path, required=True, help="Approved Header capture iteration with four locale folders")
parser.add_argument("--output", type=Path, required=True, help="New Search Results iteration")
parser.add_argument("--approved-thumbnail", type=Path, required=True, help="Owner-approved English thumbnail")
parser.add_argument("--publish", action="store_true", help="After localized visual review, register final exports and refresh delivery")
args = parser.parse_args()
root = args.output.resolve()
native_root = args.native_root.resolve(strict=True)
assert root.is_relative_to(repo / "Marketing/Preview/Output/iOS/creative/search-results")
thumbnail = args.approved_thumbnail.resolve(strict=True)
thumbnail_proof = json.loads(thumbnail.with_suffix(".json").read_text())
assert thumbnail_proof["asset"] == "search-results" and thumbnail_proof["locale"] == "en-US"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, record):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


thumbnail_hash = digest(thumbnail)
assert thumbnail_hash == thumbnail_proof["sha256"]
root.mkdir(parents=True, exist_ok=True)
tools = Path("/tmp/TildoneIOSRenderTools")
tools.mkdir(exist_ok=True)
renderer = tools / "render-creative"
source = repo / "Scripts/render-marketing-ios-header-thumbnail.swift"
if not renderer.exists() or renderer.stat().st_mtime < source.stat().st_mtime:
    subprocess.run(["swiftc", "-disable-sandbox", "-module-cache-path", "/tmp/tildone-marketing-module-cache",
                    "-O", str(source), "-o", str(tools / "render-creative.new")], check=True, timeout=180)
    (tools / "render-creative.new").replace(renderer)
media = repo / "Marketing/Preview/Output/iOS-App-Store"
captures = repo / "Marketing/Preview/Output/iOS/captures"
completed = []
for locale in ["en-US", "es-ES", "fr-FR", "zh-Hans"]:
    directory = root / locale
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / "export-result.json"
    if path.exists():
        record = json.loads(path.read_text())
        assert record["approvedThumbnailSHA256"] == thumbnail_hash, "Use a new iteration for changed artwork."
        assert digest(Path(record["file"])) == record["sha256"]
    else:
        native = native_root / locale
        if locale == "en-US":
            comparison = directory / "approved-shape-check.png"
            subprocess.run([str(renderer), str(comparison), "--asset", "search-results", "--native-root", str(native)],
                           cwd=repo, check=True, timeout=180)
            def pixels(image):
                return subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(image),
                                                "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])
            assert pixels(comparison) == pixels(thumbnail), "Approved English composition changed."
        result = directory / f"Tildone-iOS-search-results-{locale}.png"
        subprocess.run([str(renderer), str(result), "--asset", "search-results", "--native-root", str(native),
                        "--locale", locale, "--full"], cwd=repo, check=True, timeout=180)
        record = json.loads(result.with_suffix(".json").read_text())
        assert record["approved"] and not record["draft"] and record["locale"] == locale
        assert struct.unpack(">IIBB", result.read_bytes()[16:26]) == (3840, 2560, 8, 2)
        assert digest(result) == record["sha256"]
        record.update(file=str(result), revisionDirectory=str(directory), renderProof=str(result.with_suffix(".json")),
                      approvedThumbnailSHA256=thumbnail_hash, reusedNativeCaptures=True)
        save(path, record)
        subprocess.run(["sips", "-Z", "1280", str(result), "--out", str(directory / "full-review.png")],
                       check=True, stdout=subprocess.DEVNULL)
    if args.publish:
        result = Path(record["file"])
        target = media / result.name
        shutil.copy2(result, target)
        save(captures / "search-results" / locale / "export-result.json", dict(record, file=str(target)))
    completed.append(locale)
    save(root / "status.json", {"stage": "exporting", "completed": completed, "nativeRecaptured": False})
if args.publish:
    subprocess.run([sys.executable, str(repo / "Scripts/publish-marketing-ios-finals.py")], cwd=repo, check=True)
save(root / "status.json", {"stage": "published" if args.publish else "ready for visual review",
                           "completed": completed, "nativeRecaptured": False, "approvedThumbnailSHA256": thumbnail_hash})
print(root)
