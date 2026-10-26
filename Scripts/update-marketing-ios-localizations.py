#!/usr/bin/env python3
"""Replicate the approved iPhone iteration into the other three locales."""
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
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
root = args.output.resolve()
root.mkdir(parents=True, exist_ok=True)
lock = (root / "localization-worker.lock").open("w")
fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
captures = repo / "Marketing/Preview/Output/iOS/captures"
media = repo / "Marketing/Preview/Output/iOS-App-Store"
registry = captures / "capture-device.json"
locales = ["es-ES", "fr-FR", "zh-Hans"]
assets = ["screenshot-2", "preview-1", "preview-2", "screenshot-3", "screenshot-6"]
completed = {}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def status(stage, asset=None, locale=None, error=None):
    path = root / "status.json"
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps({"stage": stage, "asset": asset, "locale": locale,
        "completed": list(completed), "total": len(assets) * len(locales),
        "englishConsolidated": True, "localizationAuthorized": True, "error": error}, indent=2) + "\n")
    temporary.replace(path)


def run(command, log=None, timeout=420):
    process = subprocess.Popen(command, cwd=repo, stdout=log, stderr=subprocess.STDOUT if log else None,
                               start_new_session=True)
    try:
        code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        raise
    if code:
        raise subprocess.CalledProcessError(code, command)


def sdk(*arguments, timeout=20, check=False):
    return subprocess.run(["xcrun", "simctl", *arguments], capture_output=True, text=True,
                          check=check, timeout=timeout)


def clean_owned_device():
    if not registry.exists():
        return
    owned = json.loads(registry.read_text())
    assert owned["owner"] == "Tildone-iPhone-Overnight" and owned["bundle"] == "studio.cuatro.tildone.marketing-phone"
    sdk("shutdown", owned["device"], timeout=25)
    sdk("delete", owned["device"], timeout=25, check=True)
    registry.replace(root / f"capture-device-cleaned-{time.time_ns()}.json")


def archive_previous(asset, locale, directory):
    old = json.loads((captures / asset / locale / "export-result.json").read_text())
    backup = directory / "previous-final"
    backup.mkdir(parents=True, exist_ok=True)
    if not (backup / "export-result.json").exists():
        target = backup / Path(old["file"]).name
        shutil.copy2(old["file"], target)
        assert digest(target) == old["sha256"]
        old["file"] = str(target)
        (backup / "export-result.json").write_text(json.dumps(old, ensure_ascii=False, indent=2) + "\n")


try:
    status("building private native capture app")
    base = root / "build/TildonePhonePreview.app"
    if not base.exists():
        with (root / "build-console.log").open("w") as log:
            run([sys.executable, "Scripts/build-marketing-phone.py", "--output", str(root / "build"),
                 "--story", "ios-preview-1", "--locale", "en-US"], log)
    for asset in assets:
        for locale in locales:
            key = asset + "/" + locale
            directory = root / asset / locale
            directory.mkdir(parents=True, exist_ok=True)
            saved_path = directory / "export-result.json"
            canonical_path = captures / asset / locale / "export-result.json"
            current = json.loads(canonical_path.read_text())
            current_revision = Path(current.get("revisionDirectory", captures))
            if (current.get("approvedEnglishIteration") == root.name and current_revision.is_relative_to(root)
                    and Path(current["file"]).is_file() and digest(Path(current["file"])) == current["sha256"]):
                completed[key] = current
                continue
            if saved_path.exists():
                saved = json.loads(saved_path.read_text())
                canonical = captures / asset / locale / "export-result.json"
                if (Path(saved["file"]).is_file() and digest(Path(saved["file"])) == saved["sha256"]
                        and json.loads(canonical.read_text())["sha256"] == saved["sha256"]):
                    completed[key] = saved
                    continue
            archive_previous(asset, locale, directory)
            if asset == "screenshot-2":
                record = json.loads((captures / asset / locale / "export-result.json").read_text())
                native = Path(record["nativeProof"]).parent
            else:
                app = directory / "TildonePhonePreview.app"
                if not app.exists():
                    shutil.copytree(base, app, copy_function=os.link)
                info = plistlib.loads((base / "Info.plist").read_bytes())
                info.update(MarketingLocale=locale, MarketingStory="ios-" + asset,
                            MarketingCaptureBothLayouts=asset == "screenshot-3")
                if asset == "screenshot-3":
                    info["MarketingOverviewLayout"] = "grid"
                else:
                    info.pop("MarketingOverviewLayout", None)
                temporary = app / "MarketingInfo.tmp"
                temporary.write_bytes(plistlib.dumps(info))
                temporary.replace(app / "Info.plist")
                existing = [int(p.name.split("-")[-1]) for p in directory.glob("native-*")
                            if p.name.split("-")[-1].isdigit()]
                first = max(existing, default=0) + 1
                for attempt in range(3):
                    index = first + attempt
                    native = directory / f"native-{index}"
                    status("capturing native SwiftUI", asset, locale)
                    try:
                        with (directory / f"capture-{index}.log").open("w") as log:
                            run([sys.executable, "Scripts/capture-marketing-phone.py", "--app", str(app),
                                 "--output", str(native)], log, timeout=420)
                        break
                    except (subprocess.SubprocessError, OSError):
                        print("Recovering task-owned capture:", key, "attempt", attempt + 1, flush=True)
                        clean_owned_device()
                        if (native / "phone-capture-verification.json").exists():
                            if asset != "screenshot-3" or (native / "deck/phone-capture-verification.json").exists():
                                break
                        if attempt == 2:
                            raise
            status("rendering approved composition", asset, locale)
            command = [sys.executable, "Scripts/export-marketing-ios-asset.py", "--asset", asset,
                       "--locale", locale, "--native", str(native), "--output", str(directory), "--repair"]
            if asset == "screenshot-3":
                command += ["--deck-native", str(native / "deck")]
            with (directory / "export.log").open("w") as log:
                run(command, log, timeout=240)
            record = json.loads(saved_path.read_text())
            record.update(approved=True, approvedEnglishIteration=root.name, revisionDirectory=str(directory))
            canonical = captures / asset / locale
            (canonical / "export-result.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
            for review in directory.glob("review*.png"):
                shutil.copy2(review, canonical / review.name)
            archived = dict(record)
            archived["file"] = str(directory / Path(record["file"]).name)
            assert digest(Path(archived["file"])) == record["sha256"]
            saved_path.write_text(json.dumps(archived, ensure_ascii=False, indent=2) + "\n")
            completed[key] = archived
            run([sys.executable, "Scripts/publish-marketing-ios-finals.py"], timeout=60)
            status("localized final verified and delivered", asset, locale)
            print("Localized final verified:", key, len(completed), "/", len(assets) * len(locales), flush=True)
    clean_owned_device()
    (root / "localized-results.json").write_text(json.dumps(completed, ensure_ascii=False, indent=2) + "\n")
    status("localized finals ready for visual audit")
except Exception as error:
    status("failed", error=str(error))
    raise
finally:
    if registry.exists():
        clean_owned_device()
