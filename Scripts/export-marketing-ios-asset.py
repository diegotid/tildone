#!/usr/bin/env python3
"""Export a captured native iPhone asset in the approved marketing composition."""
import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import sys
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--asset", choices=[f"screenshot-{n}" for n in range(1, 7)] + ["preview-1", "preview-2"], required=True)
parser.add_argument("--locale", choices=["en-US", "es-ES", "fr-FR", "zh-Hans"], required=True)
parser.add_argument("--native", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--repair", action="store_true", help=argparse.SUPPRESS)
parser.add_argument("--draft", action="store_true", help="Render a review without replacing any final media.")
parser.add_argument("--deck-native", type=Path, help="Matching native deck capture for screenshot 3.")
parser.add_argument("--display-size", choices=["medium", "large"], default="medium",
                    help="Screenshot device slot; previews keep their existing 886x1920 format.")
args = parser.parse_args()
assert args.deck_native is None or args.asset == "screenshot-3"
repo = Path(__file__).resolve().parents[1]
native = args.native.resolve()
output = args.output.resolve()
final = repo / "Marketing/Preview/Output/iOS-App-Store"
final.mkdir(parents=True, exist_ok=True)
suite_root = repo / "Marketing/Preview/Output/iOS/captures"
repair_manifest = suite_root / "repairs.json"
if not args.repair and not args.draft and repair_manifest.is_file():
    repairs = json.loads(repair_manifest.read_text())
    assert isinstance(repairs, list) and len(repairs) <= 32
    for item in repairs:
        asset, locale, revision = item["asset"], item["locale"], item["revision"]
        assert asset in [f"screenshot-{n}" for n in range(1, 7)] + ["preview-1", "preview-2"]
        assert locale in ["en-US", "es-ES", "fr-FR", "zh-Hans"] and type(revision) is int
        directory = suite_root / asset / locale
        done = directory / f"repair-{revision}-finished.json"
        if asset == args.asset and locale == args.locale:
            continue
        if done.exists():
            continue
        repaired_native = directory / f"native-repair-{revision}"
        with (directory / f"repair-{revision}.log").open("w") as log:
            subprocess.run([sys.executable, str(repo / "Scripts/capture-marketing-phone.py"),
                            "--app", str(directory / "TildonePhonePreview.app"), "--output", str(repaired_native)],
                           check=True, stdout=log, stderr=subprocess.STDOUT, timeout=300)
            subprocess.run([sys.executable, __file__, "--asset", asset, "--locale", locale,
                            "--native", str(repaired_native), "--output", str(directory), "--repair"],
                           check=True, stdout=log, stderr=subprocess.STDOUT, timeout=120)
        done.write_text((directory / "export-result.json").read_text())
        # Keep each GUI export below its bounded worker timeout. Remaining
        # repairs are picked up by the next approved asset's export.
        break
proof = json.loads((native / "phone-capture-verification.json").read_text())
assert proof["asset"] == "ios-" + args.asset and proof["locale"] == args.locale, proof
assert proof["mockDataOnly"] and not proof["cloudKitStarted"], proof
if args.asset.startswith("screenshot-"):
    if args.asset == "screenshot-1":
        assert proof["verified"] and proof["taskCount"] == 4 and proof["allTasksVisible"], proof
        catalog = json.loads((repo / "Tildone/Localizable.xcstrings").read_text())["strings"]
        language = {"en-US": "en", "es-ES": "es", "fr-FR": "fr", "zh-Hans": "zh-Hans"}[args.locale]
        expected = []
        for key in ["Book a table", "Check the train times", "Choose a walking route", "Pack a charger"]:
            expected.append(catalog[key].get("localizations", {}).get(language, {}).get("stringUnit", {}).get("value", key))
        assert proof["taskTexts"] == expected, (proof["taskTexts"], expected)
    if args.asset == "screenshot-2":
        mac_proof = json.loads((repo / "Marketing/Preview/Output/screenshots/02" / args.locale /
                                "phone-frames/phone-capture-verification.json").read_text())
        old = next(n for n in mac_proof["notes"] if n["title"] == proof["notes"][0]["title"])
        assert old["taskTexts"] == [t["text"] for t in proof["notes"][0]["tasks"]], (old, proof)
    number = int(args.asset.rsplit('-', 1)[1])
    image = output / f"Tildone-iOS-screenshot-{number:02}-{args.locale}.png"
    renderer = Path("/tmp/TildoneIOSRenderTools/render-screenshot")
    renderer_source = repo / "Scripts/render-marketing-ios-thumbnail.swift"
    render_command = ([str(renderer)] if renderer.exists() and renderer.stat().st_mtime >= renderer_source.stat().st_mtime else
                      ["swift", "-disable-sandbox", "-module-cache-path", "/tmp/tildone-marketing-module-cache", str(renderer_source)])
    render_arguments = [str(native / "phone-checklist.png"), str(image), args.locale, "3", args.asset]
    deck_proof_path = None
    if args.deck_native:
        deck_proof_path = args.deck_native.resolve() / "phone-capture-verification.json"
        deck = json.loads(deck_proof_path.read_text())
        assert proof["layout"] == "grid" and deck["layout"] == "deck"
        assert deck["nativeUI"] and deck["mockDataOnly"] and not deck["cloudKitStarted"] and not deck["storeKitStarted"]
        assert deck["locale"] == args.locale and deck["asset"] == "ios-screenshot-3"
        assert sorted(proof["notes"], key=lambda n: n["title"]) == sorted(deck["notes"], key=lambda n: n["title"])
        render_arguments.append(str(deck_proof_path.parent / "phone-checklist.png"))
    if args.display_size == "medium":
        render_arguments.append("--medium")
    subprocess.run(render_command + render_arguments, check=True)
    data = image.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    dimensions = (1206, 2622) if args.display_size == "medium" else (1320, 2868)
    assert struct.unpack(">IIBB", data[16:26]) == (*dimensions, 8, 2)
    target = image if args.draft else final / image.name
    if not args.draft:
        shutil.copy2(image, target)
    subprocess.run(["sips", "-Z", "956", str(image), "--out", str(output / "review.png")],
                   check=True, stdout=subprocess.DEVNULL)
    result = {"asset": args.asset, "locale": args.locale, "verified": True, "file": str(target),
              "sha256": hashlib.sha256(data).hexdigest(), "nativeProof": str(native / "phone-capture-verification.json"),
              "requiresVisualReview": True}
    result.update(displaySize=args.display_size, width=dimensions[0], height=dimensions[1])
    if deck_proof_path:
        result["nativeDeckProof"] = str(deck_proof_path)
        result["sameMockContentInBothLayouts"] = True
else:
    is_pro = args.asset == "preview-2"
    scenes = ([(0, 4, "Your Mac notes.\nWith you."), (4, 9, "See the day your way."),
               (9, 14, "Your plans, grouped."), (14, 23, "Catch it while it’s fresh."),
               (23, 30, "Pick it up on Mac.")] if not is_pro else
              [(0, 4, "Your notes.\nOn iPhone and Mac."), (4, 9, "Make the big thing feel smaller."),
               (9, 12, "Keep the next step clear."), (12, 18, "Make key words stand out."),
               (18, 22, "Free iCloud sync with Mac."), (22, 26, "One thought. Its own space."),
               (26, 30, "No subscription.")])
    command = ["ffmpeg", "-hide_banner", "-y", "-filter_complex_threads", "2", "-i", str(native / "phone-native.mp4")]
    disclosure_modes = ["free"] * len(scenes) if not is_pro else ["companion", "pro", "pro", "pro", "none", "pro", "pro"]
    for index, ((_, _, caption), disclosure_mode) in enumerate(zip(scenes, disclosure_modes)):
        overlay = output / f"overlay-{index}.png"
        renderer = Path("/tmp/TildoneIOSRenderTools/render-overlay")
        renderer_source = repo / "Scripts/render-marketing-ios-video-overlay.swift"
        render_command = ([str(renderer)] if renderer.exists() and renderer.stat().st_mtime >= renderer_source.stat().st_mtime else
                          ["swift", "-disable-sandbox", "-module-cache-path", "/tmp/tildone-marketing-module-cache", str(renderer_source)])
        subprocess.run(render_command + [str(overlay), args.locale, caption, disclosure_mode], check=True)
        command += ["-loop", "1", "-i", str(overlay)]
    macbook_index = None
    phone_intro_index = None
    if is_pro:
        # The same approved SwiftUI artwork as screenshot 2, rendered with
        # transparency so the real, moving iPhone capture remains underneath.
        macbook = output / "macbook-intro.png"
        phone = suite_root / "screenshot-2" / args.locale / "export-result.json"
        phone_native = Path(json.loads(phone.read_text())["nativeProof"]).parent / "phone-checklist.png"
        renderer = Path("/tmp/TildoneIOSRenderTools/render-screenshot")
        renderer_source = repo / "Scripts/render-marketing-ios-thumbnail.swift"
        render_command = ([str(renderer)] if renderer.exists() and renderer.stat().st_mtime >= renderer_source.stat().st_mtime else
                          ["swift", "-disable-sandbox", "-module-cache-path", "/tmp/tildone-marketing-module-cache", str(renderer_source)])
        subprocess.run(render_command + [str(phone_native), str(macbook), args.locale, "3", "screenshot-2", "--macbook-layer"], check=True)
        macbook_index = len(scenes) + 1
        command += ["-loop", "1", "-i", str(macbook)]
        phone_intro_index = macbook_index + 1
        command += ["-loop", "1", "-i", str(phone_native)]
    audio_index = len(scenes) + 1 + 2 * int(is_pro)
    command += ["-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000"]
    graph = ["[0:v]tpad=stop_mode=clone:stop_duration=30,fps=30,split[main][band]", "[band]crop=12:162:8:11,scale=422:162[island]",
             "[main][island]overlay=392:11,scale=886:1920:force_original_aspect_ratio=decrease:flags=lanczos,pad=886:1920:(ow-iw)/2:(oh-ih)/2:white[base]"]
    previous = "base"
    if is_pro:
        # Show the actual matching free checklist on both devices before
        # introducing Pro. Reuse the approved, verified native screenshot.
        graph += [f"[{phone_intro_index}:v]trim=duration=4,setpts=PTS-STARTPTS,split[phone][phoneband]",
                  "[phoneband]crop=12:162:8:11,scale=422:162[phoneisland]",
                  "[phone][phoneisland]overlay=392:11,scale=886:1920:force_original_aspect_ratio=decrease:flags=lanczos,pad=886:1920:(ow-iw)/2:(oh-ih)/2:white,format=rgba,fade=t=out:st=3.05:d=0.55:alpha=1[phoneintro]",
                  "[base][phoneintro]overlay=0:0:eof_action=pass:repeatlast=0:enable='lt(t,4)'[nativeintro]"]
        previous = "nativeintro"
    for index, (start, end, _) in enumerate(scenes):
        if is_pro and index == 0:
            continue  # This white caption travels inside the MacBook layer.
        if is_pro and index == 1:
            start = 0  # Wait behind the MacBook; its departure reveals this.
        label = f"caption{index}"
        graph.append(f"[{previous}][{index+1}:v]overlay=0:0:enable='gte(t,{start})*lt(t,{end})'[{label}]")
        previous = label
    if is_pro:
        # Composite the white title/subtitle into the desktop BEFORE applying
        # one transform. They move as MacBook screen content, while the next
        # black caption is already waiting behind the departing display.
        progress = "clip((t-2.75)/1.25,0,1)"
        easing = f"(({progress})*({progress})*(3-2*({progress})))"
        graph.append(f"[{macbook_index}:v]trim=duration=4,setpts=PTS-STARTPTS,scale=886:-1,format=rgba,"
                     "crop=886:1920:0:200[macbookdesktop]")
        graph.append("[macbookdesktop][1:v]overlay=0:0:format=auto:shortest=1,format=rgba[macbookplate]")
        graph.append(f"[macbookplate]scale=w='2*trunc(443*(1+0.9*{easing}))':"
                     f"h='2*trunc(960*(1+0.9*{easing}))':eval=frame[macbook]")
        graph.append(f"[{previous}][macbook]overlay=x='(W-w)/2':"
                     f"y='956*(1-w/886)+1300*{easing}':eval=frame:"
                     "eof_action=pass:repeatlast=0:enable='lt(t,4)'[companion]")
        previous = "companion"
    graph.append(f"[{previous}]format=yuv420p,setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709[video]")
    image = output / f"Tildone-iOS-{args.asset}-{args.locale}.mp4"
    command += ["-filter_complex", ";".join(graph), "-map", "[video]", "-map", f"{audio_index}:a:0",
                "-t", "30", "-r", "30", "-c:v", "libx264", "-preset", "medium", "-threads", "4",
                "-profile:v", "high", "-level:v", "4.0", "-b:v", "10M", "-maxrate", "12M", "-bufsize", "24M",
                "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
                "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-ac", "2", "-movflags", "+faststart", str(image)]
    with (output / "ffmpeg-export.log").open("w") as log:
        subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT)
    probe = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(image)]))
    video = next(s for s in probe["streams"] if s["codec_type"] == "video")
    audio = next(s for s in probe["streams"] if s["codec_type"] == "audio")
    assert (video["width"], video["height"], video["codec_name"], video["pix_fmt"], video["r_frame_rate"], int(video["nb_frames"])) == (886,1920,"h264","yuv420p","30/1",900), video
    assert audio["codec_name"] == "aac" and audio["channels"] == 2 and abs(float(probe["format"]["duration"])-30)<0.05
    target = image if args.draft else final / image.name
    if not args.draft:
        shutil.copy2(image, target)
    for second in [2, 7, 12, 17, 22, 28]:
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-ss", str(second), "-i", str(image),
                        "-frames:v", "1", str(output / f"review-{second:02}.png")], check=True)
    if not args.draft:
        shutil.copy2(output / "review-02.png", final / f"Tildone-iOS-{args.asset}-poster-{args.locale}.png")
    result = {"asset": args.asset, "locale": args.locale, "verified": True, "file": str(target),
              "sha256": hashlib.sha256(target.read_bytes()).hexdigest(), "nativeProof": str(native / "phone-capture-verification.json"),
              "videoProbe": probe, "proDisclosureThroughout": False,
              "proDisclosureIntervals": [[start, end] for (start, end, _), mode in zip(scenes, disclosure_modes) if mode == "pro"],
              "freeSyncClaimIntervals": [[0, 4], [18, 22]] if is_pro else [[0, 30]],
              "macBookCompanionIntro": is_pro, "macBookExitInterval": [2.75, 4] if is_pro else None,
              "macBookExitScale": [1, 1.9] if is_pro else None,
              "introCaptionPosition": "same bottom position as following captions" if is_pro else None,
              "introCaptionMovesWithMacBook": is_pro, "nextCaptionBehindMacBookFromStart": is_pro,
              "nativeChecklistCrossfade": [3.05, 3.6] if is_pro else None,
              "matchingNativePhoneAndMacIntro": is_pro,
              "freeSyncDisclosureThroughout": not is_pro, "requiresVisualReview": True}
result["draft"] = args.draft
result["revisionDirectory"] = str(output)
(output / "export-result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
if not args.draft and repair_manifest.is_file():
    for item in json.loads(repair_manifest.read_text()):
        if item["asset"] == args.asset and item["locale"] == args.locale:
            (output / f"repair-{item['revision']}-finished.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
all_assets = [f"screenshot-{n}" for n in range(1, 7)] + ["preview-1", "preview-2"]
all_locales = ["en-US", "es-ES", "fr-FR", "zh-Hans"]
if not args.repair and not args.draft and all((suite_root / asset / locale / "export-result.json").exists()
                          for asset in all_assets for locale in all_locales):
    registry = suite_root / "capture-device.json"
    if registry.exists():
        owned = json.loads(registry.read_text())
        assert owned["owner"] == "Tildone-iPhone-Overnight" and owned["bundle"] == "studio.cuatro.tildone.marketing-phone"
        subprocess.run(["xcrun", "simctl", "shutdown", owned["device"]], check=True, timeout=60)
        subprocess.run(["xcrun", "simctl", "delete", owned["device"]], check=True, timeout=60)
        registry.rename(suite_root / "capture-device-cleaned.json")
print(target)
