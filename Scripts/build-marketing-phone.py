#!/usr/bin/env python3
"""Build a private simulator-only app using the production iPhone checklist UI."""
import argparse
import json
import os
import plistlib
import shutil
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--locale", choices=["en-US", "es-ES", "fr-FR", "zh-Hans"], default="en-US")
parser.add_argument("--story", choices=["sync", "screenshot-2"], default="sync")
parser.add_argument("--derived-data", type=Path, default=Path("/tmp/TildoneMarketingPhoneDerivedData"))
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
output = args.output.resolve()
derived = args.derived_data.resolve()
output.mkdir(parents=True, exist_ok=True)
command = [
    "xcodebuild", "-project", str(repo / "Tildone.xcodeproj"), "-scheme", "Tildone iOS",
    "-configuration", "Debug", "-sdk", "iphonesimulator", "-destination", "generic/platform=iOS Simulator",
    "-derivedDataPath", str(derived), "ARCHS=arm64", "CODE_SIGNING_ALLOWED=NO", "CODE_SIGN_ENTITLEMENTS=",
    "EXCLUDED_SOURCE_FILE_NAMES=TildoneIcon.icon", "ASSETCATALOG_COMPILER_APPICON_NAME=",
    "-packageCachePath", str(derived / "PackageCache"), "-IDEPackageSupportDisableManifestSandbox=YES",
    "PRODUCT_BUNDLE_IDENTIFIER=studio.cuatro.tildone.marketing-phone",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG MARKETING_CAPTURE",
    "OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox",
    "CLANG_MODULE_CACHE_PATH=/tmp/tildone-marketing-phone-module-cache",
    "SWIFT_MODULECACHE_PATH=/tmp/tildone-marketing-phone-module-cache", "build"
]
(output / "phone-build-command.json").write_text(json.dumps(command, indent=2) + "\n")
environment = os.environ.copy()
environment.update({
    "CLANG_MODULE_CACHE_PATH": "/tmp/tildone-marketing-phone-module-cache",
    "SWIFT_MODULECACHE_PATH": "/tmp/tildone-marketing-phone-module-cache",
    "SWIFTPM_MODULECACHE_OVERRIDE": "/tmp/tildone-marketing-phone-module-cache",
    "XDG_CACHE_HOME": str(derived / "Cache"), "CFFIXED_USER_HOME": str(derived / "BuildUser")
})
with (output / "phone-build.log").open("w") as log:
    result = subprocess.run(command, cwd=repo, env=environment, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    print(f"Build failed; inspect {output / 'phone-build.log'}")
    raise SystemExit(result.returncode)
apps = list((derived / "Build/Products/Debug-iphonesimulator").glob("*.app"))
assert len(apps) == 1, apps
app = output / "TildonePhonePreview.app"
shutil.copytree(apps[0], app, dirs_exist_ok=True)
info_path = app / "Info.plist"
with info_path.open("rb") as file:
    info = plistlib.load(file)
assert info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-phone"
info["CFBundleDisplayName"] = "Tildone Phone Preview"
info["MarketingLocale"] = args.locale
info["MarketingStory"] = args.story
info.pop("UIBackgroundModes", None)
with info_path.open("wb") as file:
    plistlib.dump(info, file)
print(app)
