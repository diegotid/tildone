#!/usr/bin/env python3
"""Build and capture the approved iPhone compositions without prepared session files."""
import argparse
import fcntl
import hashlib
import json
import os
import plistlib
import shutil
import signal
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
OUTPUT = REPO / "Marketing/Preview/Output"
CAPTURES = OUTPUT / "iOS/captures"
ASSETS = [f"screenshot-{n}" for n in range(1, 7)] + ["preview-1", "preview-2"]
LOCALES = ["en-US", "es-ES", "fr-FR", "zh-Hans"]
BUNDLE = "studio.cuatro.tildone.marketing-phone"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def run(command, log_path, timeout):
    with log_path.open("w") as log:
        process = subprocess.Popen(command, cwd=REPO, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except BaseException:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            raise
    if code:
        raise subprocess.CalledProcessError(code, command)


def cleanup_timed_out_capture(native):
    marker = native / "owned-capture-device.json"
    if not marker.exists():
        return
    owned = json.loads(marker.read_text())
    assert owned["owner"] == "Tildone-iPhone-Overnight" and owned["bundle"] == BUNDLE
    assert owned["shared"] is False
    for action in ["shutdown", "delete"]:
        subprocess.run(["xcrun", "simctl", action, owned["device"]], timeout=60,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True,
                        help="New iteration directory under Marketing/Preview/Output/iOS/revisions")
    parser.add_argument("--locales", choices=LOCALES, nargs="+", default=LOCALES)
    parser.add_argument("--assets", choices=ASSETS, nargs="+", default=ASSETS)
    parser.add_argument("--plan", action="store_true", help="Print commands and dependencies without writing or capturing")
    parser.add_argument("--check-inputs", action="store_true", help="Validate prerequisites without writing or capturing")
    args = parser.parse_args()
    root = args.output.resolve()
    if not root.is_relative_to(OUTPUT / "iOS/revisions") or root == OUTPUT / "iOS/revisions":
        parser.error("Use a new directory below Marketing/Preview/Output/iOS/revisions.")
    # Keep screenshot 2 before preview 2, whose opening consumes its native still.
    assets = [asset for asset in ASSETS if asset in args.assets]
    locales = [locale for locale in LOCALES if locale in args.locales]
    build = [sys.executable, str(REPO / "Scripts/build-marketing-phone.py"),
             "--output", str(root / "build"), "--story", "ios-preview-1", "--locale", "en-US",
             "--derived-data", str(root / "DerivedData")]
    inputs = []
    if {"screenshot-2", "preview-2"}.intersection(assets):
        for locale in locales:
            mac = OUTPUT / "screenshots/02" / locale
            inputs += [mac / "screenshot-result.json", mac / f"Tildone-macOS-screenshot-02-{locale}.png",
                       mac / "phone-frames/phone-capture-verification.json",
                       mac / "TildonePreviewStudio.app/Contents/Resources/GoldenGate.png"]
            if "screenshot-2" not in assets:
                inputs.append(CAPTURES / "screenshot-2" / locale / "export-result.json")
    missing = [str(path) for path in inputs if not path.is_file()]
    missing_tools = [tool for tool in ["xcodebuild", "xcrun", "swift", "ffmpeg", "ffprobe", "sips"]
                     if shutil.which(tool) is None]
    wallpaper_hash = json.loads((REPO / "Marketing/Preview/Inputs/manifest.json").read_text())["externalInputs"][0]["sha256"]
    mismatches = [str(path) for path in inputs if path.name == "GoldenGate.png"
                  and path.is_file() and digest(path) != wallpaper_hash]
    jobs = []
    for locale in locales:
        for asset in assets:
            directory = root / asset / locale
            native = directory / "native"
            export = [sys.executable, str(REPO / "Scripts/export-marketing-ios-asset.py"),
                      "--asset", asset, "--locale", locale, "--native", str(native),
                      "--output", str(directory), "--repair"]
            if asset == "screenshot-3":
                export += ["--deck-native", str(native / "deck")]
            jobs.append({"asset": asset, "locale": locale, "directory": str(directory),
                         "capture": [sys.executable, str(REPO / "Scripts/capture-marketing-phone.py"),
                                     "--app", str(directory / "TildonePhonePreview.app"),
                                     "--output", str(native), "--fresh-device"], "export": export,
                         "info": {"MarketingStory": "ios-" + asset, "MarketingLocale": locale,
                                  "MarketingCaptureBothLayouts": asset == "screenshot-3"}})
    plan = {"build": build, "jobs": jobs, "requiredInputs": [str(path) for path in inputs],
            "missingInputs": missing, "missingTools": missing_tools, "wallpaperHashMismatches": mismatches,
            "macRecaptureAutomatic": False, "idleScreenRequired": False,
            "note": "Mac prerequisites require separately scheduled GUI capture; see Marketing/README.md."}
    if args.plan:
        print(json.dumps(plan, indent=2))
        return
    if missing or missing_tools or mismatches:
        parser.error("Missing or incorrect prerequisites; inspect --plan. No capture started.")
    if args.check_inputs:
        print(f"Prerequisites verified for {len(jobs)} captures; no files written or capture started.")
        return
    if root.exists():
        parser.error("Iteration directory exists. Choose a new name to preserve previous versions.")
    CAPTURES.mkdir(parents=True, exist_ok=True)
    with (CAPTURES / "suite-worker.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        root.mkdir(parents=True)
        write_json(root / "plan.json", plan)
        mac_media = OUTPUT / "macOS-App-Store"
        baseline = {str(path.relative_to(mac_media)): digest(path) for path in sorted(mac_media.rglob("*"))
                    if path.is_file() and path.suffix.lower() in {".png", ".mp4"}}
        write_json(root / "mac-media-baseline.json", baseline)
        results = {}
        def checkpoint(stage):
            write_json(root / "status.json", {"stage": stage, "completed": list(results), "total": len(jobs)})
        try:
            checkpoint("building private native capture app")
            run(build, root / "build-console.log", 900)
            base = root / "build/TildonePhonePreview.app"
            for job in jobs:
                asset, locale = job["asset"], job["locale"]
                directory = Path(job["directory"])
                directory.mkdir(parents=True)
                canonical = CAPTURES / asset / locale / "export-result.json"
                if canonical.exists():
                    previous = json.loads(canonical.read_text())
                    source = Path(previous["file"])
                    assert digest(source) == previous["sha256"]
                    backup = directory / "previous-final"
                    backup.mkdir()
                    shutil.copy2(source, backup / source.name)
                    previous["file"] = str(backup / source.name)
                    write_json(backup / "export-result.json", previous)
                app = directory / "TildonePhonePreview.app"
                shutil.copytree(base, app)
                info_path = app / "Info.plist"
                info = plistlib.loads(info_path.read_bytes())
                assert info["CFBundleIdentifier"] == BUNDLE
                info.update(job["info"])
                info.pop("MarketingOverviewLayout", None)
                info_path.write_bytes(plistlib.dumps(info))
                checkpoint("capturing " + asset + "/" + locale)
                try:
                    run(job["capture"], directory / "capture.log", 600)
                except BaseException:
                    cleanup_timed_out_capture(directory / "native")
                    raise
                checkpoint("rendering " + asset + "/" + locale)
                run(job["export"], directory / "export.log", 600)
                record = json.loads((directory / "export-result.json").read_text())
                assert record["verified"] and digest(Path(record["file"])) == record["sha256"]
                # The iteration retains its own immutable media and original result.
                canonical.parent.mkdir(parents=True, exist_ok=True)
                write_json(canonical, record)
                results[asset + "/" + locale] = record
                archived = dict(record, file=str(directory / Path(record["file"]).name))
                assert digest(Path(archived["file"])) == record["sha256"]
                write_json(directory / "export-result.json", archived)
                write_json(root / "suite-result.json", {"results": results, "requiresVisualReview": True})
                for name, expected in baseline.items():
                    assert digest(mac_media / name) == expected, name
            checkpoint("ready for visual review; delivery requires publish-marketing-ios-finals.py")
        except BaseException:
            checkpoint("failed; inspect build/capture/export logs")
            raise
    print(root)
    print("Capture and format verification complete. Review before publishing the final delivery folder.")


if __name__ == "__main__":
    main()
