#!/usr/bin/env python3
"""Build a private, unsigned mock-data capture app. Never starts the customer app."""
import argparse
import json
import os
import plistlib
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--wallpaper", type=Path, required=True)
parser.add_argument("--output", type=Path, default=Path("Marketing/Preview/Output"))
parser.add_argument("--derived-data", type=Path, default=Path("/tmp/TildoneMarketingDerivedData"))
parser.add_argument("--locale", choices=["en-US", "es-ES", "fr-FR", "zh-Hans"], default="en-US")
parser.add_argument("--story", choices=["desktop", "sync", "screenshot-1", "screenshot-2", "screenshot-3", "screenshot-4"], default="desktop")
parser.add_argument("--phone-frames", type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
wallpaper = args.wallpaper.resolve(strict=True)
output = args.output.resolve()
derived = args.derived_data.resolve()
output.mkdir(parents=True, exist_ok=True)
command = [
    "xcodebuild", "-project", str(repo / "Tildone.xcodeproj"), "-scheme", "Tildone",
    "-configuration", "Debug", "-destination", "platform=macOS,arch=arm64",
    "-derivedDataPath", str(derived), "CODE_SIGNING_ALLOWED=NO",
    "-packageCachePath", str(derived / "PackageCache"),
    "-IDEPackageSupportDisableManifestSandbox=YES",
    "CODE_SIGN_ENTITLEMENTS=", "ENABLE_APP_SANDBOX=NO",
    "EXCLUDED_SOURCE_FILE_NAMES=TildoneIcon.icon", "ASSETCATALOG_COMPILER_APPICON_NAME=",
    "PRODUCT_BUNDLE_IDENTIFIER=studio.cuatro.tildone.marketing-preview",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG MARKETING_CAPTURE",
    "OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox",
    "CLANG_MODULE_CACHE_PATH=/tmp/tildone-marketing-module-cache",
    "SWIFT_MODULECACHE_PATH=/tmp/tildone-marketing-module-cache",
    "build",
]
(output / "build-command.json").write_text(json.dumps(command, indent=2) + "\n")
with (output / "build.log").open("w") as log:
    environment = os.environ.copy()
    environment.update({
        "CLANG_MODULE_CACHE_PATH": "/tmp/tildone-marketing-module-cache",
        "SWIFT_MODULECACHE_PATH": "/tmp/tildone-marketing-module-cache",
        "SWIFTPM_MODULECACHE_OVERRIDE": "/tmp/tildone-marketing-module-cache",
        "XDG_CACHE_HOME": str(derived / "Cache"),
        "CFFIXED_USER_HOME": str(derived / "BuildUser"),
    })
    result = subprocess.run(command, cwd=repo, env=environment, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    print(f"Build failed; inspect {output / 'build.log'}")
    raise SystemExit(result.returncode)
app = derived / "Build/Products/Debug/TildonePreviewStudio.app"
shutil.copytree(derived / "Build/Products/Debug/Tildone.app", app, dirs_exist_ok=True)
info_path = app / "Contents/Info.plist"
with info_path.open("rb") as file:
    info = plistlib.load(file)
assert info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-preview"
info["CFBundleDisplayName"] = "Tildone Preview Studio"
info["CFBundleName"] = "Tildone Preview Studio"
info["MarketingOutputDirectory"] = str(output)
info["MarketingLocale"] = args.locale
info["MarketingStory"] = args.story
info["MarketingRecordScript"] = str(repo / "Scripts/record-marketing-preview.py")
if args.story in {"sync", "screenshot-2"}:
    info["MarketingPhoneFramesDirectory"] = str((args.phone_frames or output / "phone-frames").resolve())
    info["MarketingPhoneCaptureAppDirectory"] = str(output / "TildonePhonePreview.app")
with info_path.open("wb") as file:
    plistlib.dump(info, file)
shutil.copy2(wallpaper, app / "Contents/Resources/GoldenGate.png")
(output / "capture-status.txt").write_text("BUILT")
(output / "capture-result.json").unlink(missing_ok=True)
print(app)
print("Launch this private app to capture the native screenshot." if args.story.startswith("screenshot-")
      else "Launch this private app to render and record the disposable 30-second scene.")
