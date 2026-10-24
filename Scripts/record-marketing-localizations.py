#!/usr/bin/env python3
"""Capture prepared localized marketing apps from a GUI Terminal session."""
import argparse
import json
import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--apps", type=Path, nargs="+", required=True)
parser.add_argument("--story", choices=["sync", "screenshot-1", "screenshot-2", "screenshot-3", "screenshot-4", "screenshot-5", "screenshot-6"], default="sync")
args = parser.parse_args()
is_screenshot = args.story.startswith("screenshot-")
scripts = Path(__file__).resolve().parent
destination = scripts.parent / "Marketing/Preview/Output/macOS-App-Store"
prepared = []
locales = set()
for path in args.apps:
    app = path.resolve(strict=True)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-preview"
    assert info["MarketingStory"] == args.story
    locale = info["MarketingLocale"]
    allowed_locales = {"en-US", "es-ES", "fr-FR", "zh-Hans"} if args.story in {"screenshot-2", "screenshot-3", "screenshot-4", "screenshot-5", "screenshot-6"} else {"es-ES", "fr-FR", "zh-Hans"}
    assert locale in allowed_locales and locale not in locales, locale
    locales.add(locale)
    if not is_screenshot or args.story == "screenshot-2":
        phone = Path(info["MarketingPhoneCaptureAppDirectory"])
        phone_info = plistlib.loads((phone / "Info.plist").read_bytes())
        assert phone_info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-phone"
        assert phone_info["MarketingLocale"] == locale
        if args.story == "screenshot-2":
            assert phone_info["MarketingStory"] == "screenshot-2"
    assert (app / "Contents/MacOS/Tildone").is_file()
    prepared.append((app, locale, Path(info["MarketingOutputDirectory"])))

environment = os.environ.copy()
environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + environment.get("PATH", "")
destination.mkdir(parents=True, exist_ok=True)
exports = []
completion = "ALL SCREENSHOTS FINISHED" if is_screenshot else "ALL RECORDINGS FINISHED"
print(f"Capturing {len(prepared)} languages. Please wait for {completion}.", flush=True)
if args.story == "screenshot-2":
    print("Preparing all iPhones first. You can keep using other apps during this step.", flush=True)
    for app, locale, _ in prepared:
        print(f"Preparing native iPhone: {locale}", flush=True)
        subprocess.run([sys.executable, str(scripts / "record-marketing-preview.py"),
                        "--app", str(app), "--prepare-phone-only"], check=True, env=environment)
    print("All iPhones are ready. Mac screenshots follow; after the first countdown, keep the screen idle until ALL SCREENSHOTS FINISHED.", flush=True)
for number, (app, locale, output) in enumerate(prepared, 1):
    print(f"\nLanguage {number}/{len(prepared)}: {locale}", flush=True)
    subprocess.run([sys.executable, str(scripts / "record-marketing-preview.py"),
                    "--app", str(app), "--batch"], check=True, env=environment)
    if is_screenshot:
        result = json.loads((output / "screenshot-result.json").read_text())
        assert result["asset"] == args.story and result["locale"] == locale
        source = output / result["file"]
    else:
        print("Exporting MP4. Another capture may follow; keep this Terminal running.", flush=True)
        subprocess.run([sys.executable, str(scripts / "export-marketing-preview.py"),
                        "--output", str(output)], check=True, env=environment)
        source = output / f"Tildone-macOS-preview-2-sync-{locale}.mp4"
    target = destination / source.name
    shutil.copy2(source, target)
    exports.append({"locale": locale, "file": str(target), "size_bytes": target.stat().st_size})

result_name = f"{args.story}-localizations-result.json" if is_screenshot else "preview-2-localizations-result.json"
(destination / result_name).write_text(
    json.dumps({"status": "complete", "exports": exports}, ensure_ascii=False, indent=2) + "\n")
reply = "captured" if is_screenshot else "recorded"
print(f"\n{completion}. You can use other apps again. Tell ChatGPT: {reply}.", flush=True)
for exported in exports:
    print(exported["file"], flush=True)
