#!/usr/bin/env python3
"""Legacy screenshot-1 helper for prepared apps; prefer run-marketing-ios-suite.py."""
import argparse
import hashlib
import json
import plistlib
import shutil
import struct
import subprocess
import sys
import traceback
from pathlib import Path

LOCALES = ["en-US", "es-ES", "fr-FR", "zh-Hans"]
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
output = args.output.resolve()
final = repo / "Marketing/Preview/Output/iOS-App-Store"
final.mkdir(parents=True, exist_ok=True)
status = output / "batch-status.txt"
result_path = output / "batch-result.json"
source = output / "en-US/TildonePhonePreview.app"
source_info = plistlib.loads((source / "Info.plist").read_bytes())
assert source_info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-phone"
assert source_info["MarketingStory"] == "ios-screenshot-1"

def png_info(path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    width, height, depth, color = struct.unpack(">IIBB", data[16:26])
    assert (width, height) == (1320, 2868) and depth == 8 and color == 2, (path, width, height, depth, color)
    return hashlib.sha256(data).hexdigest()

results = []
status.write_text("PREPARING")
print("Capture only: four disposable iPhone simulators; no physical iPhone or live iCloud.", flush=True)
print("You can keep using your screen throughout. No fullscreen or desktop capture is used.", flush=True)
try:
    for locale in LOCALES:
        directory = output / locale
        directory.mkdir(parents=True, exist_ok=True)
        app = directory / "TildonePhonePreview.app"
        if locale != "en-US":
            shutil.copytree(source, app, dirs_exist_ok=True)
        info = plistlib.loads((app / "Info.plist").read_bytes())
        info["MarketingLocale"] = locale
        (app / "Info.plist").write_bytes(plistlib.dumps(info))
        status.write_text("CAPTURING " + locale)
        print("Capturing " + locale, flush=True)
        with (directory / "capture-launcher.log").open("w") as log:
            subprocess.run([sys.executable, str(repo / "Scripts/capture-marketing-phone.py"),
                            "--app", str(app), "--output", str(directory / "native")],
                           check=True, stdout=log, stderr=subprocess.STDOUT)
        proof = json.loads((directory / "native/phone-capture-verification.json").read_text())
        assert proof["verified"] and proof["taskCount"] == 4 and proof["allTasksVisible"], proof
        assert proof["locale"] == locale and proof["mockDataOnly"] and not proof["cloudKitStarted"], proof
        name = f"Tildone-iOS-screenshot-01-{locale}.png"
        image = directory / name
        subprocess.run(["swift", "-disable-sandbox", "-module-cache-path", "/tmp/tildone-marketing-module-cache",
                        str(repo / "Scripts/render-marketing-ios-thumbnail.swift"),
                        str(directory / "native/phone-checklist.png"), str(image), locale, "3"], check=True)
        digest = png_info(image)
        shutil.copy2(image, final / name)
        # Review-sized native thumbnail for visual QA of every translation.
        subprocess.run(["sips", "-Z", "956", str(image), "--out", str(directory / "review.png")],
                       check=True, stdout=subprocess.DEVNULL)
        results.append({"locale": locale, "file": str(final / name), "sha256": digest,
                        "nativeProof": str(directory / "native/phone-capture-verification.json"),
                        "renderProof": str(image.with_suffix('.json')), "taskCount": 4,
                        "completedTaskCount": 1, "mockDataOnly": True, "cloudKitStarted": False})
        result_path.write_text(json.dumps({"status": "in-progress", "results": results}, ensure_ascii=False, indent=2) + "\n")
    result_path.write_text(json.dumps({"status": "succeeded", "asset": "ios-screenshot-1", "results": results,
                                      "requiresVisualReview": True}, ensure_ascii=False, indent=2) + "\n")
    shutil.copy2(result_path, final / "screenshot-1-localizations-result.json")
    status.write_text("ALL IPHONE SCREENSHOTS FINISHED")
    print("ALL IPHONE SCREENSHOTS FINISHED", flush=True)
    print(final, flush=True)
except Exception:
    status.write_text("FAILED")
    result_path.write_text(json.dumps({"status": "failed", "results": results,
                                      "error": traceback.format_exc()}, ensure_ascii=False, indent=2) + "\n")
    raise
