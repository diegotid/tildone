#!/usr/bin/env python3
"""Capture a task-owned mock simulator through simctl; no idle desktop required."""
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
parser.add_argument("--fresh-device", action="store_true", help="Use and remove a new isolated simulator for this capture.")
args = parser.parse_args()
app = args.app.resolve(strict=True)
app_info = plistlib.loads((app / "Info.plist").read_bytes())
assert app_info["CFBundleIdentifier"] == "studio.cuatro.tildone.marketing-phone"
locale = app_info.get("MarketingLocale", "en-US")
story = app_info.get("MarketingStory", "sync")
is_screenshot = app_info.get("MarketingStory") == "screenshot-2"
is_ios_screenshot_one = app_info.get("MarketingStory") == "ios-screenshot-1"
is_suite = story.startswith("ios-") and not is_ios_screenshot_one
pause_file = Path(__file__).resolve().parents[1] / "Marketing/Preview/Output/iOS/captures/pause-captures.flag"
pause_deadline = time.monotonic() + 300
while story.startswith("ios-") and pause_file.exists():
    if time.monotonic() > pause_deadline:
        raise TimeoutError("Capture preparation did not release the temporary build pause.")
    time.sleep(1)
assert locale in {"en-US", "es-ES", "fr-FR", "zh-Hans"}, locale
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
bundle = "studio.cuatro.tildone.marketing-phone"

def simctl(*arguments, capture=True):
    return subprocess.run(["xcrun", "simctl", *map(str, arguments)], check=True,
                          text=True, stdout=subprocess.PIPE if capture else None, timeout=180).stdout

runtimes = [r for r in json.loads(simctl("list", "runtimes", "--json"))["runtimes"]
            if r.get("isAvailable") and ".iOS-" in r["identifier"]]
assert runtimes, "No installed iOS Simulator runtime is available."
runtime = max(runtimes, key=lambda r: tuple(int(p) for p in r["version"].split(".")))
types = json.loads(simctl("list", "devicetypes", "--json"))["devicetypes"]
phone_types = [t for t in types if t["name"] in ["iPhone 17 Pro", "iPhone 16 Pro", "iPhone 15 Pro"]]
assert phone_types, "A supported iPhone Simulator device type is required."
device_type = next((t for t in phone_types if t["name"] == "iPhone 17 Pro"), phone_types[-1])
# Never inspect or reuse a user device. Only this run's newly created simulator
# can be shared between suite jobs; each job reinstalls the private mock app.
shared_device = story.startswith("ios-") and not args.fresh_device
registry = Path(__file__).resolve().parents[1] / "Marketing/Preview/Output/iOS/captures/capture-device.json"
reuse_device = shared_device and registry.is_file()
if reuse_device:
    owned = json.loads(registry.read_text())
    assert owned["owner"] == "Tildone-iPhone-Overnight" and owned["bundle"] == bundle, owned
    assert owned["runtime"] == runtime["identifier"] and owned["deviceType"] == device_type["identifier"], owned
    device = owned["device"]
else:
    device = simctl("create", "Tildone Isolated Marketing Capture", device_type["identifier"], runtime["identifier"]).strip()
(output / "owned-capture-device.json").write_text(json.dumps({"owner": "Tildone-iPhone-Overnight",
    "bundle": bundle, "device": device, "shared": shared_device}) + "\n")
