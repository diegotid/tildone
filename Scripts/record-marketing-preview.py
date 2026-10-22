#!/usr/bin/env python3
"""GUI-session launcher for native phone fixtures, then the self-recording Mac app."""
import argparse
import hashlib
import json
import plistlib
import subprocess
import sys
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--app", type=Path, required=True)
args = parser.parse_args()
app = args.app.resolve(strict=True)
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-preview"
output = Path(info["MarketingOutputDirectory"])
if info.get("MarketingStory") == "sync":
    phone_app = Path(info["MarketingPhoneCaptureAppDirectory"])
    phone_info = plistlib.loads((phone_app / "Info.plist").read_bytes())
    assert phone_info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-phone"
    assert phone_info["MarketingLocale"] == info["MarketingLocale"]
    digest = hashlib.sha256()
    for file in sorted(phone_app.rglob("*")):
        if file.is_file():
            digest.update(str(file.relative_to(phone_app)).encode())
            digest.update(file.read_bytes())
    digest.update(Path(__file__).with_name("capture-marketing-phone.py").read_bytes())
    fingerprint = digest.hexdigest()
    frames = Path(info["MarketingPhoneFramesDirectory"])
    verification_path = frames / "phone-capture-verification.json"
    cached = json.loads(verification_path.read_text()) if verification_path.exists() else {}
    valid = (cached.get("phoneAppFingerprint") == fingerprint and cached.get("storyRevision") == 7
             and cached.get("nativeTitleVisible") and cached.get("phoneSyncIndicatorConnected")
             and (frames / "phone-native.mp4").exists())
    if not valid:
        subprocess.run([sys.executable, str(Path(__file__).with_name("capture-marketing-phone.py")),
                        "--app", str(phone_app), "--output", str(frames)], check=True)
        verification = json.loads(verification_path.read_text())
        verification["phoneAppFingerprint"] = fingerprint
        verification_path.write_text(json.dumps(verification, ensure_ascii=False, indent=2) + "\n")
print("Phone preparation complete. Mac capture starts in 10 seconds.", flush=True)
print("Please leave the screen idle until the preview closes (about 35 seconds).", flush=True)
time.sleep(10)
(output / "capture-status.txt").write_text("LAUNCHING")
(output / "capture-result.json").unlink(missing_ok=True)
subprocess.run(["/usr/bin/open", "-n", str(app)], check=True)
deadline = time.monotonic() + 90
while time.monotonic() < deadline:
    status = (output / "capture-status.txt").read_text()
    if status == "COMPLETE":
        print("Capture finished. You can use other apps again. Tell ChatGPT: recorded.", flush=True)
        break
    if status.startswith("ERROR"):
        raise RuntimeError(status)
    time.sleep(0.25)
else:
    raise TimeoutError("The Mac capture did not finish. You can use other apps again.")
