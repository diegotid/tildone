#!/usr/bin/env python3
"""GUI-session launcher for native phone fixtures, then the self-recording Mac app."""
import argparse
import hashlib
import json
import plistlib
import subprocess
import shutil
import struct
import sys
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--app", type=Path, required=True)
parser.add_argument("--batch", action="store_true", help="Let a batch launcher report final completion.")
parser.add_argument("--prepare-phone-only", action="store_true", help="Prepare screenshot 2's native phone before a batch of Mac captures.")
args = parser.parse_args()
app = args.app.resolve(strict=True)
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-preview"
if args.prepare_phone_only:
    assert info.get("MarketingStory") == "screenshot-2"
output = Path(info["MarketingOutputDirectory"])
if info.get("MarketingStory") in {"sync", "screenshot-2"}:
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
    if info["MarketingStory"] == "screenshot-2":
        assert phone_info.get("MarketingStory") == "screenshot-2"
        valid = (cached.get("phoneAppFingerprint") == fingerprint and cached.get("screenshotRevision") == 3
                 and cached.get("nativeView") == "NotesDeckView" and cached.get("bothDeckPreviewsVisible")
                 and cached.get("deckContentAboveCrop") and cached.get("cropAboveSearchY")
                 and cached.get("noteCount") == 4 and cached.get("deckCount") == 2
                 and cached.get("nativeTitleVisible") and cached.get("softwareKeyboardHidden")
                 and cached.get("phoneSyncIndicatorConnected") and cached.get("locale") == info["MarketingLocale"]
                 and (frames / "phone-shared.png").exists() and (frames / "phone-screenshot-result.json").exists())
    else:
        valid = (cached.get("phoneAppFingerprint") == fingerprint and cached.get("storyRevision") == 7
                 and cached.get("nativeTitleVisible") and cached.get("phoneSyncIndicatorConnected")
                 and (info["MarketingLocale"] == "en-US" or cached.get("localizedInputVerified"))
                 and (info["MarketingLocale"] == "en-US" or cached.get("inputMethod") == "swiftui-binding")
                 and (frames / "phone-native.mp4").exists())
    if not valid:
        subprocess.run([sys.executable, str(Path(__file__).with_name("capture-marketing-phone.py")),
                        "--app", str(phone_app), "--output", str(frames)], check=True)
        verification = json.loads(verification_path.read_text())
        verification["phoneAppFingerprint"] = fingerprint
        verification_path.write_text(json.dumps(verification, ensure_ascii=False, indent=2) + "\n")
if args.prepare_phone_only:
    print(f"Native iPhone prepared for {info['MarketingLocale']}.", flush=True)
    raise SystemExit(0)
is_screenshot = info.get("MarketingStory") in {"screenshot-1", "screenshot-2", "screenshot-3", "screenshot-4"}
if is_screenshot:
    print(f"Screenshot #{info['MarketingStory'].rsplit('-', 1)[1]} capture starts in 10 seconds.", flush=True)
    print("Please leave the screen idle until the capture closes (about 10 seconds).", flush=True)
