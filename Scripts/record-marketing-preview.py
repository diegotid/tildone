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
parser.add_argument("--manual-screen-region", action="store_true", help="Select screenshot 6's canvas rectangle with the native screenshot UI.")
args = parser.parse_args()
app = args.app.resolve(strict=True)
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
assert info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-preview"
if args.prepare_phone_only:
    assert info.get("MarketingStory") == "screenshot-2"
if args.manual_screen_region:
    assert info.get("MarketingStory") == "screenshot-6"
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
is_screenshot = info.get("MarketingStory") in {"screenshot-1", "screenshot-2", "screenshot-3", "screenshot-4", "screenshot-5", "screenshot-6"}
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
screen_region_requested = False
while time.monotonic() < deadline:
    status = (output / "capture-status.txt").read_text()
    if status == "READY FOR SCREEN REGION" and not screen_region_requested:
        assert info.get("MarketingStory") == "screenshot-6"
        command = [sys.executable, str(Path(__file__).with_name("capture-marketing-screen-region.py")),
                   "--output", str(output)]
        if args.manual_screen_region:
            command.append("--interactive")
        subprocess.run(command, check=True)
        screen_region_requested = True
        deadline = time.monotonic() + 90
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
            elif info["MarketingStory"] == "screenshot-4":
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
            elif info["MarketingStory"] == "screenshot-5":
                assert result["compositionRevision"] == 2 and result["nativeNoteCount"] == 6, result
                assert result["uniquePlans"] == 3 and result["pairedPlanContentsMatch"], result
                assert result["nativeDocumentCount"] == 2 and result["nativeBackgroundDocument"] == "textedit", result
                assert result["expandedNoteCount"] == 6 and result["minimizedNoteCount"] == 0, result
                assert result["taskCountPerNote"] == 2 and result["pairedNoteSizesMatch"], result
                assert result["beforeNotesSeparated"] and result["minimumBeforeNoteGap"] >= 20, result
                frames = result["beforeNoteFrames"]
                for a, b in ((frames[0], frames[1]), (frames[0], frames[2]), (frames[1], frames[2])):
                    dx = max(0, a["x"] - b["x"] - b["width"], b["x"] - a["x"] - a["width"])
                    dy = max(0, a["y"] - b["y"] - b["height"], b["y"] - a["y"] - a["height"])
                    assert dx * dx + dy * dy >= 400, result
                assert result["relativeOrderPreserved"] and result["yellowRightEdgeVisible"], result
                assert result["outcomeNotesInsideInset"] and result["notesAboveDocuments"], result
                assert result["beforeDocumentCoverage"] > result["afterDocumentCoverage"] + 0.2, result
                assert result["ghostPositionMethod"] == "document-relative-transform", result
                assert result["ghostOutlineOpacity"] <= 0.07 and result["trailOpacity"] <= 0.03, result
                assert result["scrollIndicator"] == "ScrollChevronIndicator" and result["scrollChevronCount"] == 6, result
                assert result["scrollPointsDown"] and result["scrollAnimationFrozenForScreenshot"], result
                assert result["labelInsideInset"] and result["labelStyle"] == "white-on-charcoal", result
                assert all(abs(alpha - 0.9) < 0.001 for alpha in result["outcomeNoteAlphas"]), result
                expected_badge = {
                    "en-US": "Tildone Pro · One-time purchase", "es-ES": "Tildone Pro · Pago único",
                    "fr-FR": "Tildone Pro · Achat unique", "zh-Hans": "Tildone Pro · 一次性购买",
                }[info["MarketingLocale"]]
                assert result["proDisclosureVisible"] and result["proPurchaseDisclosure"] == expected_badge, result
                assert result["proPurchaseModel"] == "one-time-non-consumable", result
                # Recompute the ghosts from the measured document-relative frames.
                source_doc, target_doc = result["documentFrames"]
                for source, ghost in zip(result["beforeNoteFrames"], result["ghostNoteFrames"]):
                    for axis, extent in (("x", "width"), ("y", "height")):
                        scale = target_doc[extent] / source_doc[extent]
                        expected = target_doc[axis] + (source[axis] - source_doc[axis]) * scale
                        assert abs(ghost[axis] - expected) < 0.01, result
                        assert abs(ghost[extent] - source[extent] * scale) < 0.01, result
            else:
                assert result["asset"] == "screenshot-6" and result["compositionRevision"] == 3, result
                assert result["nativeNoteCount"] == 3 and result["totalTaskCount"] == 7, result
                assert result["maxIndentLevel"] == 0 and result["singleMemoCount"] == 0, result
                assert result["compositionMethod"] == "screen-region-with-live-transparent-note", result
                assert result["finalCaptureMethod"] in {"macos-screencapture-region", "macos-screencapture-interactive-region"}, result
                region = result["screenRegion"]
                assert not region["windowCaptureUsed"] and region["canvasFullyOnScreen"], result
                assert region["rect"]["width"] == 1440 and region["rect"]["height"] == 900, result
                assert abs(region["sourceWidth"] / region["sourceHeight"] - 1.6) <= 0.002, result
                assert (output / region["rawFile"]).exists(), result
                assert result["globalSettingsCapturedSeparately"] and result["nativeNoteView"] == "Note", result
                assert result["liveTransparentNote"] and result["transparentNoteAboveSettings"], result
                assert result["transparentOverlapsWeekendCorner"] and result["transparentOverlapsSettingsCorner"], result
                assert result["weekendLaterHorizontalGap"] >= 40 and result["dimmingGroupBelowMidline"], result
                assert result["transparentMaterialNeedsVisualReview"], result
                assert result["contentScale"] == 1 and result["noExampleLabels"] and result["noOuterExampleBorder"], result
                assert result["settingsView"] == "SettingsForm", result
                assert result["settingsControlsReused"] == ["noteColorSettings", "fontSizeSettings", "taskWrappingSettings"], result
                assert result["nativePaletteVisible"] and result["nativePaletteColorCount"] == 6, result
                examples = result["samples"]
                assert len(examples) == 3 and [x["color"] for x in examples] == ["green", "purple", "orange"], result
                assert [x["fontSizeSetting"] for x in examples] == [20, 15, 15], result
                assert [x["backgroundOpacitySetting"] for x in examples] == [0.65, 0, 0.65], result
                for index, sample in enumerate(examples):
                    assert sample["index"] == index and sample["nativeTitleVisible"], result
                    assert len(sample["nativeTaskFontSizes"]) >= sample["taskCount"], result
                    assert all(abs(size - sample["fontSizeSetting"]) < 0.1 for size in sample["nativeTaskFontSizes"]), result
                    assert sample["nativeVisualEffectMaterialRetained"] and sample["nativeWindowShadow"], result
                    assert (output / "native-frames" / sample["source"]).exists(), result
                assert examples[0]["nativePaletteVisible"] and examples[0]["paletteColorCount"] == 6, result
                assert examples[1]["nativeBackgroundAlpha"] == 0 and examples[1]["windowAlpha"] == 1, result
                assert [x["keptLiveForFinalCapture"] for x in examples] == [False, True, False], result
                green, home, later = [x["windowFrame"] for x in examples]
                settings = result["settingsFrame"]
                def contains_point(rect, x, y):
                    return rect["x"] <= x <= rect["x"] + rect["width"] and rect["y"] <= y <= rect["y"] + rect["height"]
                assert contains_point(home, green["x"] + 1, green["y"] + 1), result
                assert contains_point(home, settings["x"] + settings["width"] - 1, settings["y"] + settings["height"] - 1), result
                assert later["x"] - green["x"] - green["width"] >= 40, result
                assert later["y"] + later["height"] < 450, result
                assert settings["x"] < 150 and settings["y"] < 100, result
                assert abs(examples[2]["windowAlpha"] - 0.45) < 0.001, result
                expected_caption = {
                    "en-US": "Dim notes with a scroll.", "es-ES": "Atenúa notas con un scroll.",
                    "fr-FR": "Un défilement pour atténuer les notes.", "zh-Hans": "滚动鼠标，淡化便签。",
                }[info["MarketingLocale"]]
                assert result["dimmingCaption"] == expected_caption and result["proDisclosureScope"] == "dimming-only", result
                expected_badge = {
                    "en-US": "Tildone Pro · One-time purchase", "es-ES": "Tildone Pro · Pago único",
                    "fr-FR": "Tildone Pro · Achat unique", "zh-Hans": "Tildone Pro · 一次性购买",
                }[info["MarketingLocale"]]
                assert result["proPurchaseDisclosure"] == expected_badge, result
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
