#!/usr/bin/env python3
"""Export approved Header compositions from existing localized native captures."""
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
parser.add_argument("--native-root", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--approved-thumbnail", type=Path, required=True)
parser.add_argument("--publish", action="store_true", help="Publish after localized visual review")
args = parser.parse_args()
root = args.output.resolve()
native_root = args.native_root.resolve(strict=True)
assert root.is_relative_to(repo / "Marketing/Preview/Output/iOS/creative/header")
thumbnail = args.approved_thumbnail.resolve(strict=True)
proof = json.loads(thumbnail.with_suffix(".json").read_text())
assert proof["asset"] == "header" and proof["locale"] == "en-US" and proof["revision"] in [7, 9, 11]
revision = proof["revision"]
layout_option = {7: "--crop-safe-review", 9: "--spacing-review", 11: "--large-text-review"}[revision]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, record):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def pixels(path):
    return subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(path),
                                    "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])


thumbnail_hash = digest(thumbnail)
assert thumbnail_hash == proof["sha256"]
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
        common = ["--asset", "header", "--native-root", str(native), layout_option]
        if locale == "en-US":
            comparison = directory / "approved-shape-check.png"
            subprocess.run([str(renderer), str(comparison), *common], cwd=repo, check=True, timeout=180)
            original, rendered = pixels(thumbnail), pixels(comparison)
            assert len(original) == len(rendered)
            differences = [abs(a - b) for a, b in zip(original, rendered)]
            assert max(differences) <= 1 and sum(d != 0 for d in differences) < 100
            save(directory / "approved-shape-comparison.json", {
                "maxChannelDifference": max(differences), "changedChannels": sum(d != 0 for d in differences),
                "approvedThumbnailSHA256": thumbnail_hash})
        result = directory / f"Tildone-iOS-header-{locale}.png"
        subprocess.run([str(renderer), str(result), *common, "--locale", locale, "--full"],
                       cwd=repo, check=True, timeout=180)
        record = json.loads(result.with_suffix(".json").read_text())
        assert record["approved"] and not record["draft"] and record["locale"] == locale
        assert record["macKeyboardAndTrackpadPerspective"]
        if revision == 11:
            assert not record["captionInsideHeaderSafeArea"]
            record["captionOutsideTemplateSafeAreaApproved"] = True
        else:
            assert record["essentialContentInsideHeaderSafeArea"]
        assert struct.unpack(">IIBB", result.read_bytes()[16:26]) == (3840, 1646, 8, 2)
        assert digest(result) == record["sha256"]
        record.update(file=str(result), revisionDirectory=str(directory), renderProof=str(result.with_suffix(".json")),
                      approvedThumbnailSHA256=thumbnail_hash, approvedRevision=f"r{revision}", reusedNativeCaptures=True)
        save(path, record)
        shutil.copy2(source, directory / "renderer-full-source.swift")
        for name, filters in [("full-review.png", "scale=1280:-1"),
                              ("safe-area-review.png", "crop=1646:661:1097:493,scale=1317:-1")]:
            subprocess.run(["ffmpeg", "-v", "error", "-i", str(result), "-vf", filters,
                            "-frames:v", "1", "-y", str(directory / name)], check=True)
    if args.publish:
        result = Path(record["file"])
        target = media / result.name
        shutil.copy2(result, target)
        save(captures / "header" / locale / "export-result.json", dict(record, file=str(target)))
    completed.append(locale)
    save(root / "status.json", {"stage": "exporting", "completed": completed, "nativeRecaptured": False})
if args.publish:
    subprocess.run([sys.executable, str(repo / "Scripts/publish-marketing-ios-finals.py")], cwd=repo, check=True)
save(root / "status.json", {"stage": "published" if args.publish else "ready for visual review",
                           "completed": completed, "nativeRecaptured": False, "approvedThumbnailSHA256": thumbnail_hash})
print(root)