else:
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
        if is_screenshot:
            result = json.loads((output / "screenshot-result.json").read_text())
            assert result["asset"] == info["MarketingStory"] and result["locale"] == info["MarketingLocale"], result
            expected_language = {"en-US": "en", "es-ES": "es", "fr-FR": "fr", "zh-Hans": "zh-Hans"}[info["MarketingLocale"]]
            assert result["preferredLocalizations"][0] == expected_language, result
            if info["MarketingStory"] == "screenshot-1":
                assert result["compositionRevision"] == 2 and result["nativeNoteCount"] == 3, result
                assert result["expandedNoteCount"] == 1 and result["minimizedNoteCount"] == 2, result
                assert result["mainTaskCount"] == 3 and result["mainCompletedTaskCount"] == 1, result
                assert result["maxIndentLevel"] == 0 and result["singleMemoCount"] == 0, result
                assert result["nativeBackgroundDocument"] == "none" and not result["proDisclosureVisible"], result
            elif info["MarketingStory"] == "screenshot-2":
                assert result["compositionRevision"] == 4 and result["nativeNoteCount"] == 4, result
                assert result["nativePhoneView"] == "NotesDeckView" and result["phoneTaskStateMatches"], result
                assert result["phoneDeckCount"] == 2 and result["bothDeckPreviewsVisible"], result
                assert result["colorCounts"] == {"yellow": 2, "blue": 2}, result
                assert result["nativePhoneTitleVisible"] and result["softwareKeyboardHidden"], result
                assert result["phoneSyncIndicatorConnected"], result
                assert result["totalTaskCount"] == 9 and result["completedTaskCount"] == 2, result
                assert result["maxIndentLevel"] == 0 and result["singleMemoCount"] == 0, result
                assert result["nativeBackgroundDocument"] == "none" and not result["proDisclosureVisible"], result
                assert result["scatteredNoteLayout"] and result["homeAboveDinner"], result
                assert 18 <= result["homeDinnerOverlapHeight"] <= 22, result
                assert result["iCloudPillBelowSubtitle"] and result["phoneSearchBoxOutsideCanvas"], result
                assert result["phoneTop"] == 232 and result["phoneLeft"] == 900, result
                assert result["phoneSearchChromeClearance"] == 12, result
            elif info["MarketingStory"] == "screenshot-3":
                assert result["nativeNoteCount"] == 2 and result["nativeBackgroundDocument"] == "mail", result
                assert result["compositionRevision"] == 7, result
                expected_pro_badge = {
                    "en-US": "Tildone Pro · One-time purchase",
                    "es-ES": "Tildone Pro · Pago único",
                    "fr-FR": "Tildone Pro · Achat unique",
                    "zh-Hans": "Tildone Pro · 一次性购买",
                }[info["MarketingLocale"]]
                assert result["proPurchaseDisclosure"] == expected_pro_badge, result
                assert result["proPurchaseModel"] == "one-time-non-consumable", result
                assert result["singleMemoFitFraction"] == 0.95, result
                assert result["backgroundDocumentIsKey"] and result["notesAboveBackgroundDocument"], result
                assert result["memoOverlapsBackgroundDocument"], result
                assert result["subtaskCount"] == 2 and result["maxIndentLevel"] == 1, result
                assert result["singleMemoCount"] == 1 and result["proDisclosureVisible"], result
            else:
                assert result["compositionRevision"] == 3 and result["nativeNoteCount"] == 2, result
                assert result["nativeBackgroundDocument"] == "textedit", result
                assert result["nativePrivacyMenuVisible"] and result["nativeMenuPopupCount"] >= 1, result
                assert result["nativeMenuStateVerified"] and result["nativeMenuPixelReviewRequired"], result
                assert result["nativeMenuCaptureMethod"] == "stage-child-windows", result
                assert result["blurMenuChecked"] and not result["backgroundMenuChecked"], result
                assert result["personalNoteBlurred"] and not result["workshopNoteBlurred"], result
                assert result["blurScope"] == "title-and-tasks" and result["nativeBlurRadius"] == 3, result
                assert result["notesAboveBackgroundDocument"] and result["workshopOverlapsBackgroundDocument"], result
                assert result["personalTaskCount"] == 3 and result["workshopTaskCount"] == 3, result
                assert result["workshopCompletedTaskCount"] == 1, result
                assert result["singleMemoCount"] == 0 and result["maxIndentLevel"] == 0, result
                expected_pro_badge = {
                    "en-US": "Tildone Pro · One-time purchase",
                    "es-ES": "Tildone Pro · Pago único",
                    "fr-FR": "Tildone Pro · Achat unique",
                    "zh-Hans": "Tildone Pro · 一次性购买",
                }[info["MarketingLocale"]]
                assert result["proDisclosureVisible"] and result["proPurchaseDisclosure"] == expected_pro_badge, result
                assert result["proPurchaseModel"] == "one-time-non-consumable", result
            assert result["mockDataOnly"] and not result["cloudKitStarted"] and not result["hasAlpha"], result
            image = output / result["file"]
            header = image.read_bytes()[:33]
            assert header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR"
            assert struct.unpack(">II", header[16:24]) == (2880, 1800) and header[25] == 2
            destination = Path(__file__).resolve().parents[1] / "Marketing/Preview/Output/macOS-App-Store" / image.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(image, destination)
            if args.batch:
                print(f"Screenshot captured for {info['MarketingLocale']}. More captures may follow; keep the screen idle.", flush=True)
            else:
                print("Screenshot finished. You can use other apps again. Tell ChatGPT: captured.", flush=True)
            print(destination, flush=True)
        elif args.batch:
            print(f"Capture finished for {info['MarketingLocale']}.", flush=True)
        else:
            print("Capture finished. You can use other apps again. Tell ChatGPT: recorded.", flush=True)
        break
    if status.startswith("ERROR"):
        raise RuntimeError(status)
    time.sleep(0.25)
else:
    raise TimeoutError("The Mac capture did not finish. You can use other apps again.")
