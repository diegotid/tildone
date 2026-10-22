#!/usr/bin/env python3
"""Record and export prepared localized preview apps from a GUI Terminal session."""
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
args = parser.parse_args()
scripts = Path(__file__).resolve().parent
destination = scripts.parent / "Marketing/Preview/Output/macOS-App-Store"
prepared = []
locales = set()
for path in args.apps:
    app = path.resolve(strict=True)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-preview"
    assert info["MarketingStory"] == "sync"
    locale = info["MarketingLocale"]
    assert locale in {"es-ES", "fr-FR", "zh-Hans"} and locale not in locales, locale
    locales.add(locale)
    phone = Path(info["MarketingPhoneCaptureAppDirectory"])
    phone_info = plistlib.loads((phone / "Info.plist").read_bytes())
    assert phone_info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-phone"
    assert phone_info["MarketingLocale"] == locale
    assert (app / "Contents/MacOS/Tildone").is_file()
    prepared.append((app, locale, Path(info["MarketingOutputDirectory"])))

environment = os.environ.copy()
environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + environment.get("PATH", "")
destination.mkdir(parents=True, exist_ok=True)
exports = []
print(f"Recording {len(prepared)} languages. Please wait for ALL RECORDINGS FINISHED.", flush=True)
for number, (app, locale, output) in enumerate(prepared, 1):
    print(f"\nLanguage {number}/{len(prepared)}: {locale}", flush=True)
    subprocess.run([sys.executable, str(scripts / "record-marketing-preview.py"),
                    "--app", str(app), "--batch"], check=True, env=environment)
    print("Exporting MP4. Another capture may follow; keep this Terminal running.", flush=True)
    subprocess.run([sys.executable, str(scripts / "export-marketing-preview.py"),
                    "--output", str(output)], check=True, env=environment)
    source = output / f"Tildone-macOS-preview-2-sync-{locale}.mp4"
    target = destination / source.name
    shutil.copy2(source, target)
    exports.append({"locale": locale, "file": str(target), "size_bytes": target.stat().st_size})

(destination / "preview-2-localizations-result.json").write_text(
    json.dumps({"status": "complete", "exports": exports}, ensure_ascii=False, indent=2) + "\n")
print("\nALL RECORDINGS FINISHED. You can use other apps again. Tell ChatGPT: recorded.", flush=True)
for exported in exports:
    print(exported["file"], flush=True)
