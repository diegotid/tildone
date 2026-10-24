#!/usr/bin/env python3
"""Run from a GUI Terminal session; capture only a newly created mock simulator."""
import argparse
import json
import plistlib
import signal
import shutil
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--app", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
app = args.app.resolve(strict=True)
app_info = plistlib.loads((app / "Info.plist").read_bytes())
assert app_info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-phone"
locale = app_info.get("MarketingLocale", "en-US")
is_screenshot = app_info.get("MarketingStory") == "screenshot-2"
assert locale in {"en-US", "es-ES", "fr-FR", "zh-Hans"}, locale
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
bundle = "studio.cuatro.tildone.marketing-phone"

def simctl(*arguments, capture=True):
    return subprocess.run(["xcrun", "simctl", *map(str, arguments)], check=True,
                          text=True, stdout=subprocess.PIPE if capture else None).stdout

runtimes = [r for r in json.loads(simctl("list", "runtimes", "--json"))["runtimes"]
            if r.get("isAvailable") and ".iOS-" in r["identifier"]]
assert runtimes, "No installed iOS Simulator runtime is available."
runtime = max(runtimes, key=lambda r: tuple(int(p) for p in r["version"].split(".")))
types = json.loads(simctl("list", "devicetypes", "--json"))["devicetypes"]
phone_types = [t for t in types if t["name"] in ["iPhone 17 Pro", "iPhone 16 Pro", "iPhone 15 Pro"]]
assert phone_types, "A supported iPhone Simulator device type is required."
device_type = next((t for t in phone_types if t["name"] == "iPhone 17 Pro"), phone_types[-1])
# Never reuse, erase, boot or inspect the user's existing simulator devices.
device = simctl("create", "Tildone Isolated Marketing Capture", device_type["identifier"], runtime["identifier"]).strip()
try:
    print("Preparing an isolated iPhone. You can keep using other apps during this step.", flush=True)
    simctl("boot", device)
    simctl("bootstatus", device, "-b", capture=False)
    # Only this newly created simulator is changed. Skip Apple's one-time
    # keyboard tutorials before the real title/task entry is recorded.
    # This is the same setup used by Chromium's iOS simulator test tooling.
    for key in ["DidShowContinuousPathIntroduction", "KeyboardDidShowProductivityTutorial",
                "DidShowGestureKeyboardIntroduction", "UIKeyboardDidShowInternationalInfoIntroduction"]:
        simctl("spawn", device, "defaults", "write", "com.apple.keyboard.preferences", key, "1")
    simctl("ui", device, "appearance", "light")
    simctl("status_bar", device, "override", "--time", "9:41", "--dataNetwork", "wifi",
           "--wifiMode", "active", "--wifiBars", "3", "--batteryState", "charged", "--batteryLevel", "100")
    simctl("install", device, app)
    simctl("launch", device, bundle, "-AppleLanguages", f"({locale})",
           "-AppleLocale", locale.replace("-", "_"))
    container = Path(simctl("get_app_container", device, bundle, "data").strip()) / "Documents"
    def wait_for_phase(phase, timeout=120):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            error_path = container / "capture-error.txt"
            if error_path.exists():
                shutil.copy2(error_path, output / "phone-capture-error.txt")
                for frame in [*container.glob("phone-*.png"), *container.glob("phone-screenshot-result.json")]:
                    shutil.copy2(frame, output / frame.name)
                if (container / "capture-events.json").exists():
                    shutil.copy2(container / "capture-events.json", output / "phone-failed-events.json")
                if (container / "input-diagnostic.json").exists():
                    shutil.copy2(container / "input-diagnostic.json", output / "phone-input-diagnostic.json")
                raise RuntimeError(error_path.read_text())
            try:
                state = json.loads((container / "capture-phase.json").read_text())
                if state["phase"] == phase:
                    return state
            except (FileNotFoundError, json.JSONDecodeError):
                pass
            time.sleep(0.1)
        raise TimeoutError(f"The native iPhone flow did not reach phase {phase}.")

    if is_screenshot:
        state = wait_for_phase(5)
        assert state["asset"] == "screenshot-2" and state["screenshotRevision"] == 3, state
        assert state["locale"] == locale and state["nativeView"] == "NotesDeckView", state
        assert state["nativeTitleVisible"] and state["softwareKeyboardHidden"], state
        assert state["noteCount"] == 4 and state["deckCount"] == 2 and state["bothDeckPreviewsVisible"], state
        assert state["colorCounts"] == {"yellow": 2, "blue": 2}, state
        assert state["deckContentAboveCrop"] and state["screenPointSize"][1] * 0.75 < state["cropAboveSearchY"] < state["nativeSearchTop"], state
        assert state["phoneSyncIndicatorConnected"] and state["syncSymbol"] == "icloud", state
        assert state["mockDataOnly"] and not state["cloudKitStarted"], state
        assert len(state["notes"]) == 4 and sum(len(n["taskTexts"]) for n in state["notes"]) == 9, state
        assert sum(len(n["completedTexts"]) for n in state["notes"]) == 2, state
        language = {"en-US": "en", "es-ES": "es", "fr-FR": "fr", "zh-Hans": "zh-Hans"}[locale]
        assert state["preferredLocalizations"][0] == language, state
        simctl("io", device, "screenshot", "--type=png", output / "phone-shared.png", capture=False)
        shutil.copy2(container / "phone-screenshot-result.json", output / "phone-screenshot-result.json")
        state.update({"runtime": runtime["identifier"], "deviceType": device_type["identifier"]})
        (output / "phone-capture-verification.json").write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n")
        print("Native iPhone decks captured: four matching notes, with both front-card titles and task previews visible.", flush=True)
    else:
        opening = wait_for_phase(0)
        assert opening["nativeView"] == "NotesListView" and opening["noteCount"] == 1, opening
        simctl("io", device, "screenshot", "--type=png", output / "phone-overview.png", capture=False)
        video_path = output / "phone-native.mp4"
        recording = None
        with (output / "phone-recording.log").open("w") as log:
            try:
                recording = subprocess.Popen(["xcrun", "simctl", "io", device, "recordVideo",
                                              "--codec=h264", "--force", str(video_path)],
                                             stdout=log, stderr=subprocess.STDOUT)
                # Keep a short overview lead-in before starting the native actions.
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    if recording.poll() is not None:
                        raise RuntimeError("The iPhone screen recording did not start.")
                    if "recording started" in (output / "phone-recording.log").read_text().lower():
                        break
                    time.sleep(0.1)
                else:
                    raise TimeoutError("The iPhone recorder did not report readiness.")
                time.sleep(0.5)
                (container / "advance.txt").write_text("1")
                wait_for_phase(5)
            finally:
                if recording is not None and recording.poll() is None:
                    recording.send_signal(signal.SIGINT)
                    recording.wait(timeout=20)
        assert video_path.stat().st_size > 10000
        for frame in container.glob("phone-*.png"):
            shutil.copy2(frame, output / frame.name)
        states = json.loads((container / "capture-events.json").read_text())
        assert [state["frame"] for state in states] == ["overview", "new-note", "titled", "created", "updated", "complete"], states
        assert [len(state["taskTexts"]) for state in states] == [0, 0, 0, 1, 2, 2], states
        assert [len(state["completedTexts"]) for state in states] == [0, 0, 0, 0, 1, 1], states
        assert all(state["mockDataOnly"] and not state["cloudKitStarted"] for state in states), states
        assert all(state["locale"] == locale for state in states), states
        if locale != "en-US":
            assert all(state.get("localizedInputVerified") for state in states if state["phase"] >= 2), states
            assert all(state.get("inputMethod") == "swiftui-binding" for state in states), states
            language = {"es-ES": "es", "fr-FR": "fr", "zh-Hans": "zh-Hans"}[locale]
            assert all(state["preferredLocalizations"][0] == language for state in states), states
        assert states[-1]["keyboardSuppressedFields"] >= 2, states
        assert states[-1]["maxSoftwareKeyboardHeight"] < 100, states
        assert all(state["nativeTitleVisible"] for state in states if state["phase"] >= 2), states
        assert states[-1]["titleVisibleWhileTypingTask"], states
        assert all(state["syncAvailability"] == "available" and state["syncActivity"] == "idle"
                   and state["syncSymbol"] == "icloud" for state in states), states
        (output / "phone-capture-verification.json").write_text(json.dumps({
            "storyRevision": 7, "nativeUI": True, "nativeVideo": True,
            "softwareKeyboardHidden": True,
            "nativeTitleVisible": True, "titlePresentation": "native-creation-field",
            "phoneSyncIndicatorConnected": True,
            "localizedInputVerified": all(state.get("localizedInputVerified") for state in states if state["phase"] >= 2),
            "inputMethod": states[-1].get("inputMethod", "uikit-events"),
            "runtime": runtime["identifier"], "deviceType": device_type["identifier"],
            "mockDataOnly": True, "cloudKitStarted": False, "states": states
        }, ensure_ascii=False, indent=2) + "\n")
        print("Native iPhone note creation and update recorded and verified.", flush=True)
finally:
    subprocess.run(["xcrun", "simctl", "shutdown", device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["xcrun", "simctl", "delete", device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
