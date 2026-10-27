#!/usr/bin/env python3
"""Localize an approved Header using private native fixture app copies."""
import argparse
import fcntl
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--phone-app", type=Path, required=True)
parser.add_argument("--mac-app", type=Path, required=True)
parser.add_argument("--renderer", type=Path, required=True)
args = parser.parse_args()
root = args.output.resolve()
captures = repo / "Marketing/Preview/Output/iOS/captures"
media = repo / "Marketing/Preview/Output/iOS-App-Store"
registry = captures / "capture-device.json"
locales = ["es-ES", "fr-FR", "zh-Hans"]
phone_base = args.phone_app.resolve(strict=True)
mac_base = args.mac_app.resolve(strict=True)
phone_info = plistlib.loads((phone_base / "Info.plist").read_bytes())
mac_info = plistlib.loads((mac_base / "Contents/Info.plist").read_bytes())
assert phone_info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-phone"
assert phone_info["MarketingStory"] == "ios-screenshot-header"
assert mac_info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-preview"
assert mac_info["MarketingStory"] == "header"
fixture = (repo / "Marketing/Preview/Inputs/header-note.json").read_bytes()
assert (phone_base / "HeaderNote.json").read_bytes() == fixture
assert (mac_base / "Contents/Resources/HeaderNote.json").read_bytes() == fixture
english = json.loads((captures / "header/en-US/export-result.json").read_text())
assert english["approved"] and english["verified"] and not english["draft"]
layout_options = {4: [], 7: ["--crop-safe-review"], 9: ["--spacing-review"], 11: ["--large-text-review"]}
assert english["revision"] in layout_options, "Unknown approved Header layout."
layout = layout_options[english["revision"]]
assert root.is_relative_to(repo / "Marketing/Preview/Output/iOS/creative/header")
root.mkdir(parents=True, exist_ok=True)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(path)


def run(command, log, timeout=420, env=None):
    with log.open("w") as output:
        subprocess.run(command, cwd=repo, stdout=output, stderr=subprocess.STDOUT,
                       check=True, timeout=timeout, env=env)


def cleanup_device():
    if not registry.exists():
        return
    owned = json.loads(registry.read_text())
    assert owned["owner"] == "Tildone-iPhone-Overnight" and owned["bundle"] == "studio.cuatro.tildone.marketing-phone"
    for action in ["shutdown", "delete"]:
        subprocess.run(["xcrun", "simctl", action, owned["device"]], check=action == "delete",
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
    registry.replace(root / "cleaned-capture-device.json")


completed = []
with (captures / "suite-worker.lock").open("a") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    assert not registry.exists(), "Another task-owned capture device is already registered."
    try:
        for locale in locales:
            directory = root / locale
            saved = directory / "export-result.json"
            if saved.exists():
                record = json.loads(saved.read_text())
                assert record["approvedEnglishSHA256"] == english["sha256"], "Use a new iteration for changed English artwork."
                assert digest(Path(record["file"])) == record["sha256"]
                completed.append(locale)
                continue
            directory.mkdir(parents=True, exist_ok=True)
            save(root / "localization-status.json", {"stage": "capturing", "locale": locale, "completed": completed})
            phone = directory / "phone-build/TildonePhonePreview.app"
            mac = directory / "mac-build/TildonePreviewStudio.app"
            if not phone.exists():
                shutil.copytree(phone_base, phone)
            if not mac.exists():
                shutil.copytree(mac_base, mac)
            info = dict(phone_info, MarketingLocale=locale)
            (phone / "Info.plist").write_bytes(plistlib.dumps(info))
            native_mac = directory / "mac-native"
            native_mac.mkdir(exist_ok=True)
            info = dict(mac_info, MarketingLocale=locale, MarketingOutputDirectory=str(native_mac))
            (mac / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            env = os.environ.copy()
            env["LLVM_PROFILE_FILE"] = str(native_mac / "capture-%p.profraw")
            run([str(mac / "Contents/MacOS/Tildone")], directory / "mac-capture.log", 120, env)
            assert json.loads((native_mac / "mac-note.json").read_text())["locale"] == locale
            run([sys.executable, str(repo / "Scripts/capture-marketing-phone.py"), "--app", str(phone),
                 "--output", str(directory / "phone-native")], directory / "phone-capture.log")
            result_file = directory / f"Tildone-iOS-header-{locale}.png"
            command = [str(args.renderer.resolve()), str(result_file), "--native-root", str(directory),
                       "--locale", locale, "--full", *layout]
            run(command, directory / "render.log", 180)
            record = json.loads(result_file.with_suffix(".json").read_text())
            assert record["approved"] and not record["draft"] and record["locale"] == locale
            assert digest(result_file) == record["sha256"]
            target = media / result_file.name
            shutil.copy2(result_file, target)
            record.update(file=str(target), revisionDirectory=str(directory), renderProof=str(result_file.with_suffix(".json")),
                          approvedEnglishSHA256=english["sha256"], approvedRevision=f"r{english['revision']}")
            if english.get("captionOutsideTemplateSafeAreaApproved"):
                assert not record["captionInsideHeaderSafeArea"]
                record["captionOutsideTemplateSafeAreaApproved"] = True
            save(directory / "export-result.json", dict(record, file=str(result_file)))
            save(captures / "header" / locale / "export-result.json", record)
            assert digest(Path(english["file"])) == english["sha256"]
            completed.append(locale)
        save(root / "localization-status.json", {"stage": "ready for visual review", "completed": completed})
    except Exception:
        save(root / "localization-status.json", {"stage": "failed", "completed": completed})
        raise
    finally:
        cleanup_device()
print(root)