device_prepared = False
try:
    print("Preparing an isolated iPhone. You can keep using other apps during this step.", flush=True)
    if shared_device and not reuse_device:
        registry.write_text(json.dumps({"owner": "Tildone-iPhone-Overnight", "bundle": bundle, "device": device,
                                        "runtime": runtime["identifier"], "deviceType": device_type["identifier"]}) + "\n")
    print("Task-created simulator: " + device, flush=True)
    if not reuse_device:
        simctl("boot", device)
    simctl("bootstatus", device, "-b", capture=False)
    device_prepared = True
    if reuse_device:
        # Uninstall only the private fixture bundle to remove prior capture
        # phases, locale defaults and mock data. The simulator itself stays warm.
        subprocess.run(["xcrun", "simctl", "terminate", device, bundle], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
        subprocess.run(["xcrun", "simctl", "uninstall", device, bundle], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
    # Only this newly created simulator is changed. Skip Apple's one-time
    # keyboard tutorials before the real title/task entry is recorded.
    # This is the same setup used by Chromium's iOS simulator test tooling.
    tutorial_keys = [] if story.startswith("ios-") else ["DidShowContinuousPathIntroduction", "KeyboardDidShowProductivityTutorial",
                "DidShowGestureKeyboardIntroduction", "UIKeyboardDidShowInternationalInfoIntroduction"]
    for key in tutorial_keys:
        for attempt in range(3):
            try:
                simctl("spawn", device, "defaults", "write", "com.apple.keyboard.preferences", key, "1")
                break
            except subprocess.CalledProcessError:
                if attempt == 2:
                    print("Keyboard tutorial preference unavailable; native capture fields still suppress the software keyboard.", flush=True)
                else:
                    time.sleep(2)
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

    if is_suite:
        language = {"en-US": "en", "es-ES": "es", "fr-FR": "fr", "zh-Hans": "zh-Hans"}[locale]
        if story.startswith("ios-preview-"):
            opening = wait_for_phase(0)
            recording = None
            with (output / "phone-recording.log").open("w") as log:
                try:
                    recording = subprocess.Popen(["xcrun", "simctl", "io", device, "recordVideo", "--codec=h264",
                                                  "--force", str(output / "phone-native.mp4")], stdout=log, stderr=subprocess.STDOUT)
                    deadline = time.monotonic() + 20
                    while time.monotonic() < deadline:
                        if recording.poll() is not None:
                            raise RuntimeError("The native preview recorder exited.")
                        if "recording started" in (output / "phone-recording.log").read_text().lower():
                            break
                        time.sleep(0.1)
                    else:
                        raise TimeoutError("The native preview recorder did not start.")
                    (container / "advance.txt").write_text("1")
                    state = wait_for_phase(5)
                finally:
                    if recording is not None and recording.poll() is None:
                        recording.send_signal(signal.SIGINT)
                        recording.wait(timeout=30)
            events = json.loads((container / "capture-events.json").read_text())
            names = [e["name"] for e in events]
            expected = (["opening", "grid", "deck", "captured", "progress", "finished"] if story == "ios-preview-1"
                        else ["opening", "subtasks", "collapsed", "styled-checklist", "memo", "finished"])
            assert names == expected, events
            assert all(e["mockDataOnly"] and not e["cloudKitStarted"] and not e["storeKitStarted"] for e in events), events
            if story == "ios-preview-1":
                assert {e["layout"] for e in events} == {"list", "grid", "deck"}, events
                color_counts = {}
                for note in events[0]["notes"]:
                    color_counts[note["color"]] = color_counts.get(note["color"], 0) + 1
                assert color_counts == {"green": 3, "blue": 2, "yellow": 1}, color_counts
                assert all(event["notes"][3]["color"] == "yellow" for event in events[:2]), events[:2]
                fronts = events[-1]["greenCarouselFronts"]
                assert [front["index"] for front in fronts] == [0, 1, 2], fronts
                assert {front["title"] for front in fronts} == {n["title"] for n in events[0]["notes"] if n["color"] == "green"}, fronts
                before = sum(len(n["tasks"]) for n in events[0]["notes"])
                after = sum(len(n["tasks"]) for n in events[-1]["notes"])
                assert after == before + 1, events
            else:
                assert events[-1]["nativeView"] == "SingleMemoTextView", events
                memo = next(n for n in events[-1]["notes"] if n["kind"] == "singleTask")
                assert memo["singleMemoFont"] == "permanentMarker", memo
                assert all(len(t["spans"]) == 1 and t["spans"][0]["color"] == "blue"
                           and 0 < t["spans"][0]["length"] < len(t["text"].encode("utf-16-le")) // 2 for t in memo["tasks"]), memo
                styled = next(e for e in events if e["name"] == "styled-checklist")
                note = next(n for n in styled["notes"] if n["title"] == styled["selectedTitle"])
                spans = [span for task in note["tasks"] for span in task["spans"]]
                assert {s["color"] for s in spans} == {"blue", "green", "purple"}, note
                assert {style for span in spans for style in span["styles"]} == {"bold", "italic"}, note
                assert all(0 < sum(s["length"] for s in task["spans"]) < len(task["text"].encode("utf-16-le")) // 2 for task in note["tasks"]), note
            shutil.copy2(container / "capture-events.json", output / "capture-events.json")
        else:
            state = wait_for_phase(5)
            simctl("io", device, "screenshot", "--type=png", output / "phone-checklist.png", capture=False)
            notes = state["notes"]
            if story == "ios-screenshot-2":
                assert len(notes) == 1 and len(notes[0]["tasks"]) == 2 and state["nativeView"] == "ChecklistView", state
            elif story == "ios-screenshot-header":
                fixture = json.loads((Path(__file__).resolve().parents[1] / "Marketing/Preview/Inputs/header-note.json").read_text())
                assert len(notes) == 1 and notes[0]["color"] == fixture["color"] and state["nativeView"] == "ChecklistView", state
                assert len(notes[0]["tasks"]) == len(fixture["tasks"]) == 5, state
                assert [task["completed"] for task in notes[0]["tasks"]] == [task["completed"] for task in fixture["tasks"]], state
            elif story == "ios-screenshot-3":
                expected_layout = app_info.get("MarketingOverviewLayout", "grid")
                assert expected_layout in {"grid", "deck"}
                assert len(notes) == 5 and sorted(n["color"] for n in notes) == ["blue", "green", "green", "green", "yellow"] and state["layout"] == expected_layout, state
                assert notes[2]["color"] == "yellow", state
                if app_info.get("MarketingCaptureBothLayouts"):
                    assert expected_layout == "grid"
                    (container / "capture-deck.txt").write_text("1")
                    deck = wait_for_phase(6)
                    assert deck["layout"] == "deck" and deck["notes"] == notes and deck["verified"], deck
                    assert deck["nativeUI"] and deck["mockDataOnly"] and not deck["cloudKitStarted"] and not deck["storeKitStarted"], deck
                    deck_directory = output / "deck"
                    deck_directory.mkdir(exist_ok=True)
                    simctl("io", device, "screenshot", "--type=png", deck_directory / "phone-checklist.png", capture=False)
                    deck.update({"runtime": runtime["identifier"], "deviceType": device_type["identifier"]})
                    (deck_directory / "phone-capture-verification.json").write_text(json.dumps(deck, ensure_ascii=False, indent=2) + "\n")
            elif story == "ios-screenshot-4":
                query = state["searchQuery"].casefold()
                matches = [n for n in notes if query in n["title"].casefold() or any(query in t["text"].casefold() for t in n["tasks"])]
                assert query and len(matches) == 2, state
            elif story == "ios-screenshot-5":
                assert max(t["depth"] for n in notes for t in n["tasks"]) == 1 and state["nativeView"] == "ChecklistView", state
            elif story == "ios-screenshot-6":
                assert state["nativeView"] == "SingleMemoTextView", state
                assert all(n["singleMemoFont"] == "permanentMarker" for n in notes), state
                assert all(len(t["spans"]) == 1 and t["spans"][0]["color"] == "blue"
                           and 0 < t["spans"][0]["length"] < len(t["text"].encode("utf-16-le")) // 2
                           for n in notes for t in n["tasks"]), state
        assert state["asset"] == story and state["locale"] == locale and state["verified"], state
        assert state["preferredLocalizations"][0] == language, state
        assert state["nativeUI"] and state["mockDataOnly"] and not state["cloudKitStarted"] and not state["storeKitStarted"], state
        state.update({"runtime": runtime["identifier"], "deviceType": device_type["identifier"]})
        (output / "phone-capture-verification.json").write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n")
        print(f"Verified native suite asset: {story} / {locale}", flush=True)
    elif is_ios_screenshot_one:
        state = wait_for_phase(5)
        assert state["asset"] == "ios-screenshot-1" and state["screenshotRevision"] == 1, state
        assert state["nativeView"] == "ChecklistView" and state["nativeUI"], state
        assert state["verified"] and state["nativeTitleVisible"] and state["allTasksVisible"], state
        assert state["softwareKeyboardHidden"] and state["taskCount"] == 4, state
        assert len(state["taskTexts"]) == 4 and len(state["completedTexts"]) == 1, state
        assert state["mockDataOnly"] and not state["cloudKitStarted"] and not state["proContent"], state
        language = {"en-US": "en", "es-ES": "es", "fr-FR": "fr", "zh-Hans": "zh-Hans"}[locale]
        assert state["locale"] == locale and state["preferredLocalizations"][0] == language, state
        simctl("io", device, "screenshot", "--type=png", output / "phone-checklist.png", capture=False)
        shutil.copy2(container / "phone-screenshot-result.json", output / "phone-screenshot-result.json")
        state.update({"runtime": runtime["identifier"], "deviceType": device_type["identifier"]})
        (output / "phone-capture-verification.json").write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n")
        print(f"Verified native four-task checklist captured: {locale}.", flush=True)
    elif is_screenshot:
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
    if shared_device and device_prepared:
        subprocess.run(["xcrun", "simctl", "terminate", device, bundle], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
    else:
        subprocess.run(["xcrun", "simctl", "shutdown", device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
        subprocess.run(["xcrun", "simctl", "delete", device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
        if shared_device:
            registry.unlink(missing_ok=True)
